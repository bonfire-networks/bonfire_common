defmodule Bonfire.Common.Web.Misc do

  # copies the 'go' part of the query string, if any
  def copy_go(%{go: go}), do: "?" <> Query.encode(go: go)
  def copy_go(%{"go" => go}), do: "?" <> Query.encode(go: go)
  def copy_go(_), do: ""

  # TODO: should we preserve query strings?
  def go_query(%{requested_path: requested_path}=_conn), do: "?" <> Query.encode(go: requested_path)
  def go_query(_conn), do: ""

  # TODO: we should validate this a bit harder. Phoenix will prevent
  # us from sending the user to an external URL, but it'll do so by
  # means of a 500 error.
  def valid_go_path?("/" <> _), do: true
  def valid_go_path?(_), do: false

  def go_where?(_conn, %Ecto.Changeset{}, default) do
    default
  end

  def go_where?(_conn, params, default) do
    go = params[:go] || params["go"]
    if valid_go_path?(go), do: go, else: default
  end

end
