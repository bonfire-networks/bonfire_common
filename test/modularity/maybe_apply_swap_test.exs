defmodule Bonfire.Common.MaybeApplySwapTest do
  @moduledoc """
  A module's `:modularity` setting can disable it or swap in a replacement. `maybe_apply/4` must honour both, as `maybe_module/2` does: it calls the replacement when the module is swapped. That also lets a test swap a module for one process with `Process.put`, without recompiling it.

  `Bonfire.Common.Text` is swapped for `Bonfire.Common.Enums`, and the function called (`filter_empty/2`) exists only in `Enums`, so the result shows which module ran.
  """
  use Bonfire.Common.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Common.Extend
  alias Bonfire.Common.Utils

  @swap_key [:bonfire_common, Bonfire.Common.Text, :modularity]

  setup do
    Extend.clear_modularity_cache(Bonfire.Common.Text)
    :ok
  end

  defp call_text_filter_empty(opts \\ []) do
    Utils.maybe_apply(
      Bonfire.Common.Text,
      :filter_empty,
      [[], :empty],
      [fallback_return: :not_applied] ++ opts
    )
  end

  test "without a swap, the module's own (missing) function is not applied" do
    assert call_text_filter_empty() == :not_applied
  end

  test "a swapped module applies the replacement" do
    Process.put(@swap_key, Bonfire.Common.Enums)

    assert Extend.maybe_module(Bonfire.Common.Text) == Bonfire.Common.Enums,
           "precondition: the swap is set"

    assert call_text_filter_empty() == :empty
  end

  test "a disabled module is not applied" do
    Process.put(@swap_key, :disabled)

    assert call_text_filter_empty() == :not_applied
  end

  test "force_module: true applies the module given, ignoring the swap" do
    Process.put(@swap_key, Bonfire.Common.Enums)

    assert call_text_filter_empty(force_module: true) == :not_applied
  end
end
