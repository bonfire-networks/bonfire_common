# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.TableNotFoundError do
  @enforce_keys [:table]
  defstruct @enforce_keys

  @type t :: %__MODULE__{table: term}

  @spec new(term) :: t
  def new(table), do: %__MODULE__{table: table}
end
