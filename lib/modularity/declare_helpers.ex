defmodule Bonfire.Common.Modularity.DeclareHelpers do
  @moduledoc """
  Helpers for declaring the existence of an extension (i.e., so it gets included in extension settings and nav).
  """

  @doc """
  Declares an extension by setting up the module with the given name and options.

  ## Examples

      iex> defmodule MyExtension do
      ...>   import Bonfire.Common.Modularity.DeclareHelpers
      ...>   declare_extension("My Extension", readme: "MY_README.md")
      ...> end

  """

  defmacro declare_extension(name, opts \\ []) do
    quote do
      use Arrows
      @behaviour Bonfire.Common.ExtensionModule
      @readme_contents File.read(unquote(opts)[:readme] || "README.md")

      def declared_extension do
        generate_link(
          unquote(name),
          __MODULE__,
          unquote(opts) ++ [readme_contents: from_ok(@readme_contents)]
        )

        # Enum.into(unquote(opts), %{
        #   name: unquote(name),
        #   module: __MODULE__,
        #   app: Extend.application_for_module(__MODULE__),
        #   href: unquote(opts)[:href] || path(__MODULE__)
        # })
      end
    end
  end

  @doc """
  Generates a map representing a link with metadata for the extension with the given name, module, and options.

  ## Examples

      iex> Bonfire.Common.Modularity.DeclareHelpers.generate_link(:bonfire_common, Bonfire.Common, href: "/my_extension")
      %{
        name: :bonfire_common,
        module: Bonfire.Common,
        app: :bonfire_common,
        href: "/my_extension",
        type: :link, 
        sub_widgets: []
      }

  """
  def generate_link(name, module, opts) do
    Enum.into(opts, %{
      name: name,
      module: module,
      app: app(module),
      href: opts[:href] || Bonfire.Common.URIs.path(module, [], fallback: false),
      type: :link,
      sub_widgets:
        Enum.map(opts[:sub_links] || [], fn {name, opts} -> generate_link(name, module, opts) end)
    })
  end

  @doc "Gets the OTP app name for a module"
  # NOTE: not using cache because compile-time
  def app(module), do: Application.get_application(module)
  # Bonfire.Common.Extend.application_for_module(module)
end
