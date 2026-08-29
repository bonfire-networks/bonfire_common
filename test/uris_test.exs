defmodule Bonfire.Common.URIsTest do
  use ExUnit.Case, async: true

  alias Bonfire.Common.URIs

  describe "strip_tracking_params/1" do
    test "strips utm_* and known tracking params, and the fragment" do
      assert URIs.strip_tracking_params(
               "https://blog.example.com/post/?utm_source=x&utm_medium=y&fbclid=abc#section"
             ) == "https://blog.example.com/post/"
    end

    test "strips the fragment" do
      assert URIs.strip_tracking_params("https://blog.example.com/post/#section") ==
               "https://blog.example.com/post/"
    end

    test "keeps non-tracking params (and their order-independent set)" do
      out = URIs.strip_tracking_params("https://blog.example.com/p?id=7&utm_campaign=z&page=2")
      assert out =~ "id=7"
      assert out =~ "page=2"
      refute out =~ "utm_campaign"
    end

    test "leaves a clean url untouched (aside from dropping an empty query/fragment)" do
      assert URIs.strip_tracking_params("https://blog.example.com/post/") ==
               "https://blog.example.com/post/"
    end

    test "passes non-binaries through" do
      assert URIs.strip_tracking_params(nil) == nil
    end
  end

  describe "strip_trailing_slash/1" do
    test "strips a non-root trailing slash" do
      assert URIs.strip_trailing_slash("https://blog.example.com/post/") ==
               "https://blog.example.com/post"
    end

    test "keeps the root slash" do
      assert URIs.strip_trailing_slash("https://blog.example.com/") ==
               "https://blog.example.com/"
    end

    test "leaves a slash-less path untouched" do
      assert URIs.strip_trailing_slash("https://blog.example.com/post") ==
               "https://blog.example.com/post"
    end

    test "preserves the query while stripping the path's trailing slash" do
      assert URIs.strip_trailing_slash("https://blog.example.com/post/?id=7") ==
               "https://blog.example.com/post?id=7"
    end

    test "passes non-binaries through" do
      assert URIs.strip_trailing_slash(nil) == nil
    end
  end

  describe "canonical_url/2" do
    test "uses the normalized public base URL for relative paths" do
      path = "/post/01M0DQ4JFGM29V771YBY5RK92S"

      for relative <- [path, %{path: path}] do
        assert URIs.canonical_url(relative) == "#{URIs.base_url()}#{path}"
      end
    end
  end

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
