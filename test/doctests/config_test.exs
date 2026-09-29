defmodule Bonfire.Common.ConfigTest do
  use Bonfire.Common.DataCase, async: true
  use Bonfire.Common.Utils

  # per test process, since these run async
  setup do
    Process.put([:bonfire, :test_key], "test_value")
    :ok
  end

  doctest Bonfire.Common.Opts, import: false
  doctest Bonfire.Common.Config, import: true
  doctest Bonfire.Common.Settings, import: true

  alias Bonfire.Common.EnvConfig
  doctest Bonfire.Common.EnvConfig, import: false
end
