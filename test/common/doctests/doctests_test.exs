defmodule Bonfire.Common.DocsTest do
  use Bonfire.Common.DataCase, async: true
  use Bonfire.Common.Utils
  alias Needle.Pointer

  Bonfire.Common.Config.put(:test_key, "test_value")

  doctest Bonfire.Common.Utils, import: true

  doctest Bonfire.Common.Localise, import: true
  doctest Bonfire.Common.Localise.Gettext, import: true

  doctest Bonfire.Common.Extend, import: true
  doctest Bonfire.Common.Modularity.DeclareHelpers, import: true
  doctest Bonfire.Common.Extensions, import: true
  doctest Bonfire.Common.Extensions.Diff, import: true

  doctest Bonfire.Common.DatesTimes, import: true
  doctest Bonfire.Common.Enums, import: true
  doctest Bonfire.Common.Errors, import: true
  doctest Bonfire.Common.Text, import: true
  doctest Bonfire.Common.Types, import: true
  doctest Bonfire.Common.URIs, import: true
  # doctest Bonfire.Common.Media, import: true

  # doctest Bonfire.Common.Needles, import: true
  doctest Bonfire.Common.Needles.Tables, import: true
end
