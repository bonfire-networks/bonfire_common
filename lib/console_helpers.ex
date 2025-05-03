defmodule ConsoleHelpers do
  @moduledoc "Handy aliases and imports to add to your iex CLI session"
  defmacro __using__(_) do
    quote do
      alias Bonfire.Data
      alias Bonfire.Me
      alias Bonfire.Social
      alias Bonfire.Common
      alias Common.Repo

      import IEx.Helpers, except: [l: 1]
      # ^ to avoid conflicting with our Gettext helpers

      # use Common.Utils # FIXME: Gettext no longer seems to work in IEx?
      import Common.Utils
      __common_utils__()
      use Bonfire.Common.Settings
      import Bonfire.Me.Fake
      import Untangle

      IEx.configure(auto_reload: true)
    end
  end
end
