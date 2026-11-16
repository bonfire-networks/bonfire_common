defmodule Bonfire.Common.HTTP.BodyCapTest do
  @moduledoc """
  `Bonfire.Common.HTTP` is used for URLs that come from users or remote servers, so a server that answers with a huge body must not make us hold all of it: an answer over the size limit is an error, and an ordinary one comes through. The HTTP adapter is mocked, so the answers are made up here.
  """
  use ExUnit.Case, async: false
  @moduletag :backend

  alias Bonfire.Common.HTTP

  @megabyte 1024 * 1024

  defp serve(body) do
    Tesla.Mock.mock(fn _env -> %Tesla.Env{status: 200, body: body} end)
  end

  test "an ordinary answer comes through (control)" do
    serve(String.duplicate("a", 100 * 1024))

    assert {:ok, %{status: 200, body: body}} = HTTP.get("http://example.com/page")
    assert byte_size(body) == 100 * 1024
  end

  test "an answer of 20 MB is an error" do
    serve(String.duplicate("a", 20 * @megabyte))

    refute match?({:ok, %{status: 200}}, HTTP.get("http://example.com/page"))
  end
end
