defmodule Bonfire.Common.ModuleToggleLookupsTest do
  @moduledoc """
  Extensions are enabled and disabled at runtime, at instance level and for a single user. These pin what the registry lookups do when that happens: the `ContextModule` lookup re-checks enablement on every call (the refactor of `ExtensionBehaviour.apply_modules_cached/2` relies on it), and `Extend.module_enabled?/2` answers per user.
  """
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  alias Bonfire.Common.ContextModule
  alias Bonfire.Common.Extend
  alias Bonfire.Common.Testing

  describe "ContextModule.maybe_apply" do
    test "runs the context module's function, answers with an error while its extension is disabled, and runs it again once enabled" do
      # `schema_module/0` is the callback `Bonfire.Posts` declares the schema with, so the lookup of this schema's context module finds it
      run = fn -> ContextModule.maybe_apply(Bonfire.Data.Social.Post, :schema_module) end

      # the positive first: it resolves while enabled
      assert Bonfire.Data.Social.Post = run.()

      assert {:error, _} = Testing.with_extension_disabled(:bonfire_posts, run)

      assert Bonfire.Data.Social.Post = run.()
    end
  end

  describe "Extend.module_enabled?/2 per user" do
    # each check runs in a fresh process, since the result is cached per process
    defp in_fresh_process(fun), do: Task.async(fun) |> Task.await()

    defp user_with_settings(id, json),
      do: %{id: id, settings: %Bonfire.Data.Identity.Settings{json: json}}

    test "an extension disabled in one user's settings is disabled for that user only" do
      disabled_for =
        user_with_settings("toggle_user_off", %{bonfire_posts: %{modularity: :disabled}})

      other = user_with_settings("toggle_user_on", %{})

      assert in_fresh_process(fn ->
               Extend.module_enabled?(Bonfire.Posts, current_user: other)
             end)

      refute in_fresh_process(fn ->
               Extend.module_enabled?(Bonfire.Posts, current_user: disabled_for)
             end)
    end

    # A characterisation of a known limit, not a wanted behaviour: the per-process modularity cache is keyed by module only ([extend.ex `get_modularity/2`]), so the first check in a process decides, whoever it was for.
    test "a check without a user earlier in the same process decides for later per-user checks" do
      disabled_for =
        user_with_settings("toggle_user_off", %{bonfire_posts: %{modularity: :disabled}})

      assert in_fresh_process(fn ->
               Extend.module_enabled?(Bonfire.Posts)
               Extend.module_enabled?(Bonfire.Posts, current_user: disabled_for)
             end)
    end
  end
end
