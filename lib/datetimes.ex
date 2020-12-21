defmodule Bonfire.Common.DateTimes do

  def now(), do: DateTime.utc_now()

  def past?(%DateTime{}=dt) do
    DateTime.compare(now(), dt) == :gt
  end

  def future?(%DateTime{}=dt) do
    DateTime.compare(now(), dt) == :lt
  end

end
