defmodule Bonfire.Common.TextExtended do
  import Bonfire.Common.Extend
  extend_module(Bonfire.Common.Text)

  def blank?(str_or_nil \\ 1) do
    require Logger
    Logger.info("Check if #{str_or_nil} is considered blank")
    # call function from original module:
    super(str_or_nil)
  end
end
