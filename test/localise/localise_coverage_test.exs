defmodule Bonfire.Common.Localise.CoverageTest do
  @moduledoc """
  The coverage escript counts, per locale and domain, how many source strings a locale translates, so the language picker can show how complete each language is.

  The fixture (`test/support/localisation/coverage_fixture`): `a.po` has 3 live entries (one plural) and one obsolete `#~`. `es` translates `Alpha` and has `Beta` as fuzzy. `es_ES` translates `Beta` and one key the source no longer has. `b.po` has no `es` file.
  """
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend
  @moduletag :tmp_dir

  @fixture Path.expand("../support/localisation/coverage_fixture", __DIR__)

  # a copy, so the run writes its `coverage.json` outside the repo
  setup %{tmp_dir: tmp_dir} do
    File.cp_r!(@fixture, tmp_dir)
    {:ok, dir: tmp_dir}
  end

  defp coverage(dir), do: dir |> Path.join("coverage.json") |> File.read!() |> JSON.decode!()

  test "counts the live source entries as the total, leaving out obsolete ones", %{dir: dir} do
    Mix.Tasks.Bonfire.LocaliseCoverage.run(["--dir", dir])

    assert %{"a" => 3, "b" => 1} == coverage(dir)["total"]
  end

  test "a fuzzy translation does not count", %{dir: dir} do
    Mix.Tasks.Bonfire.LocaliseCoverage.run(["--dir", dir])

    assert 1 == coverage(dir)["translated"]["es"]["a"]
  end

  test "a regional locale counts the union with its base, leaving out keys the source dropped", %{
    dir: dir
  } do
    Mix.Tasks.Bonfire.LocaliseCoverage.run(["--dir", dir])

    assert 2 == coverage(dir)["translated"]["es_ES"]["a"]
  end

  test "a domain with no file for the locale counts 0", %{dir: dir} do
    Mix.Tasks.Bonfire.LocaliseCoverage.run(["--dir", dir])

    assert 0 == coverage(dir)["translated"]["es"]["b"]
    assert 0 == coverage(dir)["translated"]["es_ES"]["b"]
  end

  test "with the source locale set to the base, the regional locale has no chain", %{dir: dir} do
    Mix.Tasks.Bonfire.LocaliseCoverage.run(["--dir", dir, "--source-locale", "es"])

    assert 1 == coverage(dir)["translated"]["es_ES"]["a"]
  end

  test "the file is stable: keys are sorted", %{dir: dir} do
    Mix.Tasks.Bonfire.LocaliseCoverage.run(["--dir", dir])
    json = File.read!(Path.join(dir, "coverage.json"))

    {es, _} = :binary.match(json, ~s("es":))
    {es_es, _} = :binary.match(json, ~s("es_ES":))
    {total, _} = :binary.match(json, ~s("total":))
    {translated, _} = :binary.match(json, ~s("translated":))

    assert es < es_es
    assert total < translated
  end
end
