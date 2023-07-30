Code.eval_file("mess.exs", (if File.exists?("../../lib/mix/mess.exs"), do: "../../lib/mix/"))

defmodule Bonfire.Common.MixProject do
  use Mix.Project

  def project do
    if System.get_env("AS_UMBRELLA") == "1" do
      [
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock"
      ]
    else
      []
    end
    ++
    [
      app: :bonfire_common,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      compilers: [] ++ Mix.compilers(),

      deps:
        Mess.deps([
          {:zest, "~> 0.1", optional: true},
          {:sentry, "~> 8.0", optional: true},
          {:dataloader, "~> 2.0", optional: true},
          {:floki, "~> 0.33.1", optional: true},
          {:emote,
           git: "https://github.com/bonfire-networks/emote",
           branch: "master",
           optional: true},
          {:text, "~> 0.2.0", optional: true},
          {:text_corpus_udhr, "~> 0.1.0", optional: true},
          # needed for graphql client, eg github for changelog
          {:neuron, "~> 5.0", only: :dev}
        ])
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]
end
