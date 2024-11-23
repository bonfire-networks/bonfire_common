defmodule Bonfire.Common.ETest do
  use Bonfire.Common.DataCase, async: true
  require Bonfire.Common.E

  doctest Bonfire.Common.E, import: false
end
