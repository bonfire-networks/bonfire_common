defmodule Bonfire.Common.DocsTest do
  use ExUnit.Case, async: true

  doctest Bonfire.Common.Utils, import: true
  doctest Bonfire.Common.Enums, import: true
end
