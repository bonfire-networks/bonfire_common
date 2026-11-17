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

  test "a string rendered on another page gets that page added too", %{
    domain: domain,
    po_file: po_file
  } do
    for path <- ["/first", "/first", "/second"] do
      POAnnotator.patch_async("Annotator probe", domain, "lib/probe.ex", 1, @url_host, path)
    end

    :ok = POAnnotator.flush()

    assert File.read!(po_file) =~ "#. URLs: #{@url_host}/second #{@url_host}/first"
  end

  test "a string keeps at most 4 pages", %{domain: domain, po_file: po_file} do
    for n <- 1..6 do
      POAnnotator.patch_async("Annotator probe", domain, "lib/probe.ex", 1, @url_host, "/p#{n}")
    end

    :ok = POAnnotator.flush()

    [urls_line] = Regex.run(~r/#\. URLs: .*/, File.read!(po_file))
    assert length(Regex.scan(~r/#{@url_host}/, urls_line)) == 4
  end

  # every `l()` render in a test suite casts here, so the work for a repeated render must not grow with the size of the .po: a full walk per cast backed the mailbox up until the end-of-suite flush timed out and lost the annotations
  test "a repeated render costs the same however big the .po is", %{
    domain: domain,
    po_file: po_file
  } do
    filler =
      for n <- 1..2000, into: "" do
        "\n#: lib/filler.ex:#{n}\nmsgid \"Filler #{n}\"\nmsgstr \"\"\n"
      end

    File.write!(po_file, File.read!(po_file) <> filler)

    patch = fn ->
      POAnnotator.patch_async("Annotator probe", domain, "lib/probe.ex", 1, @url_host, "/probe")
    end

    # the first render parses the file and adds the URL
    patch.()
    :ok = POAnnotator.flush()

    pid = Process.whereis(POAnnotator)
    {:reductions, before} = Process.info(pid, :reductions)

    for _ <- 1..200, do: patch.()
    :ok = POAnnotator.flush()

    {:reductions, after_patches} = Process.info(pid, :reductions)

    # a walk of the 2001 entries costs well over 2001 reductions on its own
    assert (after_patches - before) / 200 < 500
  end

  # CI spreads the UI suite over several jobs, each annotating only the strings its tests rendered, so their copies of each .po are merged before being pushed to translators
  describe "merging the annotated copies of a .po" do
    test "an entry annotated in only one copy keeps its URLs" do
      merged =
        POAnnotator.merge_annotations([
          po_with_urls([]),
          po_with_urls(["#{@url_host}/a"])
        ])

      assert urls_of(merged) == ["#{@url_host}/a"]
    end

    test "URLs from several copies are combined, up to 4" do
      merged =
        POAnnotator.merge_annotations([
          po_with_urls(["#{@url_host}/a", "#{@url_host}/b"]),
          po_with_urls(["#{@url_host}/b", "#{@url_host}/c"]),
          po_with_urls(["#{@url_host}/d", "#{@url_host}/e"])
        ])

      assert urls_of(merged) == Enum.map(~w(a b c d), &"#{@url_host}/#{&1}")
    end

    test "comments that aren't URLs are kept" do
      merged =
        POAnnotator.merge_annotations([
          po_with_urls([], ["Shown on the login button"]),
          po_with_urls(["#{@url_host}/login"])
        ])

      assert [%{extracted_comments: comments}] = merged.messages
      assert "Shown on the login button" in Enum.map(comments, &String.trim/1)
      assert urls_of(merged) == ["#{@url_host}/login"]
    end

    test "the merge task writes each merged .po into the target dir" do
      tmp = Path.join(System.tmp_dir!(), "po_merge_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(tmp) end)

      for {dir, url} <- [{"one", "/a"}, {"two", "/b"}] do
        File.mkdir_p!(Path.join(tmp, dir))

        File.write!(
          Path.join([tmp, dir, "probe.po"]),
          Expo.PO.compose(po_with_urls(["#{@url_host}#{url}"]))
        )
      end

      Mix.Tasks.Bonfire.Localise.MergeAnnotations.run([
        "--into",
        Path.join(tmp, "merged"),
        Path.join(tmp, "one"),
        Path.join(tmp, "two")
      ])

      merged = Expo.PO.parse_file!(Path.join([tmp, "merged", "probe.po"]))
      assert urls_of(merged) == ["#{@url_host}/a", "#{@url_host}/b"]
    end
  end

  defp po_with_urls(urls, other_comments \\ []) do
    url_comment = if urls == [], do: [], else: ["#. URLs: " <> Enum.join(urls, " ")]

    Expo.PO.parse_string!("""
    msgid ""
    msgstr ""

    #{Enum.join(url_comment ++ Enum.map(other_comments, &"#. #{&1}"), "\n")}
    #: lib/probe.ex:1
    msgid "Annotator probe"
    msgstr ""
    """)
  end

  defp urls_of(%Expo.Messages{messages: [message]}) do
    message.extracted_comments
    |> Enum.find_value([], fn
      " URLs: " <> urls -> String.split(urls, " ", trim: true)
      _ -> nil
    end)
  end
end
