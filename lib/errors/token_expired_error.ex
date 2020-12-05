# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.TokenExpiredError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @spec new() :: t
  @doc "Create a new TokenExpiredError"
  def new() do
    %__MODULE__{
      message: "This access token has expired, please generate a fresh one.",
      code: "token_expired",
      status: 403
    }
  end
end
