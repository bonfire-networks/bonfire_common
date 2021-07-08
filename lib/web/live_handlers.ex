defmodule Bonfire.Common.LiveHandlers do
  @moduledoc """
  usage examples:

  phx-submit="Bonfire.Social.Posts:post" will be routed to Bonfire.Social.Posts.LiveHandler.handle_event("post", ...

  Bonfire.Common.Utils.pubsub_broadcast(feed_id, {{Bonfire.Social.Feeds, :new_activity}, activity})  will be routed to Bonfire.Social.Feeds.LiveHandler.handle_info({:new_activity, activity}, ...

  href="?Bonfire.Social.Feeds[after]=<%= e(@page_info, :after, nil) %>" will be routed to Bonfire.Social.Feeds.LiveHandler.handle_params(%{"after" => cursor_after} ...

  """
  use Bonfire.Web, :live_handler
  require Logger

  def handle_params(params, uri, socket, source_module \\ nil) do
    undead(socket, fn ->
      Logger.info("LiveHandler: handle_params via #{source_module || "delegation"}")
      ## IO.inspect(params: params)
      do_handle_params(params, uri, socket
                                    |> assign_global(
                                      current_url: URI.parse(uri)
                                                   |> maybe_get(:path)
                                    ))
    end)
  end

  def handle_event(action, attrs, socket, source_module \\ nil) do
    undead(socket, fn ->
      Logger.info("LiveHandler: handle_event via #{source_module || "delegation"}")
      do_handle_event(action, attrs, socket)
    end)
  end

  def handle_info(blob, socket, source_module \\ nil) do
    undead(socket, fn ->
      Logger.info("LiveHandler: handle_info via #{source_module || "delegation"}")
      do_handle_info(blob, socket)
    end)
  end


  # global handler to set a view's assigns from a component
  defp do_handle_info({:assign, {assign, value}}, socket) do
    undead(socket, fn ->
      IO.inspect(handle_info_set_assign: assign)
      {:noreply,
        socket
        |> assign_global(assign, value)
        # |> IO.inspect(limit: :infinity)
      }
    end)
  end

  defp do_handle_info({{mod, name}, data}, socket) do
    mod_delegate(mod, :handle_info, [{name, data}], socket)
  end

  defp do_handle_info({info, data}, socket) when is_binary(info) do
    case String.split(info, ":", parts: 2) do
      [mod, name] -> mod_delegate(mod, :handle_info, [{name, data}], socket)
      _ -> empty(socket)
    end
  end

  defp do_handle_info(_, socket), do: empty(socket)

  defp do_handle_event(event, attrs, socket) when is_binary(event) do
    # IO.inspect(handle_event: event)
    case String.split(event, ":", parts: 2) do
      [mod, action] -> mod_delegate(mod, :handle_event, [action, attrs], socket)
      _ -> empty(socket)
    end
  end

  defp do_handle_event(_, _, socket), do: empty(socket)

  defp do_handle_params(params, uri, socket) when is_map(params) and params !=%{} do
    # IO.inspect(handle_params: params)
    case Map.keys(params) |> List.first do
      mod when is_binary(mod) and mod not in ["id"] -> mod_delegate(mod, :handle_params, [Map.get(params, mod), uri], socket)
      _ -> empty(socket)
    end
  end

  defp do_handle_params(_, _, socket), do: empty(socket)


  defp mod_delegate(mod, fun, params, socket) do
    Logger.info("LiveHandler: attempt delegating to #{inspect fun} in #{inspect mod}...")

    case maybe_str_to_module("#{mod}.LiveHandler") || maybe_str_to_module(mod) do
      module when is_atom(module) ->
        # IO.inspect(module)
        if module_enabled?(module), do: apply(module, fun, params ++ [socket]),
        else: empty(socket)
      _ -> empty(socket)
    end
  end

  defp empty(socket), do: {:noreply, socket}
end
