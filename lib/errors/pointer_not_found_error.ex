# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.PointerNotFoundError do
  @enforce_keys [:id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{id: term()}

  @spec new(term()) :: t()
  @doc "Create a new PointerNotFoundError with the given Pointer id"
  def new(id), do: %__MODULE__{id: id}
end
