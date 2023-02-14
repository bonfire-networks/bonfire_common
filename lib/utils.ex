defmodule Bonfire.Common.Utils do
  use Arrows
  alias Bonfire.Common
  import Common.Extend
  # require Bonfire.Common.Localise.Gettext
  # import Bonfire.Common.Localise.Gettext.Helpers
  import Common.Config, only: [repo: 0]
  use Untangle
  require Logger
  alias Common.Text
  alias Common.Config
  alias Common.Enums
  alias Common.Errors
  alias Common.Types

  # 6 hours
  @default_cache_ttl 1_000 * 60 * 60 * 6
  # 5 min
  @error_cache_ttl 1_000 * 60 * 5

  defmacro __using__(opts) do
    quote do
      alias Bonfire.Common
      alias Common.Utils

      alias Common.Cache
      alias Common.Config
      alias Common.Errors
      alias Common.Extend
      alias Common.Types
      alias Common.Text
      alias Common.Enums
      alias Common.DatesTimes
      alias Common.Media
      alias Common.URIs
      alias Bonfire.Me.Settings

      require Utils
      # can import specific functions with `only` or `except`
      import Utils, unquote(opts)

      import Enums
      import Extend
      import Types
      import URIs

      import Untangle
      use Arrows

      # localisation
      require Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  # WIP: move functions out of here into other modules (eg. Text, Enums, URIs, DatesTimes, etc) and update function calls in codebase (incl. extensions) without importing them all in the use macro above

  @doc "Returns a value, or a fallback if nil/false"
  def e(val, fallback) do
    Enums.filter_empty(val, fallback)
  end

  @doc "Returns a value from a map, or a fallback if not present"
  def e({:ok, object}, key, fallback), do: e(object, key, fallback)

  # def e(object, :current_user = key, fallback) do #temporary
  #       debug(key: key)
  #       debug(e_object: object)

  #       case object do
  #     %{__context__: context} ->
  #       debug(key: key)
  #       debug(e_context: context)
  #       # try searching in Surface's context (when object is assigns), if present
  #       enum_get(object, key, nil) || enum_get(context, key, nil) || fallback

  #     map when is_map(map) ->
  #       # attempt using key as atom or string, fallback if doesn't exist or is nil
  #       enum_get(map, key, nil) || fallback

  #     list when is_list(list) and length(list)==1 ->
  #       # if object is a list with 1 element, try with that
  #       e(List.first(list), key, nil) || fallback

  #     _ -> fallback
  #   end
  # end

  # @decorate time()
  def e(object, key, fallback) do
    case object do
      %{__context__: context} ->
        # try searching in Surface's context (when object is assigns), if present
        case Enums.enum_get(object, key, nil) do
          result when is_nil(result) or result == fallback ->
            Enums.enum_get(context, key, fallback)

          result ->
            result
        end

      map when is_map(map) ->
        # attempt using key as atom or string, fallback if doesn't exist or is nil
        Enums.enum_get(map, key, fallback)

      list when is_list(list) and length(list) == 1 ->
        if not Keyword.keyword?(list) do
          # if object is a list with 1 element, look inside
          e(List.first(list), key, fallback)
        else
          list |> Map.new() |> e(key, fallback)
        end

      list when is_list(list) ->
        if not Keyword.keyword?(list) do
          list |> Enum.reject(&is_nil/1) |> Enum.map(&e(&1, key, fallback))
        else
          list |> Map.new() |> e(key, fallback)
        end

      _ ->
        fallback
    end
  end

  @doc "Returns a value from a nested map, or a fallback if not present"
  def e(object, key1, key2, fallback) do
    e(object, key1, %{})
    |> e(key2, fallback)
  end

  def e(object, key1, key2, key3, fallback) do
    e(object, key1, key2, %{})
    |> e(key3, fallback)
  end

  def e(object, key1, key2, key3, key4, fallback) do
    e(object, key1, key2, key3, %{})
    |> e(key4, fallback)
  end

  def e(object, key1, key2, key3, key4, key5, fallback) do
    e(object, key1, key2, key3, key4, %{})
    |> e(key5, fallback)
  end

  def e(object, key1, key2, key3, key4, key5, key6, fallback) do
    e(object, key1, key2, key3, key4, key5, %{})
    |> e(key6, fallback)
  end

  def to_options(user_or_socket_or_opts) do
    case user_or_socket_or_opts do
      %{assigns: assigns} = _socket ->
        Keyword.new(assigns)

      _ when is_struct(user_or_socket_or_opts) ->
        [context: user_or_socket_or_opts]

      _
      when is_list(user_or_socket_or_opts) or is_map(user_or_socket_or_opts) ->
        Keyword.new(user_or_socket_or_opts)

      _ ->
        debug(Types.typeof(user_or_socket_or_opts), "No opts found in")
        []
    end
  end

  def maybe_from_opts(opts, key, fallback \\ nil)
      when is_list(opts) or is_map(opts),
      do: opts[key] || fallback

  def maybe_from_opts(_opts, _key, fallback), do: fallback

  def current_user(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      %{current_user: %{id: _} = user} = _options ->
        user

      %{id: _, profile: _} ->
        current_user_or_socket_or_opts

      %{id: _, character: _} ->
        current_user_or_socket_or_opts

      # %{id: _} when is_struct(current_user_or_socket_or_opts) ->
      #   current_user_or_socket_or_opts

      %{assigns: %{} = assigns} = _socket ->
        current_user(assigns, true)

      %{__context__: %{current_user: _} = context} = _assigns ->
        current_user(context, true)

      %{__context__: %{current_user_id: _} = context} = _assigns ->
        current_user(context, true)

      %{socket: socket} = _socket ->
        current_user(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_user(context, true)

      _ when is_list(current_user_or_socket_or_opts) ->
        if Keyword.keyword?(current_user_or_socket_or_opts) do
          current_user(Map.new(current_user_or_socket_or_opts), true)
        else
          Enum.find_value(current_user_or_socket_or_opts, &current_user/1)
        end

      %{current_user_id: user_id} when is_binary(user_id) ->
        current_user(user_id, true)

      %{current_user: user_id} when is_binary(user_id) ->
        current_user(user_id, true)

      %{user_id: user_id} when is_binary(user_id) ->
        Types.ulid(user_id)

      user_id when is_binary(user_id) ->
        Types.ulid(user_id)

      _ ->
        nil
    end ||
      (
        if recursing != true,
          do: debug(Types.typeof(current_user_or_socket_or_opts), "No current_user found in")

        nil
      )
  end

  def current_user_id(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      %{current_user_id: id} = _options ->
        Types.ulid(id)

      %{user_id: id} = _options ->
        Types.ulid(id)

      %{assigns: %{} = assigns} = _socket ->
        current_user_id(assigns, true)

      %{__context__: %{current_user_id: _} = context} = _assigns ->
        current_user_id(context, true)

      %{socket: socket} = _socket ->
        current_user_id(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_user_id(context, true)

      _ when is_list(current_user_or_socket_or_opts) ->
        current_user_id(Map.new(current_user_or_socket_or_opts), true)

      %{current_user_id: user_id} when is_binary(user_id) ->
        current_user_id(user_id, true)

      user_id when is_binary(user_id) ->
        Types.ulid(user_id)

      _ ->
        current_user(current_user_or_socket_or_opts)
        |> Types.ulid()
    end ||
      (
        if recursing != true,
          do:
            debug(
              Types.typeof(current_user_or_socket_or_opts),
              "No current_user_id or current_user found in"
            )

        nil
      )
  end

  def current_user_required!(context),
    do: current_user(context) || raise(Bonfire.Fail.Auth, :needs_login)

  def current_account(list) when is_list(list) do
    current_account(Map.new(list))
  end

  def current_account(%{current_account: current_account} = _assigns)
      when not is_nil(current_account) do
    current_account
  end

  def current_account(%Bonfire.Data.Identity.Account{id: _} = current_account) do
    current_account
  end

  def current_account(%{accounted: %{account: %{id: _} = account}} = _user) do
    account
  end

  def current_account(%{__context__: %{} = context} = _assigns) do
    current_account(context)
  end

  def current_account(%{assigns: %{} = assigns} = _socket) do
    current_account(assigns)
  end

  def current_account(%{socket: %{} = socket} = _socket) do
    current_account(socket)
  end

  def current_account(%{context: %{} = context} = _api_opts) do
    current_account(context)
  end

  def current_account(other) do
    case current_user(other, true) do
      nil ->
        debug(Types.typeof(other), "No current_account found in")
        nil

      user ->
        case user do
          # |> repo().maybe_preload(accounted: :account) do
          %{accounted: %{account: %{id: _} = account}} -> account
          # %{accounted: %{account_id: account_id}} -> account_id
          _ -> nil
        end
    end
  end

  def current_account_and_or_user_ids(%{assigns: assigns}),
    do: current_account_and_or_user_ids(assigns)

  def current_account_and_or_user_ids(%{
        current_account: %{id: account_id},
        current_user: %{id: user_id}
      }) do
    [{:account, account_id}, {:user, user_id}]
  end

  def current_account_and_or_user_ids(%{
        current_user: %{id: user_id, accounted: %{account_id: account_id}}
      }) do
    [{:account, account_id}, {:user, user_id}]
  end

  def current_account_and_or_user_ids(%{current_user: %{id: user_id}}) do
    [{:user, user_id}]
  end

  def current_account_and_or_user_ids(%{current_account: %{id: account_id}}) do
    [{:account, account_id}]
  end

  def current_account_and_or_user_ids(%{__context__: context}),
    do: current_account_and_or_user_ids(context)

  def current_account_and_or_user_ids(_), do: nil

  def socket_connected?(%{socket_connected?: bool}) do
    bool
  end

  def socket_connected?(%{__context__: %{socket_connected?: bool}}) do
    bool
  end

  def socket_connected?(%{assigns: %{__context__: %{socket_connected?: bool}}}) do
    bool
  end

  def socket_connected?(%struct{} = socket) when struct == Phoenix.LiveView.Socket do
    maybe_apply(Phoenix.LiveView, :connected?, socket, fn _, _ -> nil end)
  end

  def socket_connected?(assigns) do
    warn(Types.typeof(assigns), "Unable to find Socket or :socket_connected? info in")
    nil
  end

  @doc "Helpers for calling hypothetical functions in other modules"
  def maybe_apply(
        module,
        fun,
        args \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_apply(
        module,
        funs,
        args,
        fallback_fun
      )
      when is_atom(module) and not is_nil(module) and is_list(funs) and is_list(args) do
    arity = length(args)

    fallback_fun = if not is_function(fallback_fun), do: &apply_error/2, else: fallback_fun

    fallback_return = if not is_function(fallback_fun), do: fallback_fun

    if module_enabled?(module) do
      # debug(module, "module_enabled")

      available_funs =
        Enum.reject(funs, fn f ->
          not Kernel.function_exported?(module, f, arity)
        end)

      fun = List.first(available_funs)

      if fun do
        # debug({fun, arity}, "function_exists")

        try do
          apply(module, fun, args)
        rescue
          e in FunctionClauseError ->
            {exception, stacktrace} = Errors.debug_banner_with_trace(:error, e, __STACKTRACE__)

            error(stacktrace, exception)

            e =
              fallback_fun.(
                "A pattern matching error occured when trying to maybe_apply #{module}.#{fun}/#{arity}",
                args
              )

            fallback_return || e

          e in ArgumentError ->
            {exception, stacktrace} = Errors.debug_banner_with_trace(:error, e, __STACKTRACE__)

            error(stacktrace, exception)

            e =
              fallback_fun.(
                "An argument error occured when trying to maybe_apply #{module}.#{fun}/#{arity}",
                args
              )

            fallback_return || e
        end
      else
        e =
          fallback_fun.(
            "None of the functions #{inspect(funs)} are defined at #{module} with arity #{arity}",
            args
          )

        fallback_return || e
      end
    else
      e =
        fallback_fun.(
          "No such module (#{module}) could be loaded.",
          args
        )

      fallback_return || e
    end
  end

  def maybe_apply(
        module,
        fun,
        args,
        fallback_fun
      )
      when not is_list(args),
      do:
        maybe_apply(
          module,
          fun,
          [args],
          fallback_fun
        )

  def maybe_apply(
        module,
        fun,
        args,
        fallback_fun
      )
      when not is_list(fun),
      do:
        maybe_apply(
          module,
          [fun],
          args,
          fallback_fun
        )

  def maybe_apply(
        module,
        fun,
        args,
        fallback_fun
      ),
      do:
        apply_error(
          "invalid function call for #{inspect(fun)} on #{inspect(module)}",
          args
        )

  def apply_error(error, args) do
    Logger.warn("maybe_apply: #{error} - with args: (#{inspect(args)})")

    {:error, error}
  end

  def empty?(v) when is_nil(v) or v == %{} or v == [] or v == "", do: true
  def empty?(_), do: false

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  def replace_nil(nil, value), do: value
  def replace_nil(other, _), do: other

  def ok_unwrap(val, fallback \\ nil)
  def ok_unwrap({:ok, val}, _fallback), do: val
  def ok_unwrap({:error, _val}, fallback), do: fallback
  def ok_unwrap(:error, fallback), do: fallback
  def ok_unwrap(val, fallback), do: val || fallback
end
