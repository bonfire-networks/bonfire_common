defmodule Bonfire.Common.Modularity.DeclareHelpers do
  # alias Bonfire.Common.Extend

  defmacro declare_extension(name, opts \\ []) do
    quote do
      @behaviour Bonfire.Common.ExtensionModule

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

  def generate_link(name, module, opts) do
    Enum.into(opts, %{
      name: name,
      module: module,
      app: app(module),
      href: opts[:href] || Bonfire.Common.URIs.path(module),
      type: :link
    })
  end

  def app(module), do: Application.get_application(module)
end
