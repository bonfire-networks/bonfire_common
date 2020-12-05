# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Errors.MalformedAuthorizationHeaderError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          message: binary,
          code: binary,
          status: integer
        }

  @spec new() :: t
  @doc "Create a new MalformedAuthorizationHeaderError"
  def new() do
    %__MODULE__{
      message: "Bad request - malformed Authorization header",
      code: "bad_request",
      status: 400
    }
  end
end
