defmodule Bonfire.Web do
  @moduledoc false

  alias Bonfire.Common.Utils

  def controller(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:namespace, Bonfire.Common.Config.get!(:default_web_namespace))

    quote do
      use Phoenix.Controller, unquote(opts)
      import Plug.Conn
      alias Bonfire.Web.Plugs.{MustBeGuest, MustLogIn}
      import Phoenix.LiveView.Controller

      unquote(basic_view_helpers())

    end
  end

  def view(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:root, "lib")
      |> maybe_put_layout("app.html")
    quote do
      use Phoenix.View, unquote(opts)
      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      unquote(live_view_helpers())

    end
  end

  defp maybe_put_layout(opts, file) do
    if !Bonfire.Common.Config.get(:default_layout_module), do: opts, else: opts
      |> Keyword.put_new(:layout, {Bonfire.Common.Config.get(:default_layout_module), file})
  end

  def layout_view(opts \\ []) do
    view(opts)
  end

  def live_view(opts \\ []) do
    #IO.inspect(live_view: opts)
    opts =
      opts
      |> maybe_put_layout("live.html")
    quote do
      use Phoenix.LiveView, unquote(opts)

      unquote(live_view_helpers())

    end
  end

  def live_component(opts \\ []) do
    quote do
      use Phoenix.LiveComponent, unquote(opts)

      unquote(live_view_helpers())

    end
  end

  def live_handler(_opts \\ []) do
    quote do
      import Phoenix.LiveView
      import Phoenix.LiveView.Helpers
      alias Bonfire.Common.Web.ComponentID

      unquote(view_helpers())
    end
  end

  def live_plug(_opts \\ []) do
    quote do
      unquote(common_helpers())

      import Phoenix.LiveView
    end
  end

  def plug(_opts \\ []) do
    quote do
      unquote(common_helpers())

      import Plug.Conn
      import Phoenix.Controller

    end
  end

  def router(opts \\ []) do
    quote do
      use Phoenix.Router, unquote(opts)
      unquote(common_helpers())

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router

      # unquote(Bonfire.Common.Extend.quoted_use_if_enabled(Thesis.Router))

    end
  end

  def channel(opts \\ []) do
    quote do
      use Phoenix.Channel, unquote(opts)
      import Where

    end
  end


  defp common_helpers do
    quote do
      import Where

      use Bonfire.Common.Utils

      # localisation
      require Bonfire.Web.Gettext
      import Bonfire.Web.Gettext.Helpers

      # deprecated: Phoenix's Helpers
      alias Bonfire.Web.Router.Helpers, as: Routes
      # use instead: Bonfire's voodoo routing, eg: `path(Bonfire.Social.Web.HomeLive):
      import Bonfire.Common.URIs

      import Bonfire.Common.Config, only: [repo: 0]

      import Bonfire.Common.Extend

      import Bonfire.Common.Web.ErrorHelpers
    end
  end

  defp basic_view_helpers do
    quote do
      unquote(common_helpers())

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      # icons
      alias Heroicons.Solid
      alias Heroicons.Outline

      # unquote(Bonfire.Common.Extend.quoted_use_if_enabled(Thesis.View, Bonfire.Common.Web.ContentAreas))

    end
  end

  defp view_helpers do
    quote do
      unquote(basic_view_helpers())

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      # unquote(Bonfire.Common.Extend.quoted_use_if_enabled(Thesis.View, Bonfire.Common.Web.ContentAreas))

    end
  end

  defp live_view_helpers do
    quote do

      unquote(view_helpers())

      # Import LiveView helpers (live_render, live_component, live_patch, etc)
      import Phoenix.LiveView.Helpers
      alias Bonfire.Common.Web.ComponentID

      alias Phoenix.LiveView.JS

      # Import Surface if any dep is using it
      Bonfire.Common.Extend.quoted_import_if_enabled(Surface)

    end
  end

  if Bonfire.Common.Extend.module_exists?(Surface) do
    def surface_view(opts \\ []) do
      opts =
        opts
        |> maybe_put_layout("live.html")

      quote do

        use Surface.LiveView, unquote(opts)

        unquote(surface_helpers())

      end
    end

    def stateful_component(opts \\ []) do
      quote do
        use Surface.LiveComponent, unquote(opts)

        unquote(surface_helpers())

      end
    end

    def stateless_component(opts \\ []) do
      quote do

        use Surface.Component, unquote(opts)

        unquote(surface_helpers())

      end
    end

    defp surface_helpers do
      quote do

        unquote(live_view_helpers())

        # prop globals, :map, default: %{}
        prop current_account, :any
        prop current_user, :any

        alias Surface.Components.Link
        alias Surface.Components.LivePatch
        alias Surface.Components.LiveRedirect

        alias Surface.Components.Form
        alias Surface.Components.Form.Field
        alias Surface.Components.Form.FieldContext
        alias Surface.Components.Form.Label
        alias Surface.Components.Form.ErrorTag
        alias Surface.Components.Form.Inputs
        alias Surface.Components.Form.HiddenInput
        alias Surface.Components.Form.HiddenInputs
        alias Surface.Components.Form.TextInput
        alias Surface.Components.Form.TextArea
        alias Surface.Components.Form.NumberInput
        alias Surface.Components.Form.RadioButton
        alias Surface.Components.Form.Select
        alias Surface.Components.Form.MultipleSelect
        alias Surface.Components.Form.OptionsForSelect
        alias Surface.Components.Form.DateTimeSelect
        alias Surface.Components.Form.TimeSelect
        alias Surface.Components.Form.Checkbox
        alias Surface.Components.Form.ColorInput
        alias Surface.Components.Form.DateInput
        alias Surface.Components.Form.TimeInput
        alias Surface.Components.Form.DateTimeLocalInput
        alias Surface.Components.Form.EmailInput
        alias Surface.Components.Form.PasswordInput
        alias Surface.Components.Form.RangeInput
        alias Surface.Components.Form.SearchInput
        alias Surface.Components.Form.TelephoneInput
        alias Surface.Components.Form.UrlInput
        alias Surface.Components.Form.FileInput
        alias Surface.Components.Form.TextArea

        alias Bonfire.Common.Web.LazyImage

      end
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defmacro __using__({which, opts}) when is_atom(which) and is_list(opts) do
    apply(__MODULE__, which, [opts])
  end
end
