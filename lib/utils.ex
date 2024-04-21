defmodule Bonfire.Common.Utils do
  @moduledoc """
  Various very commonly used utility functions for the Bonfire application.
  """
  use Arrows
  alias Bonfire.Common
  import Common.Extend
  # require Bonfire.Common.Localise.Gettext
  # import Bonfire.Common.Localise.Gettext.Helpers
  # import Common.Config, only: [repo: 0]
  use Untangle
  require Logger
  # alias Common.Text
  # alias Common.Config
  alias Common.Cache
  alias Common.Enums
  alias Common.Errors
  alias Common.Types
  import Bonfire.Common.Modularity.DeclareHelpers
  require Bonfire.Common.Localise.Gettext
  import Bonfire.Common.Localise.Gettext.Helpers

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
      alias Common.HTTP
      alias Bonfire.Common.Settings
      alias Bonfire.Boundaries

      require Utils
      # can import specific functions with `only` or `except`
      import Utils, unquote(opts)

      import Enums
      import Extend
      import Types
      import URIs
      import Bonfire.Common.Modularity.DeclareHelpers

      import Untangle
      use Arrows

      # localisation
      require Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  declare_extension("Common",
    icon: "carbon:software-resource",
    emoji: "🔶",
    description: l("Common utilities and functionality used by most other extensions.")
  )

  # WIP: move functions out of here into other modules (eg. Text, Enums, URIs, DatesTimes, etc) and update function calls in codebase (incl. extensions) without importing them all in the use macro above

  defdelegate e(object, fallback \\ nil), to: Bonfire.Common.E
  defdelegate e(object, key1, fallback), to: Bonfire.Common.E
  defdelegate e(object, key1, key2, fallback), to: Bonfire.Common.E
  defdelegate e(object, key1, key2, key3, fallback), to: Bonfire.Common.E
  defdelegate e(object, key1, key2, key3, key4, fallback), to: Bonfire.Common.E
  defdelegate e(object, key1, key2, key3, key4, key5, fallback), to: Bonfire.Common.E
  defdelegate e(object, key1, key2, key3, key4, key5, key6, fallback), to: Bonfire.Common.E

  @doc """
  Converts a map, user, socket, tuple, etc, to a keyword list for standardised use as function options.
  """
  defdelegate to_options(user_or_socket_or_opts), to: Bonfire.Common.Opts

  @doc """
  Returns the value of a key from options keyword list or map, or a fallback if not present or empty.
  """
  defdelegate maybe_from_opts(opts, key, fallback \\ nil), to: Bonfire.Common.Opts

  @doc """
  Returns the current user from socket, assigns, or options.
  """
  def current_user(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      {:ok, ret} = _socket ->
        current_user(ret)

      %{current_user: %{id: _} = user} ->
        user

      # %{current_user: id} when is_binary(id) ->
      #   Cache.get!("current_user:#{id}") || %{id: id}

      # id when is_binary(id) ->
      #   Cache.get!("current_user:#{id}") || %{id: id}

      %{id: _, profile: _} ->
        current_user_or_socket_or_opts

      %{id: _, character: _} ->
        current_user_or_socket_or_opts

      %Bonfire.Data.Identity.User{} ->
        current_user_or_socket_or_opts

      %{assigns: %{} = assigns} = _socket ->
        current_user(assigns, true)

      %{__context__: %{current_user: _} = context} = _assigns ->
        current_user(context, true)

      %{socket: socket} = _socket ->
        current_user(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_user(context, true)

      _ when is_list(current_user_or_socket_or_opts) ->
        if Keyword.keyword?(current_user_or_socket_or_opts) do
          current_user(Map.new(current_user_or_socket_or_opts), true)
        else
          Enum.find_value(current_user_or_socket_or_opts, &current_user(&1, true))
        end

      {:current_user, user} ->
        current_user(user, true)

      nil ->
        nil

      %{context: :instance} ->
        nil

      _ ->
        if !empty?(current_user_or_socket_or_opts) do
          warn(
            current_user_or_socket_or_opts,
            "No current_user found, will fallback to looking for a current_user_id"
          )

          current_user_id(current_user_or_socket_or_opts, :skip)
        end
    end ||
      (
        if recursing != true,
          do: debug(Types.typeof(current_user_or_socket_or_opts), "No current_user found in")

        nil
      )
  end

  @doc """
  Returns the current user ID from socket, assigns, or options.
  """
  def current_user_id(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      %{current_user_id: id} = _options ->
        Types.ulid(id)

      # %{user_id: id} = _options ->
      #   Types.ulid(id)

      %{assigns: %{} = assigns} = _socket ->
        current_user_id(assigns, true)

      %{__context__: %{current_user_id: _} = context} = _assigns ->
        current_user_id(context, true)

      %{socket: socket} = _socket ->
        current_user_id(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_user_id(context, true)

      %{current_user_id: user_id} when is_binary(user_id) ->
        current_user_id(user_id, true)

      {:current_user_id, user_id} ->
        current_user_id(user_id, true)

      %{current_user: %{id: user_id}} when is_binary(user_id) ->
        Types.ulid(user_id)

      %{current_user: user_id} when is_binary(user_id) ->
        Types.ulid(user_id)

      user_id when is_binary(user_id) ->
        Types.ulid(user_id)

      _ ->
        if recursing != :skip,
          do:
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

  def current_user_auth!(context, password) do
    current_user = current_user(context)
    current_account_id = current_account_id(current_user)

    if not is_nil(current_user) and not is_nil(current_account_id) and
         Bonfire.Me.Accounts.login_valid?(current_account_id, password),
       do: current_user,
       else: raise(Bonfire.Fail.Auth, :invalid_credentials)
  end

  def current_account_auth!(context, password) do
    current_account = current_account(context)
    current_account_id = Enums.id(current_account)

    if not is_nil(current_account_id) and
         Bonfire.Me.Accounts.login_valid?(current_account_id, password),
       do: current_account,
       else: raise(Bonfire.Fail.Auth, :invalid_credentials)
  end

  @doc """
  Returns the current account from socket, assigns, or options.
  """
  def current_account(current_account_or_socket_or_opts, recursing \\ false) do
    case current_account_or_socket_or_opts do
      %{current_account: %{id: _} = account} = _options ->
        account

      %Bonfire.Data.Identity.Account{id: _} = current_account ->
        current_account

      %{account: %{id: _} = account} = _user ->
        account

      %{accounted: %{account: %{id: _} = account}} = _user ->
        account

      %{assigns: %{} = assigns} = _socket ->
        current_account(assigns, true)

      %{__context__: %{} = context} = _assigns ->
        current_account(context, true)

      %{socket: socket} = _socket ->
        current_account(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_account(context, true)

      _ when is_list(current_account_or_socket_or_opts) ->
        if Keyword.keyword?(current_account_or_socket_or_opts) do
          current_account(Map.new(current_account_or_socket_or_opts), true)
        else
          Enum.find_value(current_account_or_socket_or_opts, &current_account(&1, true))
        end

      %{current_account: account_id} when is_binary(account_id) ->
        Types.ulid(account_id)

      {:current_account, account_id} ->
        current_account(account_id, true)

      nil ->
        nil

      other ->
        case current_user(other, true) do
          nil ->
            nil

          user ->
            case user do
              # |> repo().maybe_preload(accounted: :account) do
              %{account: %{id: _} = account} ->
                account

              %{accounted: %{account: %{id: _} = account}} ->
                account

              %{accounted: %{account_id: account_id}} ->
                account_id

              _ ->
                debug(Enums.id(user), "no account in current_user")
                nil
            end
        end ||
          (
            debug(
              # other,
              "No current_account found, will fallback to looking for a current account_id"
            )

            current_account_id(other, :skip)
          )
    end ||
      (
        if recursing != true,
          do:
            debug(Types.typeof(current_account_or_socket_or_opts), "No current_account found in")

        nil
      )
  end

  def current_account_id(current_account_or_socket_or_opts, recursing \\ false) do
    case current_account_or_socket_or_opts do
      %{current_account_id: id} = _options ->
        Types.ulid(id)

      # %{account_id: id} = _options ->
      #   Types.ulid(id)

      %{assigns: %{} = assigns} = _socket ->
        current_account_id(assigns, true)

      %{__context__: %{current_account_id: _} = context} = _assigns ->
        current_account_id(context, true)

      %{socket: socket} = _socket ->
        current_account_id(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_account_id(context, true)

      %{current_account_id: account_id} when is_binary(account_id) ->
        current_account_id(account_id, true)

      {:current_account_id, account_id} ->
        current_account_id(account_id, true)

      %{current_user: %{account: %{id: account_id}}} ->
        account_id

      %{current_user: %{accounted: %{account_id: account_id}}} ->
        account_id

      %{current_user: %{accounted: %{account: %{id: account_id}}}} ->
        account_id

      account_id when is_binary(account_id) ->
        Types.ulid(account_id)

      _ ->
        if recursing != :skip,
          do:
            current_account(current_account_or_socket_or_opts)
            |> Types.ulid()
    end ||
      (
        if recursing != true,
          do:
            debug(
              Types.typeof(current_account_or_socket_or_opts),
              "No current_account_id or current_account found in"
            )

        nil
      )
  end

  def current_account_and_or_user_ids(assigns) do
    case {current_account_id(assigns), current_user_id(assigns)} do
      {nil, nil} -> []
      {current_account, nil} -> [{:account, current_account}]
      {nil, current_user} -> [{:user, current_user}]
      {current_account, current_user} -> [{:account, current_account}, {:user, current_user}]
    end
  end

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
    maybe_apply(Phoenix.LiveView, :connected?, socket, fallback_return: false)
  end

  def socket_connected?(assigns) do
    warn(Types.typeof(assigns), "Unable to find Socket or :socket_connected? info in")
    false
  end

  @doc "Helpers for calling hypothetical functions in other modules. Returns the result of calling a function with the given arguments, or the result of fallback function if the primary function is not defined (by default just logging an error message)."
  def maybe_apply(
        module,
        fun,
        args \\ [],
        opts \\ []
      )

  def maybe_apply(
        module,
        funs,
        args,
        fallback_fun
      )
      when is_function(fallback_fun),
      do:
        maybe_apply(
          module,
          funs,
          args,
          fallback_fun: fallback_fun
        )

  def maybe_apply(
        module,
        funs,
        args,
        opts
      )
      when is_atom(module) and not is_nil(module) and is_list(funs) and is_list(args) do
    arity = length(args)
    opts = to_options(opts)

    if module_enabled?(module, opts) do
      # debug(module, "module_enabled")

      available_funs =
        Enum.reject(funs, fn f ->
          not Kernel.function_exported?(module, f, arity)
        end)

      fun = List.first(available_funs)

      if fun do
        # debug({fun, arity}, "function_exists")

        if opts[:no_argument_rescue] do
          apply(module, fun, args)
        else
          try do
            apply(module, fun, args)
          rescue
            e in FunctionClauseError ->
              {exception, stacktrace} = Errors.debug_banner_with_trace(:error, e, __STACKTRACE__)

              error(stacktrace, exception)

              maybe_apply_fallback(
                "A pattern matching error occurred when trying to maybe_apply #{module}.#{fun}/#{arity}",
                args,
                opts
              )

            e in ArgumentError ->
              {exception, stacktrace} = Errors.debug_banner_with_trace(:error, e, __STACKTRACE__)

              error(stacktrace, exception)

              maybe_apply_fallback(
                "An argument error occurred when trying to maybe_apply #{module}.#{fun}/#{arity}",
                args,
                opts
              )
          end
        end
      else
        maybe_apply_fallback(
          "None of the functions #{inspect(funs)} are defined at #{module} with arity #{arity}",
          args,
          opts
        )
      end
    else
      maybe_apply_fallback("No such module (#{module}) could be loaded.", args, opts)
    end
  end

  def maybe_apply(
        module,
        fun,
        args,
        opts
      )
      when not is_list(args),
      do:
        maybe_apply(
          module,
          fun,
          [args],
          opts
        )

  def maybe_apply(
        module,
        fun,
        args,
        opts
      )
      when not is_list(fun),
      do:
        maybe_apply(
          module,
          [fun],
          args,
          opts
        )

  def maybe_apply(
        module,
        fun,
        args,
        opts
      ),
      do:
        apply_error(
          "invalid function call for #{inspect(fun)} on #{inspect(module)}",
          args,
          opts
        )

  def maybe_apply_fallback(error, args, opts) do
    do_maybe_apply_fallback(
      Keyword.get(
        opts,
        :fallback_return,
        case opts[:fallback_fun] do
          fallback_fun when is_function(fallback_fun) -> fallback_fun
          _ -> &apply_error/3
        end
      ),
      error,
      args,
      opts
    )
  end

  defp do_maybe_apply_fallback(fallback_fun, error, args, opts)
       when is_function(fallback_fun, 3) do
    fallback_fun.(
      error,
      args,
      opts
    )
  end

  defp do_maybe_apply_fallback(fallback_fun, error, args, _opts)
       when is_function(fallback_fun, 2) do
    fallback_fun.(
      error,
      args
    )
  end

  defp do_maybe_apply_fallback(fallback_fun, error, args, _opts)
       when is_function(fallback_fun, 1) do
    fallback_fun.(args)
  end

  defp do_maybe_apply_fallback(fallback_fun, error, args, _opts)
       when is_function(fallback_fun, 0) do
    fallback_fun.()
  end

  defp do_maybe_apply_fallback(fallback_return, error, args, _opts) do
    Logger.warning("maybe_apply: #{error} - with args: (#{inspect(args)})")
    fallback_return
  end

  def apply_error(error, args, opts) do
    Logger.warning(
      "maybe_apply: #{error} - with args: #{inspect(args)} - and opts: #{inspect(opts)}"
    )

    {:error, error}
  end

  @doc """
  Runs a function asynchronously in a Task. Simply a shorthand for calling functions in `Task` and `Task.Supervisor` but with support for multi-tenancy in the spawned process. 

  - `Task.async/1` the caller creates a new process links and monitors it. Once the task action finishes, a message is sent to the caller with the result. `Task.await/2` is used to read the message sent by the task. When using `async`, you *must* `await` a reply as they are always sent. 

  - `Task.start_link/1` is suggested instead if you are not expecting a reply. It starts a statically supervised task as part of a supervision tree, linked to the calling process (meaning it will be stopped when the caller stops). 

  - `Task.start/1` can be used for fire-and-forget tasks, like side-effects, when you have no interest on its results nor if it completes successfully (because if the server is shut down it won't be restarted).

  For more serious tasks, consider using `Oban` or `apply_task_supervised/3` for supervised tasks when possible:

  - `Task.Supervisor.start_child/2` allows you to start a fire-and-forget task when you don't care about its results or if it completes successfully or not.

  - `Task.Supervisor.async/2` + `Task.await/2` allows you to execute tasks concurrently and retrieve its result. If the task fails, the caller will also fail.
  """
  def apply_task(function \\ :async, fun, opts \\ []) do
    pid = self()
    current_endpoint = Process.get(:phoenix_endpoint_module)

    apply(opts[:module] || Task, function, [
      fn ->
        Process.put(:task_parent_pid, pid)
        Bonfire.Common.TestInstanceRepo.maybe_declare_test_instance(current_endpoint)
        fun.()
      end
    ])
  end

  def apply_task_supervised(function \\ :async, fun, opts \\ []) do
    apply_task(function, fun, opts ++ [module: Task.Supervisor])
  end

  @doc "Returns true if the given value is nil, an empty enumerable, or an empty string."
  def empty?(v) when is_nil(v) or v == %{} or v == [] or v == "", do: true
  def empty?(v) when is_binary(v), do: String.trim(v) == ""

  def empty?(v) do
    if Enumerable.impl_for(v),
      do: Enum.empty?(v),
      else: false
  end

  @doc "Returns true if the given value is 0, false, nil, or empty (see `empty?/1`)"
  def nothing?(v) when is_nil(v) or v == false or v == 0 or v == "0", do: true
  def nothing?(v), do: empty?(v)

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  @doc """
  Unwraps an `{:ok, val}` tuple, returning the value, or returns a fallback value (nil by default) if the tuple is `{:error, _}` or `:error`.
  """
  def ok_unwrap(val, fallback \\ nil)
  def ok_unwrap({:ok, val}, _fallback), do: val

  def ok_unwrap({:error, val}, fallback) do
    error(val)
    fallback
  end

  def ok_unwrap(:error, fallback), do: fallback
  def ok_unwrap(val, fallback), do: val || fallback

  def round_nearest(num) when is_number(num) do
    case maybe_apply(Bonfire.Common.Localise.Cldr.Number, :to_string, [num, [format: :short]]) do
      {:ok, formatted} ->
        formatted

      other when is_integer(num) ->
        warn(other)
        do_round_nearest(num, num |> Integer.digits() |> length())

      other ->
        error(other)
        nil
    end
  end

  def round_nearest(num, target) when is_number(num) and is_number(target),
    do: round(num / target) * target

  defp do_round_nearest(num, digit_count)
  defp do_round_nearest(num, 1), do: num
  defp do_round_nearest(num, 2), do: round_nearest(num, 10)
  defp do_round_nearest(num, 3), do: round_nearest(num, 100)
  defp do_round_nearest(num, 4), do: round_nearest(num, 1000)
  defp do_round_nearest(num, 5), do: round_nearest(num, 10000)
  defp do_round_nearest(num, 6), do: round_nearest(num, 100_000)
  defp do_round_nearest(num, _), do: round_nearest(num, 1_000_000)
end
