defmodule Bonfire.Common.Localise.POAnnotatorTest do
  @moduledoc """
  Covers `POAnnotator.flush/0`: annotations are normally written after a few seconds of inactivity, which a short-lived test run (or the end of a suite) never waits for, so a flush must write every pending file before it returns.

  Also covers matching the file a string was rendered from to the `.po` reference, wherever the extension is installed.
  """
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg, like the other bare `ExUnit.Case` modules
  @moduletag :backend

  alias Bonfire.Common.Localise.POAnnotator

  @url_host "https://campground.bonfire.cafe"

  # a domain per test: the annotator keeps each parsed `.po` in memory, so a shared file would carry one test's annotations into the next
  setup do
    domain = "test_po_annotator_#{System.unique_integer([:positive])}"
    po_file = "priv/localisation/#{domain}.po"

    File.write!(po_file, """
    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\\n"

    #: lib/probe.ex:1
    msgid "Annotator probe"
    msgstr ""
    """)

    on_exit(fn -> File.rm(po_file) end)

    %{domain: domain, po_file: po_file}
  end

  test "flush writes the URL comment of a pending patch straight away", %{
    domain: domain,
    po_file: po_file
  } do
    POAnnotator.patch_async("Annotator probe", domain, "lib/probe.ex", 1, @url_host, "/probe")

    :ok = POAnnotator.flush()

    assert File.read!(po_file) =~ "#. URLs: #{@url_host}/probe"
  end

  # the `.po` references are relative to the extension (`lib/probe.ex`), but the macro passes the absolute path of the source file, which sits under a different directory depending on how the extension is installed: `extensions/` for a local checkout, `deps/` on CI and for anyone who did not clone it, `forks/` for a patched one
  for dir <- ["extensions", "deps", "forks"] do
    test "annotates a string whose source is under #{dir}/", %{domain: domain, po_file: po_file} do
      file = Path.join([File.cwd!(), unquote(dir), "bonfire_probe", "lib", "probe.ex"])

      POAnnotator.patch_async("Annotator probe", domain, file, 1, @url_host, "/probe")

      :ok = POAnnotator.flush()

      assert File.read!(po_file) =~ "#. URLs: #{@url_host}/probe"
    end
  end

  # one warning per missing string, not one per render: a wrong path would otherwise log on every `l()` call of a test suite, which buried the annotator in its own log
  test "warns once about a string that is not in the .po", %{domain: domain} do
    log =
      ExUnit.CaptureLog.capture_log([level: :warning], fn ->
        for _ <- 1..3 do
          POAnnotator.patch_async(
            "Not extracted",
            domain,
            "lib/missing.ex",
            9,
            @url_host,
            "/missing"
          )
        end

        :ok = POAnnotator.flush()
      end)

    assert length(String.split(log, "an entry was not found")) - 1 == 1
  end

  test "flush with nothing pending is a no-op", %{po_file: po_file} do
    assert :ok = POAnnotator.flush()
    refute File.read!(po_file) =~ "#. URLs:"
  end
end
