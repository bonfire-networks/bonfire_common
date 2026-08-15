defmodule Bonfire.Common.URIsTest do
  use ExUnit.Case, async: true

  alias Bonfire.Common.URIs

  describe "versioned_static_path/1" do
    @moduletag :uris

    setup do
      # a real file to stat, so the mtime branch is exercised without depending on built assets
      dir = Path.join([to_string(:code.priv_dir(:bonfire)), "static", "assets"])
      File.mkdir_p!(dir)
      path = Path.join(dir, "__versioned_static_path_test__.js")
      File.write!(path, "// fixture")
      on_exit(fn -> File.rm(path) end)

      # not `:file`, which ExUnit reserves for the test's own source location
      {:ok, url_path: "/assets/__versioned_static_path_test__.js", fixture: path}
    end

    test "busts only when the file actually changes", %{url_path: url_path, fixture: file} do
      before = URIs.versioned_static_path(url_path)

      # the property that matters: an unchanged file keeps the same URL, so caches are not thrown away on every render
      assert before == URIs.versioned_static_path(url_path)

      File.touch!(file, System.os_time(:second) + 60)

      refute before == URIs.versioned_static_path(url_path)
    end

    test "still versions a path with no file on disk", %{} do
      # falls back to a timestamp rather than raising, so a not-yet-built bundle still renders
      assert URIs.versioned_static_path("/assets/__no_such_bundle__.js") =~
               ~r"^/assets/__no_such_bundle__\.js\?v=\d+$"
    end

    test "keeps the path itself intact", %{url_path: url_path} do
      assert URIs.versioned_static_path(url_path) =~ ~r"^#{Regex.escape(url_path)}\?v=\d+$"
    end
  end
end
