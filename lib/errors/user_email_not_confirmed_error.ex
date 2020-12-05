# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.UserEmailNotConfirmedError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @doc "Create a new UserEmailNotConfirmedError"
  @spec new() :: t
  def new() do
    %__MODULE__{
      message: "You must confirm your email address first.",
      code: "email_not_confirmed",
      status: 403
    }
  end
end
