# # what module we want to override
# module = Bonfire.Common.Text

# # start by archiving the old module
# Bonfire.Common.Module.Override.clone_original(module)

# defmodule module do
#   use Bonfire.Common.Module.Override

#   ####
#   # Redefine existing functions, or add new ones:
#   ####

#   # example of straight up replacing a function
#   def random_string(max_length), do: Enum.random(0..max_length)

#   # example of modifying the input of a function
#   def strlen(x), do: x |> String.trim() |> Original.strlen()

#   # example of modifying the output of a function
#   def blank?(str_or_nil \\ 1) do
#       require Logger
#       Logger.info("Check if #{str_or_nil} is considered blank")
#       # call function from original module:
#       Original.blank?(str_or_nil)
#    end
# end
