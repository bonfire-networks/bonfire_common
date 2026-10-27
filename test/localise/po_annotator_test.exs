defmodule Bonfire.Common.Localise.POAnnotatorTest do
  @moduledoc """
  Covers `POAnnotator.flush/0`: annotations are normally written after a few seconds of inactivity, which a short-lived test run (or the end of a suite) never waits for, so a flush must write every pending file before it returns.
  """
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg, like the other bare `ExUnit.Case` modules
  @moduletag :backend

  alias Bonfire.Common.Localise.POAnnotator

  @domain "test_po_annotator"
  @po_file "priv/localisation/#{@domain}.po"
  @url_host "https://campground.bonfire.cafe"

  setup do
    File.write!(@po_file, """
    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\\n"

    #: lib/probe.ex:1
    msgid "Annotator probe"
    msgstr ""
    """)

    on_exit(fn -> File.rm(@po_file) end)
  end

  test "flush writes the URL comment of a pending patch straight away" do
    POAnnotator.patch_async("Annotator probe", @domain, "lib/probe.ex", 1, @url_host, "/probe")

    :ok = POAnnotator.flush()

    assert File.read!(@po_file) =~ "#. URLs: #{@url_host}/probe"
  end

  test "flush with nothing pending is a no-op" do
    assert :ok = POAnnotator.flush()
    refute File.read!(@po_file) =~ "#. URLs:"
  end
end
