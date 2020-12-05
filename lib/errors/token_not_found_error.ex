# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.TokenNotFoundError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @doc "Create a new TokenNotFoundError"
  @spec new() :: t
  def new() do
    %__MODULE__{
      message: "This token was not found, please generate a fresh one.",
      code: "token_not_found",
      status: 403
    }
  end
end
