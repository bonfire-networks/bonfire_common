defmodule Bonfire.Common.Settings.IdCutoffsTest do
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.Settings.IdCutoffs

  setup do
    original = Application.get_env(:bonfire_common, IdCutoffs)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:bonfire_common, IdCutoffs)
        v -> Application.put_env(:bonfire_common, IdCutoffs, v)
      end
    end)

    :ok
  end

  # deterministic chronological IDs: explicit ms timestamps avoid same-ms random-bit flakiness
  defp uid_at(ms_offset),
    do: Needle.ULID.generate(System.system_time(:millisecond) + ms_offset)

  defp put_config(key, value) do
    Application.put_env(
      :bonfire_common,
      IdCutoffs,
      Keyword.put(Application.get_env(:bonfire_common, IdCutoffs) || [], key, value)
    )
  end

  describe "after?/2" do
    test "false when no cutoff is recorded" do
      refute IdCutoffs.after?(:some_unset_cutoff_key, uid_at(0))
    end

    test "compares chronologically against a recorded cutoff" do
      cutoff = uid_at(0)
      put_config(:recorded, test_primed_cutoff_key: cutoff)

      assert IdCutoffs.after?(:test_primed_cutoff_key, uid_at(10_000))
      refute IdCutoffs.after?(:test_primed_cutoff_key, cutoff)
      refute IdCutoffs.after?(:test_primed_cutoff_key, uid_at(-10_000))
    end

    test "false for non-binary ids" do
      put_config(:recorded, test_primed_cutoff_key: uid_at(0))
      refute IdCutoffs.after?(:test_primed_cutoff_key, nil)
      refute IdCutoffs.after?(:test_primed_cutoff_key, %{})
    end
  end

  describe "cutoff/1" do
    test "nil when unset, blank or nil-recorded" do
      assert IdCutoffs.cutoff(:some_unset_cutoff_key) == nil

      put_config(:recorded, test_blank_cutoff_key: "", test_nil_cutoff_key: nil)
      assert IdCutoffs.cutoff(:test_blank_cutoff_key) == nil
      assert IdCutoffs.cutoff(:test_nil_cutoff_key) == nil
    end
  end

  describe "keys_to_record/0" do
    test "returns keys of the :record keyword list, filtering falsy (unregistered) ones" do
      put_config(:record, some_cutoff: true, disabled_cutoff: false)

      assert IdCutoffs.keys_to_record() == [:some_cutoff]
    end
  end

  describe "ensure_recorded/1" do
    test "records a valid UID cutoff once, then is idempotent" do
      key = :test_idempotent_cutoff_key

      assert {:ok, cutoff} = IdCutoffs.ensure_recorded(key)
      assert Needle.UID.valid?(cutoff)

      # second call must return the SAME cutoff, not mint a new one
      assert {:ok, ^cutoff} = IdCutoffs.ensure_recorded(key)
      assert IdCutoffs.cutoff(key) == cutoff

      # ids generated after recording sort after the cutoff
      assert IdCutoffs.after?(key, uid_at(10_000))
    end
  end
end
