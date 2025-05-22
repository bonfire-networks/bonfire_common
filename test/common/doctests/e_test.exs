defmodule Bonfire.Common.ETest do
  use Bonfire.Common.DataCase, async: true
  use Bonfire.Common.E

  doctest Bonfire.Common, import: true
  doctest Bonfire.Common.E, import: false
end
