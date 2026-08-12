defmodule Bonfire.Common.ObjectTypeOwnershipTest do
  @moduledoc """
  Object type names belong to the extension that declares the type, not to `bonfire_common`. A translator working on `bonfire_posts` should see "post" beside the rest of that extension's strings.

  The owner is derived rather than declared: take the schema's context module and use its OTP app, falling back to the schema's own app. Emission and lookup must derive it identically or the lookup silently misses, which is what the round-trip test at the bottom pins.
  """
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.Types

  describe "object_type_owner/1" do
    test "resolves through the context module to the feature extension" do
      assert Types.object_type_owner(Bonfire.Data.Social.Post) |> app_of() == :bonfire_posts
      assert Types.object_type_owner(Bonfire.Data.Identity.User) |> app_of() == :bonfire_me
      assert Types.object_type_owner(Bonfire.Data.Social.Message) |> app_of() == :bonfire_messages
    end

    test "falls back to the schema's own app when no context module names it" do
      # `geolocation` has no context module declaring it, and its schema's app is still the right answer
      assert Types.object_type_owner(Bonfire.Geolocate.Geolocation) |> app_of() ==
               :bonfire_geolocate
    end

    test "returns nil for something that is not an object type" do
      refute Types.object_type_owner(NotARealModule)
    end
  end

  describe "all_object_type_names_by_owner/0" do
    test "groups the names under the module whose domain they will be extracted into" do
      # grouped by owner *module*, and one app can own several (bonfire_me has Users, Profiles and Characters), which is fine since every one of them resolves to the same gettext domain
      assert "post" in names_for_app(:bonfire_posts)
      assert "Delete this post" in names_for_app(:bonfire_posts)
      assert "user" in names_for_app(:bonfire_me)
      assert "message" in names_for_app(:bonfire_messages)

      refute "post" in names_for_app(:bonfire_common)
    end

    test "covers the same names as all_object_type_names/0" do
      flat =
        Types.all_object_type_names_by_owner() |> Enum.flat_map(fn {_owner, names} -> names end)

      assert Enum.sort(Enum.uniq(flat)) == Enum.sort(Enum.uniq(Types.all_object_type_names()))
    end
  end

  describe "emission and lookup agree" do
    test "the domain a name is emitted into is the one object_type_display/1 searches" do
      # the invariant that fails silently: if these ever diverge the string renders in English with
      # no error anywhere
      for schema <- [Bonfire.Data.Social.Post, Bonfire.Data.Identity.User] do
        emitted_under =
          Types.all_object_type_names_by_owner()
          |> Enum.find_value(fn {owner, names} ->
            name = Types.module_to_human_readable(schema) |> to_string() |> String.downcase()
            if name in names, do: owner
          end)

        assert emitted_under == Types.object_type_owner(schema)
      end
    end
  end

  defp app_of(nil), do: nil
  defp app_of(module), do: Application.get_application(module)

  defp names_for_app(app) do
    Types.all_object_type_names_by_owner()
    |> Enum.flat_map(fn {owner, names} -> if app_of(owner) == app, do: names, else: [] end)
  end
end
