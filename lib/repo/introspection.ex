# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Repo.Introspection do
  @moduledoc """
  Utilities for introspecting our use of Ecto within Bonfire
  """

  @spec ecto_schema_modules() :: [atom()]
  @doc """
  Return a list of Ecto Schema modules in our OTP application
  Note: not all of these will represent database tables
  """
  def ecto_schema_modules(),
    do: Enum.filter(app_modules(), &is_ecto_schema_module?/1)

  @doc """
  Lists all modules in the CommonsPub OTP application
  """
  def app_modules() do
    otp_app = Application.get_env(:bonfire_common, :otp_app)
    Application.spec(otp_app, :modules) || all_modules()
  end

  def all_modules() do
    :code.all_loaded()
      # |> IO.inspect(limit: :infinity)
      |> Enum.filter(fn {mod, _} -> "#{mod}" =~ ~r{^[A-Z]} end)
      |> Enum.map(fn {mod, _} -> mod end)
      # |> Enum.map(fn mod -> hd(Module.split(mod)) end)
      |> Enum.uniq
  end

  @spec ecto_schema_table(atom()) :: binary() | nil
  @doc """
  Queries an ecto schema module by name for the database table it represents
  """
  def ecto_schema_table(module) when is_atom(module),
    do: apply(module, :__schema__, [:source])

  @spec is_ecto_schema_module?(atom) :: boolean()
  @doc "true if the given atom names an Ecto Schema module"
  def is_ecto_schema_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 1)
  end

  def is_ecto_schema_module?(_), do: false

end
