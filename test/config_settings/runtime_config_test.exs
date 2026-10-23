defmodule Bonfire.Common.RuntimeConfigTest do
  use Bonfire.Common.DataCase, async: true
  alias Bonfire.Common.Repo

  test "tests run in the test database, whatever DATABASE_URL names" do
    %{rows: [[connected]]} = Repo.query!("SELECT current_database()")

    assert connected == Repo.config()[:database]
    assert String.starts_with?(connected, "bonfire_test_")
  end

  test "url_with_database/2 swaps only the database" do
    assert Bonfire.Common.RuntimeConfig.url_with_database(
             "ecto://user:pass@localhost:5433/bonfire_db?ssl=false",
             "bonfire_test__0"
           ) == "ecto://user:pass@localhost:5433/bonfire_test__0?ssl=false"
  end
end
