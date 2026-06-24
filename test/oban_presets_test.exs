defmodule Bonfire.Common.ObanPresetsTest do
  use ExUnit.Case, async: false

  alias Bonfire.Common.ObanPresets
  alias Bonfire.Common.Config

  setup do
    on_exit(fn ->
      Config.delete([ObanPresets, :preset])
      Config.delete([ObanPresets, :queues])
      Config.delete([ObanPresets, :managed_queues])
      Config.delete([ObanPresets, :prioritised_groups])
    end)

    :ok
  end

  describe "limits_for/1 (env-relative multipliers over all managed queues)" do
    test ":default is the env baseline, covering every managed queue" do
      limits = ObanPresets.limits_for(:default)
      assert Map.keys(limits) |> Enum.sort() == Enum.sort(ObanPresets.managed_queues())
      assert Enum.all?(limits, fn {_q, l} -> is_integer(l) and l >= 1 end)
    end

    test ":eco halves each queue's baseline (min 1)" do
      default = ObanPresets.limits_for(:default)
      eco = ObanPresets.limits_for(:eco)

      assert Map.keys(eco) == Map.keys(default)
      for {queue, n} <- default, do: assert(eco[queue] == max(1, trunc(n * 0.5)))
    end

    test ":turbo doubles each queue's baseline" do
      default = ObanPresets.limits_for(:default)
      turbo = ObanPresets.limits_for(:turbo)

      for {queue, n} <- default, do: assert(turbo[queue] == n * 2)
    end

    test "presets cover non-federation queues too (e.g. :import), not just federation" do
      # only meaningful when the Oban config actually has these queues
      if :import in ObanPresets.managed_queues() do
        assert Map.has_key?(ObanPresets.limits_for(:eco), :import)
        refute :import in ObanPresets.federation_queues()
      end
    end

    test ":custom has no base (overrides-only)" do
      assert ObanPresets.limits_for(:custom) == nil
    end

    test "accepts the preset as a string" do
      assert ObanPresets.limits_for("eco") == ObanPresets.limits_for(:eco)
    end

    test "an unknown preset falls back to the default baseline" do
      assert ObanPresets.limits_for(:bogus) == ObanPresets.limits_for(:default)
      assert ObanPresets.limits_for("nope") == ObanPresets.limits_for(:default)
    end

    test "current_preset normalises an unknown/garbage stored value to :default" do
      Config.put([ObanPresets, :preset], "bogus")
      assert ObanPresets.current_preset() == :default

      Config.put([ObanPresets, :preset], 123)
      assert ObanPresets.current_preset() == :default
    end
  end

  describe "effective_limits/0 (preset + sparse overrides)" do
    test "merges a sparse per-queue override on top of the preset base" do
      Config.put([ObanPresets, :preset], :eco)
      Config.put([ObanPresets, :queues], %{federator_outgoing: 7})

      effective = ObanPresets.effective_limits()

      # the override wins for that one queue...
      assert effective[:federator_outgoing] == 7
      # ...while the rest stay at the eco base
      assert effective[:federator_incoming] == ObanPresets.limits_for(:eco)[:federator_incoming]
    end

    test "custom preset with overrides applies only the overrides" do
      Config.put([ObanPresets, :preset], :custom)
      Config.put([ObanPresets, :queues], %{federator_outgoing: 5})

      assert ObanPresets.effective_limits() == %{federator_outgoing: 5}
    end

    test "ignores unknown queue names and non-positive limits in overrides" do
      Config.put([ObanPresets, :preset], :custom)
      Config.put([ObanPresets, :queues], %{"not_a_queue" => 3, federator_outgoing: 0})

      assert ObanPresets.effective_limits() == %{}
    end
  end

  describe "merge_into_config/1 (boot path)" do
    test "rescales the Oban config's :queues to the effective preset (incl. non-federation)" do
      Config.put([ObanPresets, :preset], :eco)
      Config.put([ObanPresets, :queues], %{})

      base = [repo: SomeRepo, queues: [federator_outgoing: 9, import: 9, unmanaged_extra: 3]]
      merged = ObanPresets.merge_into_config(base)
      queues = Keyword.fetch!(merged, :queues)
      eco = ObanPresets.limits_for(:eco)

      # every managed queue is rescaled to the eco value (federation AND import)...
      assert queues[:federator_outgoing] == eco[:federator_outgoing]
      assert queues[:import] == eco[:import]
      # ...a queue not in the managed set is left as-is
      assert queues[:unmanaged_extra] == 3
    end
  end

  describe "group prioritisation (Layer 2)" do
    test "a prioritised group runs its queues at the turbo (2x) level on top of the preset" do
      Config.put([ObanPresets, :preset], :default)
      Config.put([ObanPresets, :prioritised_groups], %{interactions: true})

      effective = ObanPresets.effective_limits()
      default = ObanPresets.limits_for(:default)
      turbo = ObanPresets.limits_for(:turbo)

      # the interactions group has TWO queues — both must be prioritised
      prioritised = ObanPresets.group_queues(:interactions)
      assert :federator_incoming_mentions in prioritised
      assert :federator_incoming_follows in prioritised

      for queue <- prioritised, do: assert(effective[queue] == turbo[queue])

      # a queue not in the prioritised group stays at the preset baseline
      assert effective[:federator_outgoing] == default[:federator_outgoing]
    end

    test "a non-prioritised group leaves its queues at the preset baseline" do
      Config.put([ObanPresets, :preset], :default)
      Config.put([ObanPresets, :prioritised_groups], %{interactions: false})

      effective = ObanPresets.effective_limits()
      default = ObanPresets.limits_for(:default)

      for queue <- ObanPresets.group_queues(:interactions),
          do: assert(effective[queue] == default[queue])
    end

    test "ignores unknown groups and treats non-truthy values as off" do
      Config.put([ObanPresets, :preset], :default)

      Config.put([ObanPresets, :prioritised_groups], %{
        "not_a_group" => true,
        interactions: "false"
      })

      # unknown group dropped; "false" string is off
      assert ObanPresets.current_priorities() == %{interactions: false}
      assert ObanPresets.prioritised_queues() == []

      default = ObanPresets.limits_for(:default)
      effective = ObanPresets.effective_limits()
      for q <- ObanPresets.group_queues(:interactions), do: assert(effective[q] == default[q])
    end

    test "accepts string-keyed truthy values from form input" do
      Config.put([ObanPresets, :preset], :default)
      Config.put([ObanPresets, :prioritised_groups], %{"interactions" => "true"})

      assert ObanPresets.current_priorities() == %{interactions: true}
    end
  end

  describe "apply_preset/1 / apply_current/0 (no Oban running)" do
    test "is a safe no-op when Oban isn't running" do
      assert ObanPresets.apply_preset(:eco) == :ok
      assert ObanPresets.apply_current() == :ok
    end
  end
end
