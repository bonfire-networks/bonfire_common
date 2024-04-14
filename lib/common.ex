defmodule Bonfire.Common do
  @moduledoc """
  A library of common utils and helpers used across Bonfire extensions

  Refer to the [README](https://doc.bonfirenetworks.org/bonfire_common.html)
  """

  def maybe_fallback(nil, nil), do: nil
  def maybe_fallback(nil, fun) when is_function(fun), do: fun.()
  def maybe_fallback(nil, fallback), do: fallback
  def maybe_fallback(val, _), do: val
end
