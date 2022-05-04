# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Repo.Utils do
  @moduledoc "Helper functions for changesets"

  import EctoSparkles.Changesets
  alias Ecto.Changeset
  alias Bonfire.Mailer.Checker

  # @doc "Generates the primary ID for an object, and sets the canonical URL based on that"
  # def cast_object(changeset) do
  #   cast_object(changeset, Changeset.get_field(changeset, :canonical_url))
  # end

  # defp cast_object(cs, x) when not is_nil(x), do: cs

  # defp cast_object(cs, _) do
  #   id = Pointers.ULID.generate()
  #   Changeset.put_change(cs, :id, id)
  #   Changeset.put_change(cs, :canonical_url, ActivityPub.Utils.object_url(%{id: id}))
  # end

  defmacro match_admin() do
    quote do
      %{
        instance_admin: %{is_instance_admin: true}
      }
    end
  end

  @spec validate_email(Changeset.t(), atom) :: Changeset.t()
  @doc "Validates an email for correctness"
  def validate_email(changeset, field) do
    with {:ok, email} <- Changeset.fetch_change(changeset, field),
         {:error, reason} <- Checker.validate_email(email) do
      message = validate_email_message(reason)
      Changeset.add_error(changeset, field, message, validation: reason)
    else
      _ -> changeset
    end
  end

  @spec validate_email_domain(Changeset.t(), atom) :: Changeset.t()
  def validate_email_domain(changeset, field) do
    with {:ok, domain} <- Changeset.fetch_change(changeset, field),
         {:error, reason} <- Checker.validate_domain(domain) do
      message = validate_email_message(reason)
      Changeset.add_error(changeset, field, message, validation: reason)
    else
      _ -> changeset
    end
  end

  defp validate_email_message(:format), do: "is of the wrong format"
  defp validate_email_message(:mx), do: "failed an MX record check"

  @spec change_public(Changeset.t()) :: Changeset.t()
  @doc "Keeps published_at in accord with is_public"
  def change_public(%Changeset{} = changeset),
    do: change_synced_timestamp(changeset, :is_public, :published_at)

  @spec change_muted(Changeset.t()) :: Changeset.t()
  @doc "Keeps muted_at in accord with is_muted"
  def change_muted(%Changeset{} = changeset),
    do: change_synced_timestamp(changeset, :is_muted, :muted_at)

  @spec change_disabled(Changeset.t()) :: Changeset.t()
  @doc "Keeps disabled_at in accord with is_disabled"
  def change_disabled(%Changeset{} = changeset),
    do: change_synced_timestamp(changeset, :is_disabled, :disabled_at)


end
