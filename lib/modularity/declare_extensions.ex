defmodule Bonfire.Common.Modularity.DeclareExtensions do
  alias Bonfire.Common.Extend

  defmacro declare_extension(name, opts \\ []) do
    quote do
      def declared_extension do
        generate_link(unquote(name), __MODULE__, unquote(opts))
        # Enum.into(unquote(opts), %{
        #   name: unquote(name),
        #   module: __MODULE__,
        #   app: Application.get_application(__MODULE__),
        #   href: unquote(opts)[:href] || path(__MODULE__)
        # })
      end
    end
  end

  defmacro declare_widget(name, opts \\ []) do
    quote do
      @props_specs component_props(__MODULE__)

      def declared_widget do
        Enum.into(unquote(opts), %{
          name: unquote(name),
          module: __MODULE__,
          type: component_type(__MODULE__),
          data: @props_specs
        })
      end
    end
  end

  defmacro declare_nav_component(name, opts \\ []) do
    quote do
      @props_specs component_props(__MODULE__)

      def declared_nav do
        Enum.into(unquote(opts), %{
          name: unquote(name),
          module: __MODULE__,
          type: component_type(__MODULE__),
          data: @props_specs
        })
      end
    end
  end

  defmacro declare_nav_link(name, opts \\ [])

  defmacro declare_nav_link(name, opts) do
    quote do
      def declared_nav do
        case unquote(name) do
          list when is_list(list) ->
            Enum.map(list, fn {name, opts} ->
              generate_link(name, __MODULE__, opts)
            end)

          name ->
            generate_link(name, __MODULE__, unquote(opts))
            # Enum.into(unquote(opts), %{
            #   name: unquote(name),
            #   module: __MODULE__,
            #   href: unquote(opts)[:href] || path(__MODULE__),
            #   type: :link
            # })
        end
      end
    end
  end

  def generate_link(name, module, opts) do
    Enum.into(opts, %{
      name: name,
      module: module,
      href: opts[:href] || Bonfire.Common.URIs.path(module),
      type: :link
    })
  end

  def component_type(module),
    do:
      List.first(
        module.__info__(:attributes)[:component_type] ||
          module.__info__(:attributes)[:behaviour]
      )

  def component_props(module),
    do:
      Surface.API.get_props(module)
      |> Enum.map(&Map.drop(&1, [:opts_ast, :func, :line]))
end
