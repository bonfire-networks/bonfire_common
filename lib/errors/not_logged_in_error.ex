# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.NotLoggedInError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @doc "Create a new NotLoggedInError"
  @spec new() :: t
  def new() do
    %__MODULE__{
      message: "You need to log in first.",
      code: "needs_login",
      status: 403
    }
  end
end
