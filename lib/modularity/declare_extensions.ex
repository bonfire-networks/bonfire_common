defmodule Bonfire.Common.Modularity.DeclareExtensions do
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

  defmacro declare_nav_link(name, opts \\ []) do
    quote do
      def declared_nav do
        Enum.into(unquote(opts), %{
          name: unquote(name),
          href: path(__MODULE__),
          type: :link
        })
      end
    end
  end

  def component_type(module), do: List.first(module.__info__(:attributes)[:component_type] || module.__info__(:attributes)[:behaviour])

  def component_props(module), do: Surface.API.get_props(module) |> Enum.map(&Map.drop(&1, [:opts_ast, :func, :line]))
end
