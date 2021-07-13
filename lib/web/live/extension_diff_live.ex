defmodule Bonfire.Common.Web.ExtensionDiffLive do
  use Bonfire.Web, {:live_view, [layout: {Bonfire.UI.Social.Web.LayoutView, "without_sidebar.html"}]}
  import Bonfire.Common.Extensions.Diff
  require Logger
  alias Bonfire.Web.LivePlugs

  def mount(params, session, socket) do
    LivePlugs.live_plug params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      LivePlugs.StaticChanged,
      LivePlugs.Csrf, LivePlugs.Locale,
      &mounted/3,
    ]
  end

  defp mounted(params, session, socket) do
    # necessary to avoid running it twice (and interupting an already-running diffing)
    case connected?(socket) do
      true -> mounted_connected(params, session, socket)
      false ->  {:ok,
        socket
        |> assign(
        page_title: "Loading...",
        diffs: []
        )}
    end
  end

  defp mounted_connected(params, session, socket) do
    # diff = generate_diff(package, repo_path)
    diffs = with {:ok, patches} <- generate_diff(:bonfire_me, "./forks/bonfire_me") do
      patches
    else
      {:error, error} ->
        Logger.error(inspect(error))
        []
      error ->
        Logger.error(inspect(error))
        []
    end
    # TODO: handle errors
    {:ok,
        socket
        |> assign(
        page_title: "Extension",
        diffs: diffs
        )}
  end

end
