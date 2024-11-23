defmodule Bonfire.Common.ConfigTest do
  use Bonfire.Common.DataCase, async: true

  Bonfire.Common.Config.put(:test_key, "test_value")

  doctest Bonfire.Common.Opts, import: false
  doctest Bonfire.Common.Config, import: true
  doctest Bonfire.Common.Settings, import: true

  alias Bonfire.Common.EnvConfig
  doctest Bonfire.Common.EnvConfig, import: false
end
