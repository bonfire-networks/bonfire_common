Code.eval_file("mess.exs", if(File.exists?("../../lib/mix/mess.exs"), do: "../../lib/mix/"))
Code.eval_file("mixer.ex", if(File.exists?("../../lib/mix/mixer.ex"), do: "../../lib/mix/", else: "./lib/mix/"))

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
    end ++
      [
        app: :bonfire_common,
        version: "0.1.0",
        elixir: "~> 1.10",
        elixirc_paths: elixirc_paths(Mix.env()),
        start_permanent: Mix.env() == :prod,
        compilers: [] ++ Mix.compilers(),
        deps:
          Mess.deps([
            {:assert_value, ">= 0.0.0", only: [:dev, :test]},
            {:zest, "~> 0.1", optional: true},
            {:sentry, "~> 10.0", optional: true},
            {:dataloader, "~> 2.0", optional: true},
            {:floki, "~> 0.36", optional: true},
            {:emote,
             git: "https://github.com/bonfire-networks/emote", optional: true},
            {:text, "~> 0.2.0", optional: true},
            {:text_corpus_udhr, "~> 0.1.0", optional: true},
            # needed for graphql client, eg github for changelog
            {:neuron, "~> 5.0", optional: true},
            # for extension install + mix tasks that do patching 
            {:igniter, "~> 0.3", optional: true} 
          ])
      ]
  end

    defp elixirc_paths(:test), do: ["test/support" | elixirc_paths(:dev)]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]
end
