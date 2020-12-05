defmodule Bonfire.Common.Errors.InvalidCredentialError do
  @moduledoc "The user was not found or the password was wrong"
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @doc "Create a new InvalidCredentialError"
  @spec new() :: t
  def new() do
    %__MODULE__{
      message: "We couldn't find an account with these details",
      code: "invalid_credential",
      status: 404
    }
  end
end
