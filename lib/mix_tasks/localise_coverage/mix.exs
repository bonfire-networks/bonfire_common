defmodule Bonfire.LocaliseCoverage do
  use Mix.Project

  def project do
    [
      app: :localise_coverage,
      version: "0.1.0-alpha.1",
      # the built-in `JSON` needs 1.18
      elixir: "~> 1.18",
      deps: [{:expo, "== 1.1.1"}],
      escript: [main_module: Mix.Tasks.Bonfire.LocaliseCoverage]
    ]
  end

  def application, do: [extra_applications: []]
end
