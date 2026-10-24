defmodule Bonfire.Common.VocabularyShippedPresetsTest do
  @moduledoc """
  What every extension that declares a kind of `Bonfire.Common.Vocabulary` must get right, whatever it declares. It loops over the kinds that are installed, so a preset added tomorrow is checked with no change here (and with none installed, there is nothing to check).
  """
  # bare `ExUnit.Case` skips the `:backend` tag that `Bonfire.Common.DataCase` applies, so tag it here
  use ExUnit.Case, async: true
  @moduletag :backend

  alias Bonfire.Common.Vocabulary

  # the built-in presets only, whatever an instance's own config adds
  defp declared_kinds,
    do: for(kind <- Vocabulary.kinds(), Vocabulary.built_in(kind) != %{}, do: kind)

  test "every kind has a default preset, named like itself" do
    for kind <- declared_kinds() do
      assert Map.has_key?(Vocabulary.built_in(kind), kind),
             "#{inspect(kind)} has presets but none with its own id, which is the one used until a choice is made"
    end
  end

  test "every preset words every phrase its kind's default does, and only those" do
    for kind <- declared_kinds(), {id, phrases} <- Vocabulary.built_in(kind) do
      expected = kind |> Vocabulary.built_in() |> Map.fetch!(kind) |> Map.keys() |> Enum.sort()

      assert phrases |> Map.keys() |> Enum.sort() == expected,
             "#{inspect(kind)} preset #{inspect(id)} does not have the phrases of #{inspect(kind)}: #{inspect(expected)}"
    end
  end

  test "every phrase is text" do
    for kind <- declared_kinds(),
        {id, phrases} <- Vocabulary.built_in(kind),
        {key, text} <- phrases do
      assert is_binary(text) and text != "",
             "#{inspect(kind)} preset #{inspect(id)}: #{inspect(key)} is #{inspect(text)}"
    end
  end

  test "every kind says which extension declares it, so its phrases are looked up where they were extracted" do
    for kind <- declared_kinds() do
      assert is_atom(Vocabulary.preset(kind, nil).module) and
               not is_nil(Vocabulary.preset(kind, nil).module),
             "#{inspect(kind)} has no `module:`"
    end
  end

  test "every preset can be chosen, and gives back the phrases it was declared with" do
    for kind <- declared_kinds(), id <- Vocabulary.preset_ids(kind) do
      title = Vocabulary.phrase(Vocabulary.preset_for(kind, id), :title, fallback: false)

      assert {to_string(id), title} in Vocabulary.options(kind)
    end
  end
end
