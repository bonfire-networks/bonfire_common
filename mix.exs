Code.eval_file("mess.exs")
defmodule Bonfire.Common.MixProject do
  use Mix.Project

  def project do
    [
      app: :bonfire_common,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      compilers: [:gettext] ++ Mix.compilers(),
      deps: Mess.deps([
        {:dbg, "~> 1.0", only: :dev},
        {:zest, "~> 0.1", optional: true},
        {:sentry, "~> 8.0", optional: true},
        {:dataloader, "~> 1.0", optional: true},
        {:solid, "~> 0.12.0", optional: true},
        {:floki, "~> 0.32.1", optional: true},
        {:emote, git: "https://github.com/bonfire-networks/emote", branch: "master", optional: true},
        {:text, "~> 0.2.0", optional: true},
        {:text_corpus_udhr, "~> 0.1.0", optional: true},

        {:neuron, "~> 5.0", only: :dev} # needed for graphql client, eg github for changelog
      ])
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

end
