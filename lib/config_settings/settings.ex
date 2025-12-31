defmodule Bonfire.Common.Settings do
  @moduledoc """
  Helpers to get app/extension settings, or to override a config key.

  This module provides functionality for fetching and updating application and extension settings. The process for fetching settings follows a bottom-up system of overrides:

  1. **User-specific settings:** 
    If `opts` contains `current_user`, settings are fetched from the user's settings.

  2. **Account-specific settings:** 
    If no settings are found for the user and `opts` contains `current_account`, settings are fetched from the account's settings.

  3. **Instance-specific settings:** 
     NOTE: Changes to instance settings are stored both in the database and the OTP app config/application environment, and are loaded from the DB into OTP config at app startup by `Bonfire.Common.Settings.LoadInstanceConfig`.

  4. **Default OTP config:** 
    If no settings are found at the user or account level, instance settings are loaded from OTP application configuration via `Bonfire.Common.Config`.

  5. **Default value:** 
    If no settings are found in the previous steps, the provided `default` value is returned.

  """

  import Bonfire.Common.Utils
  use Arrows
  Bonfire.Common.Utils.__common_utils__()
  Bonfire.Common.Utils.__localise__()
  use Bonfire.Common.ConfigSettingsRegistration
  use Bonfire.Common.Repo
  # import Bonfire.Me.Integration
  alias Bonfire.Common.Extend
  use Bonfire.Common.Config

  @doc """
  Get settings value for a config key (optionally from a specific OTP app or Bonfire extension)

  These two calls have the same result (i.e. specifying a module as the first key will add the OTP app of that module as the first key):
  `get([:bonfire_me, Bonfire.Me.Users])`
  `get(Bonfire.Me.Users)`

  Same with these two (i.e. not specifying a module or app as the first key will default to the main OTP app):
  `get([:random_atom, :sub_key])`
  `get([:bonfire, :random_atom, :sub_key])`
  """

  @doc """
  Retrieves the setting value for a given config key or nested key path.

  As explained above, this function checks settings in the following order:
  1. **User settings** (if `opts` contains `current_user`).
  2. **Account settings** (if `opts` contains `current_account` and no user settings are found).
  3. **Instance settings**.
  4. **OTP application config (includes compile time and runtime config)**.
  5. **Default value** (if no settings are found).

  ## Examples

      iex> get(:test_key)
      "test_value"

      iex> get([:non_existing_extension, :sub_key])
      nil

      iex> get(:non_existing_key, "default")
      "default"

      > get(:otp_app)
      :bonfire

      > get([:bonfire_common, :otp_app])
      :bonfire
      
      iex> get([Bonfire.Common.Localise.Cldr, :gettext])
      Bonfire.Common.Localise.Gettext

      > get([:bonfire_common, Bonfire.Common.Localise.Cldr, :gettext])
      Bonfire.Common.Localise.Gettext

  ## Options
    * `:otp_app` - Optionally specifies the OTP application for which to fetch settings. If none is specified, it will look at the (first) key and check if it references a known OTP application (i.e. an extension) or a module, in which case it will fetch settings from that application. Otherwise it will look in the configured top-level OTP app (see `Config.top_level_otp_app/0`). 
    * `:scope` - Optionally defines the scope for settings retrieval (e.g., `:user`, `:account`, or `:instance`).
  """
  Bonfire.Common.ConfigSettingsRegistration.def_registered_macro(
    :get,
    :__get__,
    :settings,
    {:keys, :default, :opts},
    __MODULE__
  )

  def __get__(key, default \\ nil, opts \\ [])

  def __get__(keys, default, opts) when is_list(keys) do
    opts = Utils.to_options(opts)

    {otp_app, keys_tree} =
      case opts[:otp_app] do
        nil ->
          Config.keys_tree(keys)
          |> List.pop_at(0)

        otp_app ->
          {otp_app, keys}
      end

    debug(keys_tree, "Get settings in #{inspect(otp_app)} for", trace_skip: 1)

    get_settings(keys_tree, default, otp_app, opts)
  end

  def __get__(key, default, opts) do
    __get__([key], default, opts)
  end

  if Application.compile_env(:bonfire, :env) == :test do
    # NOTE: enables using `ProcessTree` in test env, eg. `Process.put([:bonfire_common, :my_key], :value)`
    defp get_settings(keys, default, otp_app, opts) when is_list(keys),
      do: get_for_process([otp_app] ++ keys) || do_get_settings(keys, default, otp_app, opts)

    defp get_settings(key, default, otp_app, opts),
      do: get_for_process([otp_app, key]) || do_get_settings(key, default, otp_app, opts)
  else
    defp get_settings(keys, default, otp_app, opts),
      do: do_get_settings(keys, default, otp_app, opts)
  end

  def get_for_process(keys), do: ProcessTree.get(keys)

  defp do_get_settings(keys, default, otp_app, opts) do
    case get_for_ext(otp_app, opts) do
      [] ->
        default

      nil ->
        default

      result ->
        if keys != [] do
          do_get_in(result, keys, default)
          # |> debug()
        else
          maybe_fallback(result, default)
        end
    end
  end

  @doc """
  Retrieves the setting value for a given config key like in `get/3`, but raises an exception if the key is not found, ensuring that the setting must be present.

  ## Examples

      iex> get!(:test_key)
      "test_value"

      iex> get!(:non_existing_key)
      ** (RuntimeError) Missing setting or configuration value: :non_existing_key

  """
  Bonfire.Common.ConfigSettingsRegistration.def_registered_macro(
    :get!,
    :__get__!,
    :config,
    {:keys, :opts, :default},
    __MODULE__
  )

  def __get__!(key, opts \\ [], _default \\ nil) do
    case get(key, nil, opts) do
      nil ->
        raise "Missing setting or configuration value: #{inspect(key, pretty: true)}"

      value ->
        value
    end
  end

  @doc """
  Retrieves a value from nested data structures using a list of keys.

  This function supports various data types and handles errors gracefully:
  - For keyword lists, it uses Elixir's built-in `get_in/2` function
  - For maps and lists, it uses a custom traversal function `ed/3`
  - Falls back to the provided default value when the key path doesn't exist

  ## Examples

      iex> do_get_in([foo: [bar: "value"]], [:foo, :bar], "default")
      "value"

      iex> do_get_in(%{foo: %{bar: "value"}}, [:foo, :bar], "default")
      "value"

      iex> do_get_in([foo: %{bar: "value"}], [:foo, :bar], "default")
      "value"

      iex> do_get_in(%{foo: [bar: "value"]}, [:foo, :bar], "default")
      "value"

      iex> do_get_in([foo: [bar: "value"]], [:foo, :missing], "default")
      "default"

      iex> do_get_in(%{foo: %{bar: "value"}}, [:foo, :missing], "default")
      "default"

      iex> do_get_in("invalid", [:foo], "default")
      "default"

  """
  def do_get_in(result, keys_tree, default) when is_list(keys_tree) do
    debug(keys_tree, "lookup settings", trace_skip: 2)

    if is_list(result) and Keyword.keyword?(result) do
      # Enums.get_in_access_keys(result, keys_tree, :not_set)
      get_in(result, keys_tree)
      |> maybe_fallback(default)
      |> debug("settings for #{inspect(keys_tree)}", trace_skip: 2)
    else
      if is_map(result) or is_list(result) do
        ed(result, keys_tree, nil)
        |> maybe_fallback(default)
        |> debug("settings for #{inspect(keys_tree)}", trace_skip: 2)
      else
        error(result, "Settings are in an invalid structure and can't be used", trace_skip: 2)
        default
      end
    end
  rescue
    error in ArgumentError ->
      error(error, "get_in failed, try with `ed`", trace_skip: 2)

      ed(result, keys_tree, nil)
      |> maybe_fallback(default)

    error in FunctionClauseError ->
      error(error, "get_in failed, try with `ed`", trace_skip: 2)

      ed(result, keys_tree, nil)
      |> maybe_fallback(default)
  end

  def do_get_in(_result, keys_tree, default) do
    error(keys_tree, "Invalid keys_tree, cannot lookup the setting")
    default
  end

  defp maybe_fallback(val, fallback, fallback_value \\ nil)
  defp maybe_fallback(fallback_value, fallback, fallback_value), do: fallback
  defp maybe_fallback(val, _, _), do: val

  defp the_otp_app(module_or_otp_app),
    do: Extend.maybe_extension_loaded!(module_or_otp_app) || Config.top_level_otp_app()

  defp get_for_ext(module_or_otp_app, opts \\ []) do
    if e(opts, :one_scope_only, false) do
      the_otp_app(module_or_otp_app)
      |> fetch_one_scope(opts)
    else
      get_merged_ext(module_or_otp_app, opts)
    end
  end

  @doc """
  Get all config keys/values for a Bonfire extension or OTP app
  """
  defp get_merged_ext(module_or_otp_app, opts \\ []) do
    the_otp_app(module_or_otp_app)
    |> fetch_all_scopes(opts)
    |> deep_merge_reduce()

    # |> debug("domino-merged settings for #{inspect(otp_app)}")
  end

  # defp get_merged_ext!(module_or_otp_app, opts \\ []) do
  #   case get_merged_ext(module_or_otp_app, opts) do
  #     nil ->
  #       raise "Missing settings or configuration for extension: #{inspect(module_or_otp_app, pretty: true)}"
  #       []

  #     value ->
  #       value
  #   end
  # end

  # @doc "Fetch all config & settings, both from Mix.Config and DB. Order matters! current_user > current_account > instance > Config"
  defp fetch_all_scopes(otp_app, opts) do
    # debug(opts, "opts")
    current_user = current_user(opts)
    current_user_id = id(current_user)
    current_account = current_account(opts)
    current_account_id = id(current_account)
    scope = e(opts, :scope, nil) || if is_atom(opts), do: opts
    scope_id = id(scope)
    # debug(current_user, "current_user")
    # debug(current_account, "current_account")

    if (scope != :instance and not is_map(current_user) and not is_map(current_account)) or
         (is_struct(current_user) and Map.has_key?(current_user, :settings) and
            not Ecto.assoc_loaded?(current_user.settings)) or
         (is_struct(current_account) and Map.has_key?(current_account, :settings) and
            not Ecto.assoc_loaded?(current_account.settings)) do
      warn(
        otp_app,
        "You should pass a current_user and/or current_account (with settings assoc preloaded) in `opts` depending on what scope of Settings you want for OTP app",
        trace_limit: 7
      )

      # debug(opts)
    end

    #  |> debug()
    ([
       Config.get_all(otp_app)
     ] ++
       [
         if(current_account_id,
           do:
             maybe_fetch(current_account, opts)
             |> settings_data_for_app(otp_app)
         )
       ] ++
       [
         if(current_user_id,
           do:
             maybe_fetch(current_user, opts)
             |> settings_data_for_app(otp_app)
           #  |> debug()
         )
         #  |> debug()
       ] ++
       if(is_map(scope) and scope_id != current_user_id and scope_id != current_account_id,
         do: [
           maybe_fetch(scope, opts)
           |> settings_data_for_app(otp_app)
         ],
         else: []
       ))
    # |> debug()
    |> filter_empty([])

    # |> debug("list of different configs and settings for #{inspect(otp_app)}")
  end

  defp fetch_one_scope(otp_app, opts) do
    # debug(opts, "opts")
    current_user = current_user(opts)
    current_account = current_account(opts)
    scope = e(opts, :scope, nil)

    cond do
      is_map(scope) ->
        maybe_fetch(scope, opts)
        |> settings_data_for_app(otp_app)

      not is_nil(current_user) ->
        debug("for user")

        maybe_fetch(current_user, opts)
        |> settings_data_for_app(otp_app)

      not is_nil(current_account) ->
        debug("for account")

        maybe_fetch(current_account, opts)
        |> settings_data_for_app(otp_app)

      true ->
        debug("for instance")
        Config.get_all(otp_app)
    end

    # |> debug("config/settings for #{inspect(otp_app)}")
  end

  defp settings_data(%{json: %{} = json_data} = _settings) when json_data != %{} do
    prepare_from_json(json_data)
  end

  defp settings_data(_) do
    []
  end

  defp settings_data_for_app(settings, otp_app) do
    settings_data(settings)
    |> e(otp_app, nil)
  end

  # not including this line in fetch_all_scopes because load_instance_settings preloads it into Config
  # [load_instance_settings() |> e(otp_app, nil) ] # should already be loaded in Config

  def load_instance_settings() do
    maybe_fetch(instance_scope(), preload: true)
    |> settings_data()
  end

  defp maybe_fetch(scope, opts \\ [])

  defp maybe_fetch({_scope, scoped} = _scope_tuple, opts) do
    maybe_fetch(scoped, opts)
  end

  defp maybe_fetch(scope_id, opts) when is_binary(scope_id) do
    if e(opts, :preload, nil) do
      do_fetch(scope_id)
      # |> debug("fetched")
    else
      if !e(opts, :preload, nil) and Config.env() != :test,
        do:
          warn(
            scope_id,
            "cannot lookup Settings since an ID was provided as scope instead of an object with Settings preloaded"
          )

      nil
    end
  end

  defp maybe_fetch(scope, opts) when is_map(scope) do
    case id(scope) do
      nil ->
        # if is_map(scope) or Keyword.keyword?(scope) do
        #   scope
        # else

        error(
          scope,
          "no ID for scope"
        )

        nil

      # end

      scope_id ->
        case scope do
          %{settings: %Ecto.Association.NotLoaded{}} ->
            maybe_fetch(scope_id, opts ++ [recursing: true]) ||
              maybe_warn_not_fetched(scope, opts[:recursing])

          %{settings: settings} ->
            settings

          _ ->
            maybe_fetch(scope_id, opts ++ [recursing: true]) ||
              maybe_warn_not_fetched(scope, opts[:recursing])
        end
    end
  end

  defp maybe_fetch(scope, _opts) do
    warn(scope, "invalid scope")
    nil
  end

  if Config.env() != :test do
    defp maybe_warn_not_fetched(scope, nil) do
      warn(
        Types.object_type(scope),
        "cannot lookup Settings since they aren't preloaded in scoped object"
      )

      nil
    end
  end

  defp maybe_warn_not_fetched(_, _), do: nil

  defp do_fetch(id) do
    query_filter(Bonfire.Data.Identity.Settings, %{id: id})
    # |> proload([:pointer]) # workaround for error "attempting to cast or change association `pointer` from `Bonfire.Data.Identity.Settings` that was not loaded. Please preload your associations before manipulating them through changesets"
    |> repo().maybe_one()
  end

  @doc """
  Sets a value for a specific key or list of nested keys.

  This function updates the configuration with the provided value. You can specify a single key or a list of nested keys.

  ## Examples

      # when no scope or current_user are passed in opts:
      > put(:some_key, "new_value")
      {:error, "You need to be authenticated to change settings."}

      # when the scope is :instance but an admin isn't passed as current_user in opts:
      > put(:some_key, "new_value", scope: :instance)
      ** (Bonfire.Fail) You do not have permission to change instance settings. Please contact an admin.

      > {:ok, %Bonfire.Data.Identity.Settings{}} = put(:some_key, "new_value", skip_boundary_check: true, scope: :instance)

      > {:ok, %Bonfire.Data.Identity.Settings{}} = put([:top_key, :sub_key], "new_value", skip_boundary_check: true, scope: "instance")

  ## Options
    * `:otp_app` - Specifies the OTP application for which to set settings. If not specified, it decides where to put it using the same logic as `get/3`.
    * `:scope` - Defines the scope for settings (e.g., `:user`, `:account`, or `:instance`).
  """
  def put(keys, value, opts \\ [])

  def put(keys, value, opts) when is_list(keys) do
    # keys = Config.keys_tree(keys) # Note: doing this in set/2 instead
    # |> debug("Putting settings for")
    Enums.map_put_in(keys, value)
    |> debug("map_put_in")
    |> input_to_atoms(
      discard_unknown_keys: true,
      values: true,
      values_to_integers: true,
      also_discard_unknown_nested_keys: false
    )
    |> debug("send to hooks")
    # |> maybe_to_keyword_list(true)
    # |> debug("maybe_to_keyword_list")
    |> set_with_hooks(to_options(opts))
  end

  def put(key, value, opts), do: put([key], value, opts)

  @doc "..."
  def put_raw(keys, value, opts \\ [])

  def put_raw(keys, value, opts) when is_list(keys) do
    # keys = Config.keys_tree(keys) # Note: doing this in set/2 instead
    keys
    |> debug("Putting settings for")
    |> Enums.map_put_in(value)
    |> debug("send to hooks")
    # |> maybe_to_keyword_list(true)
    # |> debug("maybe_to_keyword_list")
    |> set_with_hooks(to_options(opts))
  end

  def put_raw(key, value, opts), do: put_raw([key], value, opts)

  def delete(key_tree, opts \\ [])

  def delete(key_tree, opts) when is_list(key_tree) do
    # TODO: optimise since this also runs in do_set
    [otp_app | key_tree] = Config.keys_tree(key_tree)

    opts =
      to_options(opts)
      # FIXME: won't work if provided keys don't match what is stored (atom / non-atom)
      |> Keyword.put(:delete_key, key_tree)
      |> Keyword.put(:otp_app, otp_app)

    # TODO: handle with and without otp_app as first key

    Enums.map_put_in([otp_app] ++ key_tree, nil)
    |> debug("to_delete")
    |> set_with_hooks(opts)
  end

  def delete(key, opts), do: put([key], opts)

  @doc """
  Sets multiple settings at once.

  This function accepts a map or keyword list of settings to be updated. It determines the appropriate scope and updates the settings accordingly.

  ## Examples

      > {:ok, %Bonfire.Data.Identity.Settings{}} = set(%{some_key: "value", another_key: "another_value"}, skip_boundary_check: true, scope: :instance)

      > {:ok, %Bonfire.Data.Identity.Settings{}} = set([some_key: "value", another_key: "another_value"], skip_boundary_check: true, scope: "instance")

  ## Options
    * `:otp_app` - Specifies the OTP application for which to set settings.
    * `:scope` - Defines the scope for settings (e.g., `:user`, `:account`, or `:instance`).
  """

  def set(attrs, opts \\ [])

  def set(attrs, opts) when is_map(attrs) do
    attrs
    |> input_to_atoms(
      discard_unknown_keys: true,
      values: true,
      values_to_integers: true,
      also_discard_unknown_nested_keys: false
    )
    |> debug("send to hooks")
    |> set_with_hooks(to_options(opts))
  end

  def set(settings, opts) when is_list(settings) do
    # TODO: optimise (do not convert to map and then back)
    Enum.into(settings, %{})
    |> debug("send to hooks")
    |> set_with_hooks(to_options(opts))
  end

  @doc """
  Resets settings for the instance scope.

  This function deletes the settings associated with the whole instance and returns the result.

  ## Examples

      > reset_instance()
      {:ok, %Bonfire.Data.Identity.Settings{id: "some_id"}}
  """
  def reset_instance() do
    with {:ok, set} <-
           repo().delete(struct(Bonfire.Data.Identity.Settings, id: id(instance_scope())), []) do
      # also put_env to cache it in Elixir's Config?
      # Config.put([])

      {:ok, set}
    end
  end

  @doc """
  Resets all settings.

  This function deletes all settings from the database, including instance-specific settings and user-specific settings for all users. Please be careful!

  ## Examples

      > reset_all()
      {:ok, %{}}
  """
  def reset_all() do
    reset_instance()
    repo().delete_many(Bonfire.Data.Identity.Settings)
  end

  # TODO: find a better, more pluggable way to add hooks to settings
  defp set_with_hooks(
         %{Bonfire.Me.Users => %{undiscoverable: true}} = attrs,
         opts
       ) do
    current_user = current_user_required!(opts)

    # TODO: move this code somewhere else

    maybe_apply(Bonfire.Search, :maybe_unindex, [current_user])
    |> debug("deleetd?")

    Bonfire.Boundaries.Controlleds.remove_acls(
      current_user,
      :everyone_may_see_read
    )

    Bonfire.Boundaries.Controlleds.add_acls(
      current_user,
      :everyone_may_read
    )

    do_set(attrs, opts)
  end

  defp set_with_hooks(
         %{Bonfire.Me.Users => %{undiscoverable: _}} = attrs,
         opts
       ) do
    current_user = current_user_required!(opts)

    Bonfire.Boundaries.Controlleds.remove_acls(
      current_user,
      :everyone_may_read
    )

    Bonfire.Boundaries.Controlleds.add_acls(
      current_user,
      :everyone_may_see_read
    )

    do_set(attrs, opts)
  end

  defp set_with_hooks(attrs, opts) do
    do_set(attrs, opts)
  end

  defp do_set(attrs, opts) when is_map(attrs) do
    attrs
    |> maybe_to_keyword_list(true)
    |> do_set(opts)
  end

  defp do_set(settings, opts) when is_list(settings) do
    if scope = check_scope(e(settings, :scope, nil), opts) do
      settings
      |> Keyword.drop([:scope])
      |> Enum.map(&Config.keys_tree/1)
      |> debug("keyword list to set for #{inspect(scope)}")
      |> set_for(scope, ..., opts)

      # TODO: if setting a key to `nil` we could remove it instead
    else
      {:error, l("You need to be authenticated to change settings.")}
    end
  end

  def check_scope(scope \\ nil, opts) do
    current_user = current_user(opts)
    current_account = current_account(opts)
    # FIXME: do we need to associate each setting key to a verb? (eg. :describe)
    is_admin_or_skip =
      e(opts, :skip_boundary_check, nil) ||
        maybe_apply(Bonfire.Boundaries, :can?, [current_account, :configure, :instance],
          fallback_return: false
        )

    case maybe_to_atom(scope || e(opts, :scope, nil))
         |> debug("scope specified to set") do
      :instance when is_admin_or_skip == true ->
        {:instance, instance_scope()}

      :instance ->
        fail(
          {:unauthorized,
           l("to change instance settings.") <> " " <> l("Please contact an admin.")}
        )

      :account ->
        {:current_account, current_account}

      :user ->
        {:current_user, current_user}

      %schema{} = scope when schema == Bonfire.Data.Identity.Account ->
        {:current_account, scope}

      %schema{} = scope when schema == Bonfire.Data.Identity.User ->
        {:current_user, scope}

      object when is_map(object) ->
        object

      _ ->
        if current_user do
          {:current_user, current_user}
        else
          if current_account do
            {:current_account, current_account}
          end
        end
    end
    |> debug("computed scope to set")
  end

  defp fail(reason) do
    if Extend.module_exists?(Bonfire.Fail),
      do: raise(Bonfire.Fail, reason),
      else: raise(inspect(reason))
  end

  defp set_for({:current_user, scoped} = _scope_tuple, settings, opts) do
    fetch_or_empty(scoped, opts)
    # |> debug
    |> upsert(settings, uid(scoped), opts)
    ~> {:ok,
     %{
       __context__: %{current_user: map_put_settings(scoped, ...)}
     }}
  end

  defp set_for({:current_account, scoped} = _scope_tuple, settings, opts) do
    fetch_or_empty(scoped, opts)
    # |> debug
    |> upsert(settings, uid(scoped), opts)
    ~> {:ok,
     %{
       __context__: %{current_account: map_put_settings(scoped, ...)}
       # TODO: assign this within current_user ?
     }}
  end

  defp set_for({:instance, scoped} = _scope_tuple, settings, opts) do
    with {:ok, %{json: new_data} = set} <-
           fetch_or_empty(scoped, opts)
           # |> debug
           |> upsert(settings, uid(scoped), opts) do
      # also save it in Elixir's Config for quick lookups
      if delete_key = opts[:delete_key] do
        Config.delete(delete_key, opts[:otp_app])
      else
        Config.put_tree(new_data, already_prepared: true)
        |> debug("put in config")
      end

      {:ok, set}
    end
  end

  defp set_for({_, scope}, settings, opts) do
    set_for(scope, settings, opts)
  end

  defp set_for(scoped, settings, opts) do
    fetch_or_empty(scoped, opts)
    |> upsert(settings, uid!(scoped), opts)
  end

  defp map_put_settings(object, {:ok, settings}),
    do: map_put_settings(object, settings)

  defp map_put_settings(object, settings),
    do: Map.put(object, :settings, settings)

  defp fetch_or_empty(scoped, opts) do
    maybe_fetch(scoped, opts ++ [preload: true]) ||
      struct(Bonfire.Data.Identity.Settings)
  end

  defp upsert(
         %schema{json: existing_data} = settings,
         new_data,
         _,
         opts
       )
       when (schema == Bonfire.Data.Identity.Settings and is_list(existing_data)) or
              is_map(existing_data) do
    # new_data
    # |> debug("new settings")

    existing_data
    |> prepare_from_json()
    |> debug("existing_data")
    |> do_upsert(
      settings,
      ...,
      new_data,
      opts
    )
  end

  defp upsert(
         %schema{id: id} = settings,
         new_data,
         _,
         _opts
       )
       when schema == Bonfire.Data.Identity.Settings and is_binary(id) do
    do_update(settings, new_data)
  end

  defp upsert(%{settings: _} = parent, new_data, _, opts) do
    parent
    |> repo().maybe_preload(:settings)
    |> e(:settings, struct(Bonfire.Data.Identity.Settings))
    |> upsert(new_data, uid(parent), opts)
  end

  defp upsert(%schema{} = settings, new_data, scope_id, _opts)
       when schema == Bonfire.Data.Identity.Settings do
    %{id: uid!(scope_id), json: prepare_for_json(new_data)}
    # |> debug()
    |> Bonfire.Data.Identity.Settings.changeset(settings, ...)
    # |> debug()
    |> repo().insert()
  rescue
    e in Ecto.ConstraintError ->
      warn(e, "ConstraintError - will next attempt to update instead")

      do_fetch(uid!(scope_id))
      |> info("fetched")
      |> do_update(new_data)
  end

  defp do_upsert(
         settings,
         existing_data,
         new_data,
         opts
       ) do
    if keys = opts[:delete_key] do
      {_, new_data} =
        existing_data
        |> pop_in([opts[:otp_app]] ++ keys)
        |> debug("settings with deletion to set")

      do_update(settings, new_data)
    else
      existing_data
      # |> debug("existing_data")
      |> deep_merge(new_data, replace_lists: true)
      |> debug("merged settings to set")
      |> do_update(settings, ...)
    end
  end

  defp do_update(
         %schema{} = settings,
         new_data
       )
       when schema == Bonfire.Data.Identity.Settings do
    Bonfire.Data.Identity.Settings.changeset(settings, %{
      new_data: new_data,
      json: prepare_for_json(new_data)
    })
    |> repo().update()
  end

  defp prepare_for_json(settings) do
    with {:ok, for_json} <-
           settings
           |> Map.new() do
      #  |> JsonSerde.Serializer.serialize() do
      for_json
    end
  end

  defp prepare_from_json(settings) do
    settings
    # |> JsonSerde.Deserializer.deserialize(..., ...)
    # ~> debug("deserialized")
    # ~> input_to_atoms(
    #   discard_unknown_keys: true,
    #   values: false,
    #   also_discard_unknown_nested_keys: false
    # )
    # |> debug("to_atoms")
  end

  defp instance_scope,
    do:
      maybe_apply(Bonfire.Boundaries.Circles, :get_id, :local, fallback_return: nil) ||
        "3SERSFR0MY0VR10CA11NSTANCE"
end
