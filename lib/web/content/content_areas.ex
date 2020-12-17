defmodule Bonfire.Common.Web.ContentAreas do
  import Phoenix.HTML, only: [safe_to_string: 1]

  alias Bonfire.Common.Web.ContentAreas.Render

  @doc """
  Returns HTML-safe string if type is `:html` or just a string if `:text`.

  These are basic fallbacks in case Publisher:Thesis extension is not present.
  In future, this can also be extended for content localisation.

  # see https://github.com/infinitered/thesis-phoenix/blob/master/lib/thesis/view.ex#L32

  ## Examples
      <%= content(@conn, "Title", :text, do: "Default Title") %>

      <%= content(@conn, "Description", :html) do %>
        <p>Default description</p>
        <p>Another paragraph</p>
      <% end %>

      <%= content(@conn, "Description", :html, classes: "more classes") do %>
        <p>Default description</p>
      <% end %>

      <%= content(@conn, "Section identifier", :raw_html) do %>
        <iframe width="560" height="315" src="https://www.youtube.com/embed/5SVLs_NN_uY" frameborder="0" allowfullscreen></iframe>
      <% end %>

      <%= content(@conn, "Image identifier", :image, alt: "My alt tag", do: "http://placekitten.com/200/300") %>

  """
  @spec content(Plug.Conn.t, String.t, String.t, list) :: String.t | {:safe, String.t}
  def content(conn, name, type, opts \\ [do: ""]) do
    render_content(conn, name, type, opts)
  end

  @spec content(Plug.Conn.t, String.t, String.t, list, list) :: String.t | {:safe, String.t}
  def content(conn, name, type, opts, [do: block]) do
    render_content(conn, name, type, Keyword.put(opts, :do, block))
  end

  defp render_content(_conn, name, type, opts) do
    make_content(name, type, stringify(opts[:do]), Keyword.delete(opts, :do))
    |>
    Render.render_editable(opts)
  end

  defp make_content(name, type, content, meta) do
    %{
      name: name,
      content_type: Atom.to_string(type),
      content: content,
      meta: meta_serialize(meta)
    }
  end

  @doc """
  Returns a serialized string, given a map, for storage in the meta field.
  ## Doctests:
      iex> m = %{test: "Thing", test2: "123"}
      iex> Thesis.PageContent.meta_serialize(m)
      ~S({"test2":"123","test":"Thing"})
  """
  def meta_serialize(keyword_list) when is_list(keyword_list) do
    keyword_list
    |> Enum.into(%{})
    |> meta_serialize
  end

  def meta_serialize(map) when is_map(map) do
    map
    |> Jason.encode!
  end

  @doc """
  Returns a keyword list of meta attributes from the serialized data.
  ## Doctests:
      iex> m = %Thesis.PageContent{meta: ~S({"test":"Thing", "test2":"123"})}
      iex> Thesis.PageContent.meta_attributes(m)
      %{test: "Thing", test2: "123"}
  """
  def meta_attributes(%{meta: nil}), do: []
  def meta_attributes(%{} = page_content) do
    page_content.meta
    |> Jason.decode!(keys: :atoms)
  end

  defp stringify(str) when is_binary(str), do: str
  defp stringify(str), do: safe_to_string(str)

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

end
