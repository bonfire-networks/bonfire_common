defmodule Bonfire.Common.Swatches do
  @moduledoc """
  A fixed set of named colours (Tailwind's 17 hues), for what has one colour out of a few rather than any colour: a topic, a group or a label.

  What is stored is the name (eg. `"violet"`). The CSS class of the same name (`class/1`, eg. `topic-violet`, in `bonfire_ui_common/assets/css/topic_swatches.css`) sets the colours to use for it in light and dark themes (`--topic-ink`, `--topic-wash`).
  """
  alias Bonfire.Common.Enums

  @names ~w(red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose)

  @doc "The names of the swatches, in the order a picker shows them."
  def names, do: @names

  @doc """
  The swatch name as a string, or nil if it is not one of the set.

      iex> normalize(:violet)
      "violet"

      iex> normalize("beige")
      nil
  """
  def normalize(name) when is_atom(name) and not is_nil(name), do: normalize(Atom.to_string(name))
  def normalize(name) when is_binary(name) and name in @names, do: name
  def normalize(_), do: nil

  @doc "Whether this is the name of a swatch."
  def valid?(name), do: normalize(name) != nil

  @doc """
  The CSS class that sets the colours of a swatch, or nil if it is not one.

      iex> class("violet")
      "topic-violet"
  """
  def class(name) do
    if name = normalize(name), do: "topic-" <> name
  end

  @doc "A swatch picked from a seed (eg. an object's id), the same one every time."
  def from_seed(seed), do: Enums.pick_by_hash(@names, seed)
end
