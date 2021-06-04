defmodule Bonfire.Web.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:

      import Bonfire.Web.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext,
    otp_app: :bonfire_common,
    priv: Bonfire.Common.Config.get!(:localisation_path)

  def default_locale, do: "en" # TODO: configurable

  defmacro l(msgid, bindings \\ %{}), do: Gettext.gettext(Bonfire.Web.Gettext, msgid, bindings)

  defmacro ln(msgid, msgid_plural, n, bindings \\ %{}), do: Gettext.ngettext(Bonfire.Web.Gettext, msgid, msgid_plural, n, bindings) # pluralised
  defmacro lnc(msgctxt, msgid, msgid_plural, n, bindings \\ %{}), do: Gettext.pngettext(Bonfire.Web.Gettext, msgctxt, msgid, msgid_plural, n, bindings) # pluralised+context
  defmacro lnd(domain, msgid, msgid_plural, n, bindings \\ %{}), do: Gettext.dngettext(Bonfire.Web.Gettext, domain, msgid, msgid_plural, n, bindings) # pluralised+domain
  defmacro lndc(domain, msgctxt, msgid, msgid_plural, n, bindings \\ %{}), do: Gettext.dngettext(Bonfire.Web.Gettext, domain, msgctxt, msgid, msgid_plural, n, bindings) # pluralised+domain+context

  defmacro ld(domain, msgid, bindings \\ %{}), do: Gettext.dgettext(Bonfire.Web.Gettext, domain, msgid, bindings) # with domain other than default

  defmacro lc(msgctxt, msgid, bindings \\ %{}), do: Gettext.pgettext(Bonfire.Web.Gettext, msgctxt, msgid, bindings) # with context

  defmacro ldc(domain, msgctxt, msgid, bindings \\ %{}), do: Gettext.dngettext(Bonfire.Web.Gettext, domain, msgctxt, msgid, bindings) # with comain+context

end
