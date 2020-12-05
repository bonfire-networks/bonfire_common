# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.UserDisabledError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @doc "Create a new UserDisabledError"
  @spec new() :: t
  def new() do
    %__MODULE__{
      message: "This user account is disabled by the instance administrator.",
      code: "user_disabled",
      status: 403
    }
  end
end
