defmodule Bonfire.Common.Modularity.DeclareHelpers do
  # alias Bonfire.Common.Extend

  defmacro declare_extension(name, opts \\ []) do
    quote do
      @behaviour Bonfire.Common.ExtensionModule
      @readme_contents File.read(unquote(opts)[:readme] || "README.md")

      def declared_extension do
        generate_link(
          unquote(name),
          __MODULE__,
          unquote(opts) ++ [readme_contents: Bonfire.Common.Utils.ok_unwrap(@readme_contents)]
        )

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
