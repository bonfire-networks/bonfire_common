defmodule Bonfire.Common.ETest do
  use Bonfire.Common.DataCase, async: true
  require Bonfire.Common.E

  Bonfire.Common.Config.put(:test_key, "test_value")

  doctest Bonfire.Common.E, import: false
end
