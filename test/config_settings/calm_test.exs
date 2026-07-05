defmodule Bonfire.Common.Settings.CalmTest do
  @moduledoc """
  Pins the calm-empowerment engine's contract independently of its consumers: the preset → toggles → sparse-values reducer precedence, the transform vocabulary, and the normalization rules (unknown names dropped, garbage presets → :default).
  """
  use ExUnit.Case, async: false

  alias Bonfire.Common.Settings.Calm
  alias Bonfire.Common.Config

  defmodule ToyTuner do
    @behaviour Calm

    @impl Calm
    def knobs, do: [:alpha, :beta, :gamma]

    @impl Calm
    def baseline, do: %{alpha: 10, beta: 4, gamma: 100}

    @impl Calm
    def normalize_value(_knob, v), do: Bonfire.Common.Types.maybe_to_pos_integer(v)

    @impl Calm
    def toggle_transforms(group_opts) do
      group_opts
      |> Keyword.get(:knobs, [])
      |> Map.new(fn {knob, tf} -> {knob, tf} end)
    end
  end

  @keys [preset: :preset, values: :values, toggles: :toggles]
  @config_keys [:preset, :values, :toggles, :preset_names, :multipliers, :groups]

  setup do
    Config.put([ToyTuner, :preset_names], [:eco, :default, :turbo, :custom])
    Config.put([ToyTuner, :multipliers], eco: 0.5, turbo: 2.0)

    Config.put([ToyTuner, :groups],
      boost_alpha: [name: "Boost alpha", knobs: [alpha: {:preset_level, :turbo}]],
      pin_beta: [name: "Pin beta", knobs: [beta: {:set, 42}]]
    )

    Config.put([ToyTuner, :preset], :default)
    Config.put([ToyTuner, :values], %{})
    Config.put([ToyTuner, :toggles], %{})

    on_exit(fn -> Enum.each(@config_keys, &Config.delete([ToyTuner, &1])) end)
    :ok
  end

  describe "values_for_preset/2 (transforms over the baseline)" do
    test ":default is the baseline, :custom is nil, multipliers scale with min-1 clamp" do
      assert Calm.values_for_preset(ToyTuner, :default) == %{alpha: 10, beta: 4, gamma: 100}
      assert Calm.values_for_preset(ToyTuner, :custom) == nil
      assert Calm.values_for_preset(ToyTuner, :turbo) == %{alpha: 20, beta: 8, gamma: 200}
      # eco halves; a knob that would hit 0 clamps to 1
      Config.put([ToyTuner, :multipliers], eco: 0.1)
      assert Calm.values_for_preset(ToyTuner, :eco) == %{alpha: 1, beta: 1, gamma: 10}
    end

    test "unknown presets (atom, string, garbage) fall back to the baseline/:default" do
      base = Calm.values_for_preset(ToyTuner, :default)
      assert Calm.values_for_preset(ToyTuner, :bogus) == base
      assert Calm.values_for_preset(ToyTuner, "nope") == base
      assert Calm.values_for_preset(ToyTuner, 123) == base
    end
  end

  describe "effective/2 (reducer precedence: preset → toggles → sparse values)" do
    test "a toggle bumps only its knobs, on top of the preset" do
      Config.put([ToyTuner, :preset], :eco)
      Config.put([ToyTuner, :toggles], %{boost_alpha: true})

      effective = Calm.effective(ToyTuner, @keys)

      # alpha at turbo level (the toggle), others at eco
      assert effective[:alpha] == 20
      assert effective[:beta] == 2
      assert effective[:gamma] == 50
    end

    test "a {:set, v} toggle transform applies the literal value" do
      Config.put([ToyTuner, :toggles], %{pin_beta: true})
      assert Calm.effective(ToyTuner, @keys)[:beta] == 42
    end

    test "sparse values win over both preset and toggles" do
      Config.put([ToyTuner, :preset], :turbo)
      Config.put([ToyTuner, :toggles], %{boost_alpha: true, pin_beta: true})
      Config.put([ToyTuner, :values], %{alpha: 7, beta: 7})

      effective = Calm.effective(ToyTuner, @keys)
      assert effective == %{alpha: 7, beta: 7, gamma: 200}
    end

    test ":custom preset = sparse values only" do
      Config.put([ToyTuner, :preset], :custom)
      Config.put([ToyTuner, :values], %{gamma: 5})

      assert Calm.effective(ToyTuner, @keys) == %{gamma: 5}
    end
  end

  describe "normalization" do
    test "unknown knobs and invalid values are dropped; string names/values accepted" do
      Config.put([ToyTuner, :values], %{"alpha" => "3", "not_a_knob" => 9, beta: 0, gamma: -1})
      assert Calm.current_values(ToyTuner, :values) == %{alpha: 3}
    end

    test "unknown toggle groups dropped, form-input truthiness coerced" do
      Config.put([ToyTuner, :toggles], %{
        "boost_alpha" => "true",
        "nope" => true,
        pin_beta: "false"
      })

      assert Calm.current_toggles(ToyTuner, :toggles) == %{boost_alpha: true, pin_beta: false}
    end

    test "garbage stored preset normalizes to :default" do
      Config.put([ToyTuner, :preset], "bogus")
      assert Calm.current_preset(ToyTuner, :preset) == :default
      Config.put([ToyTuner, :preset], %{weird: true})
      assert Calm.current_preset(ToyTuner, :preset) == :default
    end
  end
end
