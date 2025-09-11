defmodule Bonfire.Common.Utils do
  @moduledoc """
  Various very commonly used utility functions for the Bonfire application.

  This module should contain only a few generic and/or heavily-used functions, and any other functions should be in more specific modules (or in other extensions altogether) for e.g.: 

  - `Bonfire.Common.Enums` for functions around maps, structs, keyword lists, and the like
  - `Bonfire.Common.Types` for object types
  - `Bonfire.Common.URIs` and `Linkify` for URI handling
  - `Bonfire.Common.DatesTimes` for date/time helpers
  - `Bonfire.Common.E` to extract nested data from an object
  - `Bonfire.Common.Errors` and `Bonfire.Fail` for error handling
  - `Bonfire.Common.Extend` for functions around modularity
  - `Bonfire.Common.Opts` for handling function options
  - `Bonfire.Common.Config` for handling app-wide config
  - `Bonfire.Common.Settings` for handling account/user/instance level settings
  - `Bonfire.Common.HTTP` for HTTP requests
  - `Bonfire.Common.Cache` for caching
  - `Bonfire.Common.Text` for plain or rich text
  - `Bonfire.Common.Localise` for app localisation
  - `Bonfire.Common.Media` and `Bonfire.Files` for avatars/images/videos/etc
  - `Bonfire.Common.Repo` and `Needle` for database access
  - `Bonfire.Common.PubSub` for pub/sub

  We may also want to consider reusing functions from existing utils libraries when possible and contributing missing ones there, for example:

  - https://hexdocs.pm/moar/readme.html
  - https://hexdocs.pm/bunch/api-reference.html
  - https://hexdocs.pm/swiss/api-reference.html
  - https://hexdocs.pm/wuunder_utils/api-reference.html
  - https://github.com/cozy-elixir
  """

  use Arrows
  alias Bonfire.Common
  # import Common.Config, only: [repo: 0]
  use Untangle
  require Logger
  use Common.E
  # alias Common.Text
  alias Common.Opts
  # alias Common.Cache
  alias Common.Enums
  alias Common.Errors
  alias Common.Extend
  alias Common.Types
  import Bonfire.Common.Modularity.DeclareHelpers
  use Gettext, backend: Bonfire.Common.Localise.Gettext
  import Bonfire.Common.Localise.Gettext.Helpers

  defmacro __common_utils__(opts \\ []) do
    quote do
      import Untangle
      use Arrows

      alias Bonfire.Common

      use Common.E

      # require Utils
      # can import specific functions with `only` or `except`
      import Common.Utils, unquote(opts)

      import Common.Enums
      import Common.Extend
      import Common.Types
      import Common.URIs
      import Bonfire.Common.Modularity.DeclareHelpers

      alias Common.Utils
      alias Common.Cache
      alias Common.E
      alias Common.Errors
      alias Common.Extend
      alias Common.Types
      alias Common.Text
      alias Common.Enums
      alias Common.DatesTimes
      alias Common.Media
      alias Common.URIs
      alias Common.HTTP
      alias Bonfire.Boundaries
    end
  end

  defmacro __localise__(opts \\ []) do
    quote do
      # localisation
      use Gettext, backend: Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  defmacro __using__(opts) do
    quote do
      Bonfire.Common.Utils.__localise__(unquote(opts))
      Bonfire.Common.Utils.__common_utils__(unquote(opts))

      use Bonfire.Common.Config
      use Bonfire.Common.Settings
    end
  end

  declare_extension("Common",
    icon: "carbon:software-resource",
    emoji: "🔶",
    description: l("Common utilities and functionality used by most other extensions.")
  )

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

  This function traverses various possible structures to find and return the current user (or current user ID if that's all that's available). 

  ## Examples

      iex> Bonfire.Common.Utils.current_user(%{current_user: %{id: "user1"}})
      %{id: "user1"}

      iex> Bonfire.Common.Utils.current_user(%{assigns: %{current_user: %{id: "user2"}}})
      %{id: "user2"}

      iex> Bonfire.Common.Utils.current_user(%{socket: %{assigns: %{current_user: %{id: "user3"}}}})
      %{id: "user3"}

      iex> Bonfire.Common.Utils.current_user([current_user: %{id: "user4"}])
      %{id: "user4"}

      iex> Bonfire.Common.Utils.current_user(%{current_user_id: "5EVSER1S0STENS1B1YHVMAN01D"})
      "5EVSER1S0STENS1B1YHVMAN01D"
  """
  def current_user(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      {:ok, ret} = _socket ->
        current_user(ret)

      %{current_user: %{id: _} = user} ->
        user

      # %{current_user: nil} ->
      #   nil

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

      %{table_id: "5EVSER1S0STENS1B1YHVMAN01D"} ->
        current_user_or_socket_or_opts

      %{assigns: %{} = assigns} = _socket ->
        current_user(assigns, true)

      %{__context__: %{current_user: _} = context} = _assigns ->
        current_user(context, true)

      %{socket: %{} = socket} = _socket ->
        current_user(socket, true)

      %{context: %{current_user: _} = context} = _api_opts ->
        current_user(context, true)

      %{context: %Bonfire.Data.Identity.User{} = user} ->
        user

      %{context: %{table_id: "5EVSER1S0STENS1B1YHVMAN01D"} = user} ->
        user

      _ when is_list(current_user_or_socket_or_opts) ->
        if Keyword.keyword?(current_user_or_socket_or_opts) do
          current_user(Map.new(current_user_or_socket_or_opts), true)
        else
          Enum.find_value(current_user_or_socket_or_opts, &current_user(&1, true))
        end

      {:current_user, user} when not is_nil(user) ->
        current_user(user, true)

      nil ->
        nil

      %{context: :instance} ->
        nil

      _ ->
        if !empty?(current_user_or_socket_or_opts) and recursing != :skip do
          debug(
            current_user_or_socket_or_opts,
            "No current_user found, will fallback to looking for a current_user_id",
            trace_skip: if(recursing, do: 2, else: 1)
          )

          current_user_id(current_user_or_socket_or_opts, :skip)
        end
    end ||
      (
        if !recursing,
          do:
            debug(Types.typeof(current_user_or_socket_or_opts), "No current_user found in",
              trace_skip: 1
            )

        nil
      )
  end

  @doc """
  Returns the current user ID from socket, assigns, or options.

  This function traverses various possible structures to find and return the current user ID.

  ## Examples

      iex> Bonfire.Common.Utils.current_user_id(%{current_user_id: "5EVSER1S0STENS1B1YHVMAN01D"})
      "5EVSER1S0STENS1B1YHVMAN01D"

      iex> Bonfire.Common.Utils.current_user_id(%{assigns: %{current_user_id: "5EVSER1S0STENS1B1YHVMAN01D"}})
      "5EVSER1S0STENS1B1YHVMAN01D"

      iex> Bonfire.Common.Utils.current_user_id(%{assigns: %{__context__: %{current_user_id: "5EVSER1S0STENS1B1YHVMAN01D"}}})
      "5EVSER1S0STENS1B1YHVMAN01D"

      iex> Bonfire.Common.Utils.current_user_id("5EVSER1S0STENS1B1YHVMAN01D")
      "5EVSER1S0STENS1B1YHVMAN01D"
      
      iex> Bonfire.Common.Utils.current_user_id("invalid id")
      nil
  """
  def current_user_id(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      %{current_user_id: nil} ->
        nil

      %{current_user_id: id} ->
        Types.uid(id)

      # %{user_id: id} ->
      #   Types.uid(id)

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
        Types.uid(user_id)

      %{current_user: user_id} when is_binary(user_id) ->
        Types.uid(user_id)

      user_id when is_binary(user_id) ->
        Types.uid(user_id)

      _ ->
        if recursing != :skip,
          do:
            current_user(current_user_or_socket_or_opts, :skip)
            |> Types.uid()
    end ||
      (
        if !recursing,
          do:
            debug(
              Types.typeof(current_user_or_socket_or_opts),
              "No current_user_id or current_user found in"
            )

        nil
      )
  end

  @doc """
  Ensures that the current user is present and raises an exception if not logged in.

  ## Examples

      iex> Bonfire.Common.Utils.current_user_required!(%{current_user: %{id: "user1"}})
      %{id: "user1"}

      > Bonfire.Common.Utils.current_user_required!(%{})
      ** (Bonfire.Fail.Auth) You need to log in first. 
  """
  def current_user_required!(context),
    do: current_user(context) || fail_auth(:needs_login)

  @doc """
  (Re)authenticates the current user using the provided password.

  Raises an exception if the credentials are invalid.

  ## Examples

      > Bonfire.Common.Utils.current_user_auth!(%{current_user: %{id: "user1"}}, "password123")
      ** (Bonfire.Fail.Auth) We couldn't find an account with the details you provided. 

  """
  def current_user_auth!(context, password) do
    current_user = current_user(context)
    current_account_id = current_account_id(current_user)

    if not is_nil(current_user) and not is_nil(current_account_id) and
         Bonfire.Me.Accounts.login_valid?(current_account_id, password),
       do: current_user,
       else: fail_auth(:invalid_credentials)
  end

  @doc """
  (Re)authenticates the current account using the provided password.

  Raises an exception if the credentials are invalid.

  ## Examples

      > Bonfire.Common.Utils.current_account_auth!(%{current_account: %{id: "2CC0VNTSARE1S01AT10NGR0VPS"}}, "wrong-password")
      ** (Bonfire.Fail.Auth) We couldn't find an account with the details you provided.
  """
  def current_account_auth!(context, password) do
    current_account = current_account(context)
    current_account_id = Enums.id(current_account)

    if not is_nil(current_account_id) and
         Bonfire.Me.Accounts.login_valid?(current_account_id, password),
       do: current_account,
       else: fail_auth(:invalid_credentials)
  end

  defp fail_auth(reason) do
    if Extend.module_exists?(Bonfire.Fail.Auth),
      do: raise(Bonfire.Fail.Auth, reason),
      else: raise(to_string(reason))
  end

  @doc """
  Returns the current account from socket, assigns, or options.

  This function traverses various possible structures to find and return the current account.

  ## Examples

      iex> Bonfire.Common.Utils.current_account(%{current_account: %{id: "account1"}})
      %{id: "account1"}

      iex> Bonfire.Common.Utils.current_account(%{assigns: %{current_account: %{id: "account2"}}})
      %{id: "account2"}

      iex> Bonfire.Common.Utils.current_account(%{socket: %{assigns: %{current_account: %{id: "account3"}}}})
      %{id: "account3"}

      iex> Bonfire.Common.Utils.current_account([current_account: %{id: "account4"}])
      %{id: "account4"}

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
        Types.uid(account_id)

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
                debug(Enums.id(user), "no account in current_user",
                  trace_skip: if(recursing, do: 2, else: 1)
                )

                nil
            end
        end ||
          (
            debug(
              Types.typeof(current_account_or_socket_or_opts),
              "No current_account found, will fallback to looking for a current account_id",
              trace_skip: if(recursing, do: 2, else: 1)
            )

            current_account_id(other, :skip)
          )
    end ||
      (
        if !recursing,
          do:
            debug(Types.typeof(current_account_or_socket_or_opts), "No current_account found in",
              trace_skip: 1
            )

        nil
      )
  end

  @doc """
  Returns the current account ID from socket, assigns, or options.

  This function traverses various possible structures to find and return the current account ID.

  ## Examples

      iex> Bonfire.Common.Utils.current_account_id(%{current_account_id: "2CC0VNTSARE1S01AT10NGR0VPS"})
      "2CC0VNTSARE1S01AT10NGR0VPS"

      iex> Bonfire.Common.Utils.current_account_id(%{assigns: %{current_account_id: "2CC0VNTSARE1S01AT10NGR0VPS"}})
      "2CC0VNTSARE1S01AT10NGR0VPS"

      iex> Bonfire.Common.Utils.current_account_id(%{socket: %{assigns: %{current_account_id: "2CC0VNTSARE1S01AT10NGR0VPS"}}})
      "2CC0VNTSARE1S01AT10NGR0VPS"

      iex> Bonfire.Common.Utils.current_account_id("2CC0VNTSARE1S01AT10NGR0VPS")
      "2CC0VNTSARE1S01AT10NGR0VPS"
  """
  def current_account_id(current_account_or_socket_or_opts, recursing \\ false) do
    case current_account_or_socket_or_opts do
      %{current_account_id: id} = _options ->
        Types.uid(id)

      # %{account_id: id} = _options ->
      #   Types.uid(id)

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

      %{current_account_id: nil} ->
        nil

      {:current_account_id, nil} ->
        nil

      {:current_account_id, account_id} ->
        current_account_id(account_id, true)

      %{current_user: %{account: %{id: account_id}}} ->
        account_id

      %{current_user: %{accounted: %{account_id: account_id}}} ->
        account_id

      %{current_user: %{accounted: %{account: %{id: account_id}}}} ->
        account_id

      account_id when is_binary(account_id) ->
        Types.uid(account_id)

      _ ->
        if recursing != :skip,
          do:
            current_account(current_account_or_socket_or_opts)
            |> Types.uid()
    end ||
      (
        if !recursing,
          do:
            debug(
              Types.typeof(current_account_or_socket_or_opts),
              "No current_account_id or current_account found in",
              trace_skip: 1
            )

        nil
      )
  end

  @doc """
  Returns a list of current account IDs and/or user IDs.

  This function returns a keyword list with the current account IDs and/or user IDs.

  ## Examples

      iex> Bonfire.Common.Utils.current_account_and_or_user_ids(%{current_account_id: "2CC0VNTSARE1S01AT10NGR0VPS", current_user_id: "5EVSER1S0STENS1B1YHVMAN01D"})
      [account: "2CC0VNTSARE1S01AT10NGR0VPS", user: "5EVSER1S0STENS1B1YHVMAN01D"]
      
      iex> Bonfire.Common.Utils.current_account_and_or_user_ids(%{current_account: %{id: "2CC0VNTSARE1S01AT10NGR0VPS"}, current_user: %{id: "5EVSER1S0STENS1B1YHVMAN01D"}})
      [account: "2CC0VNTSARE1S01AT10NGR0VPS", user: "5EVSER1S0STENS1B1YHVMAN01D"]

      iex> Bonfire.Common.Utils.current_account_and_or_user_ids(%{current_account_id: "2CC0VNTSARE1S01AT10NGR0VPS"})
      [account: "2CC0VNTSARE1S01AT10NGR0VPS"]

      iex> Bonfire.Common.Utils.current_account_and_or_user_ids(%{current_user_id: "5EVSER1S0STENS1B1YHVMAN01D"})
      [user: "5EVSER1S0STENS1B1YHVMAN01D"]

      iex> Bonfire.Common.Utils.current_account_and_or_user_ids(%{})
      []
  """
  def current_account_and_or_user_ids(assigns) do
    case {current_account_id(assigns), current_user_id(assigns)} do
      {nil, nil} -> []
      {current_account, nil} -> [{:account, current_account}]
      {nil, current_user} -> [{:user, current_user}]
      {current_account, current_user} -> [{:account, current_account}, {:user, current_user}]
    end
  end

  @doc """
    Helper for calling hypothetical functions another modules. 
    
  Attempts to apply a function from a specified module with the given arguments and returns the result. 

  Returns an error if the function is not defined,  unless a fallback function was provided to be invoked, or a fallback value to be returned.

  ## Parameters

    - `module`: The module to check for the function.
    - `funs`: A list of function names (atoms) to try.
    - `args`: Arguments to pass to the function.
    - `opts`: Options for error handling and fallback. Options include:
      - `:fallback_fun` - A function to call if the primary function is not found.
      - `:fallback_return` - A default return value if the function cannot be applied.

  ## Examples

      iex> maybe_apply(Enum, :map, [[1, 2, 3], &(&1 * 2)])
      [2, 4, 6]

      iex> maybe_apply(Enum, [:nonexistent_fun], [])
      {:error, "None of the functions [:nonexistent_fun] are defined at Elixir.Enum with arity 0"}

      iex> maybe_apply(Enum, [:nonexistent_fun], [], fallback_fun: fn error, _args, _opts -> raise "Failed" end)
      ** (RuntimeError) Failed

      iex> maybe_apply(SomeModule, [:some_fun], [1, 2, 3], fallback_return: "Failed")
      # Output: [warning] maybe_apply: No such module (Elixir.SomeModule) could be loaded. - with args: ([1, 2, 3])
      "Failed"
  """
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
    opts = Opts.to_options(opts)

    if opts[:force_module] == true or Extend.module_enabled?(module, opts) do
      # debug(module, "module_enabled")

      available_funs =
        Enum.map(funs, fn
          f when is_atom(f) ->
            if Kernel.function_exported?(module, f, arity), do: f

          f ->
            f = Types.maybe_to_atom!(f)
            if Kernel.function_exported?(module, f, arity), do: f
        end)
        |> Enum.reject(&is_nil/1)

      fun = List.first(available_funs)

      if fun do
        # debug({fun, arity}, "function_exists")

        if opts[:no_argument_rescue] do
          apply(module, fun, args)
        else
          try do
            apply(module, fun, args)
            # |> debug("ran")
          rescue
            e in FunctionClauseError ->
              exception = Errors.debug_banner(:error, e, __STACKTRACE__)

              msg =
                "A pattern matching error occurred when trying to maybe_apply #{module}.#{fun}/#{arity}"

              if opts[:ignore_errors] || opts[:fallback_fun] do
                debug(exception, msg, stacktrace: __STACKTRACE__)
              else
                err(exception, msg, stacktrace: __STACKTRACE__)
              end

              maybe_apply_fallback(
                msg,
                args,
                opts
              )

            e in ArgumentError ->
              exception = Errors.debug_banner(:error, e, __STACKTRACE__)

              msg =
                "An argument error occurred when trying to maybe_apply #{module}.#{fun}/#{arity}"

              if opts[:ignore_errors] || opts[:fallback_fun] do
                debug(exception, msg, stacktrace: __STACKTRACE__)
              else
                err(exception, msg, stacktrace: __STACKTRACE__)
              end

              maybe_apply_fallback(
                msg,
                args,
                opts
              )
          end
        end
      else
        maybe_apply_error(
          "None of the functions #{inspect(funs)} are defined at #{module} with arity #{arity}",
          args,
          opts
        )
      end
    else
      maybe_apply_error("No such module (#{module}) could be loaded.", args, opts)
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
        maybe_apply_error(
          "invalid function call for #{inspect(fun)} on #{inspect(module)}",
          args,
          opts
        )

  def maybe_apply_error(error, args, opts) do
    warn(error)
    # debug(args, "maybe_apply args")
    # debug(opts, "maybe_apply opts")

    maybe_apply_fallback(error, args, opts)
  end

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

  defp do_maybe_apply_fallback(fallback_fun, _error, args, _opts)
       when is_list(args) and is_function(fallback_fun, length(args)) do
    apply(fallback_fun, args)
  end

  defp do_maybe_apply_fallback(fallback_fun, _error, args, _opts)
       when not is_list(args) and is_function(fallback_fun, 1) do
    apply(fallback_fun, List.wrap(args))
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

  defp do_maybe_apply_fallback(fallback_fun, _error, _args, _opts)
       when is_function(fallback_fun, 0) do
    fallback_fun.()
  end

  defp do_maybe_apply_fallback(fallback_return, _error, _args, _opts) do
    fallback_return
  end

  def apply_error(error, args, opts) do
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


  ## Parameters

  - `function`: The type of task to start (e.g. `:async`, `:start_link`, or `:start`).
  - `fun`: The function to execute async.
  - `opts`: Options for task execution, including:
    - `:module` - The module to use for task execution (defaults to `Task`).

  ## Examples

      # Spawn an unsupervised Task for side effects
      > {apply_task(:start, fn -> IO.puts("Fire-and-forget task") end)
      # Output: "Fire-and-forget task"

      # Spawn a supervised Task
      > apply_task(:start_link, fn -> IO.puts("Supervised task") end)
      # Output: "Supervised task"

      # Start an async Task (which you must await to get the result)
      > apply_task(:async, fn -> IO.puts("Async task") end)
      # Output: "Async task"

      # Using LiveView's start_async
      > apply_task(:start_async, fn -> {:ok, %{result: "done"}} end, socket: socket, id: "task-123")
      # Returns updated socket with async operation

      # Using LiveView's assign_async
      > apply_task(:assign_async, fn -> {:ok, %{key_to_assign: "value"}} end, socket: socket, keys: [:key_to_assign])
      # Returns updated socket with async assignment
  """
  def apply_task(function \\ :async, fun, opts \\ [])

  # Handle LiveView's start_async
  def apply_task(:start_async, fun, opts) when is_list(opts) and is_function(fun) do
    socket =
      opts[:socket] ||
        (warn(opts) && raise ArgumentError, "`:socket` is required for LiveView async operations")

    id =
      opts[:id] ||
        (warn(opts, "`:id` is required in opts for LiveView start_async operations") &&
           raise ArgumentError, "`:id` is required in opts for LiveView start_async operations")

    pid = socket.transport_pid
    current_endpoint = Process.get(:phoenix_endpoint_module)

    if socket && function_exported?(Phoenix.LiveView, :start_async, 4) do
      Phoenix.LiveView.start_async(
        socket,
        id,
        fn ->
          # Preserve multi-tenancy/context in spawned process
          Bonfire.Common.TestInstanceRepo.set_child_instance(pid, current_endpoint)

          # Execute the function
          fun.()
        end,
        opts
      )
    else
      # Fallback to regular Task if LiveView not available
      do_apply_task(opts[:module] || Task, :start_link, fun, [], opts)
    end
  end

  # Handle LiveView's assign_async
  def apply_task(:assign_async, fun, opts) when is_list(opts) and is_function(fun) do
    socket =
      opts[:socket] ||
        (warn(opts) &&
           raise ArgumentError, "`:socket` is required in opts for LiveView async operations")

    keys =
      opts[:keys] ||
        (warn(opts) &&
           raise ArgumentError, "`:keys` is required in opts for LiveView assign_async operations")

    pid = socket.transport_pid
    current_endpoint = Process.get(:phoenix_endpoint_module)

    if socket && function_exported?(Phoenix.LiveView, :assign_async, 4) do
      Phoenix.LiveView.assign_async(
        socket,
        keys,
        fn ->
          # Preserve multi-tenancy/context in spawned process
          Bonfire.Common.TestInstanceRepo.set_child_instance(pid, current_endpoint)

          # Execute the function
          fun.()
        end,
        opts
      )
    else
      # Fallback to regular Task if LiveView not available
      task = do_apply_task(opts[:module] || Task, :async, fun, [], opts)
      result = Task.await(task)
      Phoenix.Socket.assign(socket, from_ok(result))
    end
  end

  # Use existing apply_task implementation for standard Task operations
  def apply_task(function, fun, opts) when function in [:async, :start_link, :start] do
    do_apply_task(opts[:module] || Task, function, fun, [], opts)
  end

  defp do_apply_task(module, function, fun, args, _opts \\ []) do
    pid = self()
    current_endpoint = Process.get(:phoenix_endpoint_module)

    apply(
      module,
      function,
      args ++
        [
          fn ->
            # Preserve multi-tenancy/context in spawned process
            Bonfire.Common.TestInstanceRepo.set_child_instance(pid, current_endpoint)
            fun.()
          end
        ]
    )
  end

  @doc """
  Runs a function asynchronously using `Task.Supervisor`. This is similar to `apply_task(:start_async, fun, opts)` but specifically uses `Task.Supervisor` for supervision.

  ## Parameters

    - `module`: The supervisor module to use for task execution
    - `fun`: The function to execute async
    - `opts`: Options for task execution, including:
      - `:function` - The `Task.Supervisor` function to use for task execution (defaults to `:async`).

  ## Examples

      > apply_task_supervised(MySupervisor, fn -> IO.puts("Supervised async task") end)
      ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name, possibly because its application isn't started
      # because `MySupervisor` is not defined and/or started ^
  """
  def apply_task_supervised(supervisor, fun, opts \\ []) do
    do_apply_task(Task.Supervisor, opts[:function] || :async, fun, [supervisor], opts)
  end

  @doc """
  Checks if the given value is `nil`, an empty enumerable, or an empty string.

  ## Parameters

    - `v`: The value to check.

  ## Examples

      iex> empty?(nil)
      true

      iex> empty?("")
      true

      iex> empty?([])
      true

      iex> empty?([1, 2, 3])
      false

      iex> empty?("hello")
      false
  """
  def empty?(v) when is_nil(v) or v == %{} or v == [] or v == "", do: true
  def empty?(v) when is_binary(v), do: String.trim(v) == ""

  def empty?(v) do
    if Enumerable.impl_for(v),
      do: Enum.empty?(v),
      else: false
  end

  @doc """
  Checks if the given value is `nil`, `false`, `0`, or an empty value (using `empty?/1`).

  ## Parameters

    - `v`: The value to check.

  ## Examples

      iex> nothing?(nil)
      true

      iex> nothing?(false)
      true

      iex> nothing?(0)
      true

      iex> nothing?("")
      true

      iex> nothing?([1, 2, 3])
      false

      iex> nothing?("hello")
      false
  """
  def nothing?(v) when is_nil(v) or v == false or v == 0 or v == "0", do: true
  def nothing?(v), do: empty?(v)

  @doc """
  Applies the given function if the first parameter is not `nil`.

  ## Parameters

    - `val`: The value to check.
    - `change_fn`: A function to apply if `val` is not `nil`.

  ## Examples

      iex> maybe(nil, fn x -> x * 2 end)
      nil

      iex> maybe(3, fn x -> x * 2 end)
      6
  """
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  @doc """
  Rounds a number and uses `Bonfire.Common.Localise.Cldr.Number.to_string/2` function to format into a human readable string.

  ## Examples

      iex> round_nearest(1234)
      "1K"

      iex> round_nearest(1600000)
      "2M"
  """
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

  @doc """
  Rounds a number to the nearest specified target. 

  ## Parameters

    - `num`: The number to round.
    - `target`: The target to round to (optional).

  ## Examples

      iex> round_nearest(1234, 10)
      1230

      iex> round_nearest(1234, 100)
      1200

      iex> round_nearest(1234, 1000)
      1000
  """
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
