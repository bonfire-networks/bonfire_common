defmodule Bonfire.Common.Simulation.WordTest do
  @moduledoc """
  `Simulation.word/1` is a random word, long enough to use as a name: `Faker.Lorem.word()` can return "a", which makes a profile name (3 characters at least) and a username (2) that are refused, so a test that names something with it fails now and then.
  """
  use ExUnit.Case, async: true

  alias Bonfire.Common.Simulation

  # enough draws that the one-letter words of the Lorem list come up
  @draws 500

  test "is at least 3 characters by default" do
    for _ <- 1..@draws, do: assert(String.length(Simulation.word()) >= 3)
  end

  test "is at least as long as asked" do
    for _ <- 1..@draws, do: assert(String.length(Simulation.word(6)) >= 6)
  end
end
