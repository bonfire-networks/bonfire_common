defmodule ConsoleHelpers do
  defmacro __using__(_) do
    quote do
      alias Bonfire.Repo
      alias Bonfire.Data
      alias Bonfire.Me
      alias Bonfire.Social
      alias Bonfire.Common

      import IEx.Helpers, except: [l: 1]
      # ^ to avoid conflicting with our Gettext helpers

      use Common.Utils
      import Bonfire.Me.Fake
      import Untangle
    end
  end
end
