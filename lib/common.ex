defmodule Bonfire.Common do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  def maybe_fallback(nil, nil), do: nil
  def maybe_fallback(nil, fun) when is_function(fun), do: fun.()
  def maybe_fallback(nil, fallback), do: fallback
  def maybe_fallback(val, _), do: val
end
