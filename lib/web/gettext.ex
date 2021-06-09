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

  @default_locale "en" # TODO: configurable?

  use Gettext,
    otp_app: :bonfire_common,
    default_locale: @default_locale,
    priv: Bonfire.Common.Config.get!(:localisation_path)

  def default_locale, do: @default_locale


end
defmodule Bonfire.Web.Gettext.Helpers do
  # alias the gettext macros for ease-of-use

  import Bonfire.Web.Gettext

  defmacro l(original_text_or_id, bindings \\ nil, context \\ nil, domain \\ nil)

  defmacro l(msgid, bindings, nil, nil) do
    # IO.inspect(__CALLER__)
    mod = __CALLER__.module
    case Application.get_application(mod) do

      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->

        IO.inspect(msgid, label: "based on module #{inspect mod} of #{inspect otp_app}")

        quote do: dgettext(unquote(Atom.to_string(otp_app)), unquote(msgid), unquote(bindings) || %{})

      _ ->
        IO.inspect(msgid, label: "no domain or context / #{inspect mod}")

        quote do: gettext(unquote(msgid), unquote(bindings) || %{})
    end
  end

  # defmacro l(msgid, bindings, context, nil) do
  #   case Application.get_application(__CALLER__) do
  #     otp_app when is_atom(otp_app) -> dngettext(otp_app, context, msgid, bindings || %{}) |> IO.inspect(label: "context, based on module")
  #     _ -> pgettext(context, msgid, bindings || %{}) |> IO.inspect(label: "custom context, no domain")
  #   end
  # end

  # defmacro l(msgid, bindings, nil, domain) do
  #   dgettext(domain, msgid, bindings || %{}) |> IO.inspect(label: "custom domain")
  # end

  # defmacro l(msgid, bindings, context, domain) do
  #    dngettext(otp_app, context, msgid, bindings || %{}) |> IO.inspect(label: "custom context+domain")
  # end


  # defmacro ln(msgid, msgid_plural, n, bindings \\ %{}), do: ngettext(msgid, msgid_plural, n, bindings) # pluralised
  # defmacro lnc(msgctxt, msgid, msgid_plural, n, bindings \\ %{}), do: pngettext(msgctxt, msgid, msgid_plural, n, bindings) # pluralised+context
  # defmacro lnd(domain, msgid, msgid_plural, n, bindings \\ %{}), do: dngettext(domain, msgid, msgid_plural, n, bindings) # pluralised+domain
  # defmacro lndc(domain, msgctxt, msgid, msgid_plural, n, bindings \\ %{}), do: dngettext(domain, msgctxt, msgid, msgid_plural, n, bindings) # pluralised+domain+context

  # defmacro ld(domain, msgid, bindings \\ %{}), do: dgettext(domain, msgid, bindings) # with domain other than default
  # defmacro lc(msgctxt, msgid, bindings \\ %{}), do: pgettext(msgctxt, msgid, bindings) # with context
  # defmacro ldc(domain, msgctxt, msgid, bindings \\ %{}), do: dngettext(domain, msgctxt, msgid, bindings) # with comain+context

end
