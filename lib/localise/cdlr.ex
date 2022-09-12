defmodule Bonfire.Common.Localise.Cldr do
  @moduledoc """
  This module integrates `ex_cldr` - an Elixir library for the Unicode Consortium's Common Locale Data Repository (CLDR), used to simplify the locale specific formatting and parsing of numbers, lists, currencies, calendars, units of measure and dates/times.

  Define a backend module that will host our Cldr configuration and public API.

  Most function calls in Cldr will be calls to functions on this module.
  """
  use Cldr,
    # which OTP app the ex_cldr config is set on
    otp_app: :bonfire_common
end
