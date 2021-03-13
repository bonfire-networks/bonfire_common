defmodule Bonfire.Web.LiveComponent do
  @moduledoc """
  Special LiveView used for a helper function which allows loading LiveComponents in regular Phoenix views: `live_render_component(@conn, MyLiveComponent)`
  """

  use Bonfire.Web, :live_view

  alias Bonfire.Web.LivePlugs

  def mount(params, session, socket) do
    LivePlugs.live_plug params, session, socket, [
      LivePlugs.LoadSessionAuth,
      LivePlugs.StaticChanged,
      LivePlugs.Csrf,
      &mounted/3,
    ]
  end

  defp mounted(params, %{"load_live_component" => load_live_component} = session, socket) do

     {:ok, socket |> assign(:load_live_component, load_live_component)}
  end

  defp mounted(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
      ~L"""
      <%= if Map.has_key?(assigns, :load_live_component) and module_exists?(assigns.load_live_component), do: live_component(
      @socket,
      assigns.load_live_component,
      assigns
    ) %>
    """
  end

end
