defmodule Bonfire.Common.Localise.Gettext.Plural do
  @moduledoc """
  Defines a plural forms module for Gettext that uses CLDR plural rules
  https://cldr.unicode.org/index/cldr-spec/plural-rules
  """
  use Cldr.Gettext.Plural, cldr_backend: Bonfire.Common.Localise.Cldr
end

defmodule Bonfire.Common.Localise.Gettext do
  @moduledoc """
  Default Gettext module
  It is recommended to use the more convenient macros in `Bonfire.Common.Localise.Gettext.Helpers` instead.
  """

  # if Bonfire.Common.Config.get(:env) == :dev do
  #   use PseudoGettext,
  #     otp_app: :bonfire_common,
  #     default_locale: Bonfire.Common.Config.get_ext(:bonfire_common, [Bonfire.Common.Localise.Cldr, :default_locale], "en"),
  #     plural_forms: Bonfire.Common.Localise.Gettext.Plural,
  #     priv: Bonfire.Common.Config.get!(:localisation_path)
  # else
  use Gettext,
    otp_app: :bonfire_common,
    default_locale:
      Bonfire.Common.Config.get_ext(
        :bonfire_common,
        [Bonfire.Common.Localise.Cldr, :default_locale],
        "en"
      ),
    plural_forms: Bonfire.Common.Localise.Gettext.Plural,
    priv: Application.compile_env!(:bonfire, :localisation_path)

  # end
end

defmodule Bonfire.Common.Localise.Gettext.Helpers do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:

      import Bonfire.Common.Localise.Gettext

      # Simple translation

      usage:
        <%= l("Hello") %>
        <%= l("Hello %{name}", name: "Bookchin") %>
        <%= l("Hi", [], "test context") %>


      output:
        Hello
        Hello Bookchin
        Hi


      # Plural translation

      usage:
        <%= lp("Hi friend", "Hi friends", 2) %>
        <%= lp("Hiya %{user_or_users}", "Hiyas %{user_or_users}", 1, [user_or_users: "Bookchin"], "test context") %>

      output:
        Hi friends
        Hiya Bookchin

  See the [Gettext Docs](https://hexdocs.pm/gettext) for details.
  """

  # alias the gettext macros for ease-of-use

  import Bonfire.Common.Localise.Gettext
  import Untangle

  defmacro l(original_text_or_id, bindings \\ [], context \\ nil, domain \\ nil)

  defmacro l(msgid, bindings, nil, nil)
           when is_list(bindings) or (is_map(bindings) and is_binary(msgid)) do
    case caller_app(__CALLER__.module) do
      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->
        # debug(msgid, "domain based on caller module: #{inspect otp_app}")

        quote do:
                dgettext(
                  unquote(Atom.to_string(otp_app)),
                  unquote(msgid),
                  unquote(bindings)
                )

      _ ->
        # debug(msgid, "no domain or context")

        quote do: gettext(unquote(msgid), unquote(bindings))
    end
  end

  defmacro l(msgid, bindings, context, nil)
           when (is_binary(context) and is_list(bindings)) or
                  (is_map(bindings) and is_binary(msgid)) do
    case caller_app(__CALLER__.module) do
      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->
        # debug(msgid, "custom context #{context} + domain based on module #{inspect otp_app}")

        quote do:
                dpgettext(
                  unquote(Atom.to_string(otp_app)),
                  unquote(context),
                  unquote(msgid),
                  unquote(bindings)
                )

      _ ->
        # debug(msgid, "custom context #{context} - no domain")

        quote do: pgettext(unquote(context), unquote(msgid), unquote(bindings))
    end
  end

  defmacro l(msgid, bindings, nil, domain)
           when (is_binary(domain) and is_list(bindings)) or
                  (is_map(bindings) and is_binary(msgid)) do
    # debug(msgid, "custom domain #{domain}")

    quote do: dgettext(unquote(domain), unquote(msgid), unquote(bindings))
  end

  defmacro l(msgid, bindings, context, domain)
           when (is_binary(domain) and is_binary(context) and is_list(bindings)) or
                  (is_map(bindings) and is_binary(msgid)) do
    # debug(msgid, "custom context #{context} + domain #{domain}")

    quote do:
            dpgettext(
              unquote(domain),
              unquote(context),
              unquote(msgid),
              unquote(bindings)
            )
  end

  ### Localisation with pluralisation ###

  defmacro lp(
             original_text_or_id,
             msgid_plural,
             n,
             bindings \\ [],
             context \\ nil,
             domain \\ nil
           )

  defmacro lp(msgid, msgid_plural, n, bindings, nil, nil)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or is_map(bindings) do
    case caller_app(__CALLER__.module) do
      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->
        # debug(msgid, "plural: domain based on module #{inspect mod}: #{inspect otp_app}")

        quote do:
                dngettext(
                  unquote(Atom.to_string(otp_app)),
                  unquote(msgid),
                  unquote(msgid_plural),
                  unquote(n),
                  unquote(bindings)
                )

      _ ->
        # debug(msgid, "plural: no domain or context / #{inspect mod}")

        quote do:
                ngettext(
                  unquote(msgid),
                  unquote(msgid_plural),
                  unquote(n),
                  unquote(bindings)
                )
    end
  end

  defmacro lp(msgid, msgid_plural, n, bindings, context, nil)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or
                  (is_map(bindings) and is_binary(context)) do
    case caller_app(__CALLER__.module) do
      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->
        # debug(msgid, "plural: custom context #{context} + domain based on module #{inspect otp_app}")

        quote do:
                dpngettext(
                  unquote(Atom.to_string(otp_app)),
                  unquote(context),
                  unquote(msgid),
                  unquote(msgid_plural),
                  unquote(n),
                  unquote(bindings)
                )

      _ ->
        # debug(msgid, "plural: custom context #{context} - no domain")

        quote do:
                pngettext(
                  unquote(context),
                  unquote(msgid),
                  unquote(msgid_plural),
                  unquote(n),
                  unquote(bindings)
                )
    end
  end

  defmacro lp(msgid, msgid_plural, n, bindings, nil, domain)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or
                  (is_map(bindings) and is_binary(domain)) do
    # debug(msgid, "plural: custom domain #{domain}")

    quote do:
            dngettext(
              unquote(domain),
              unquote(msgid),
              unquote(msgid_plural),
              unquote(n),
              unquote(bindings)
            )
  end

  defmacro lp(msgid, msgid_plural, n, bindings, context, domain)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or
                  (is_map(bindings) and is_binary(context) and is_binary(domain)) do
    # debug(msgid, "plural: custom context #{context} + domain #{domain}")

    quote do:
            dpngettext(
              unquote(domain),
              unquote(context),
              unquote(msgid),
              unquote(msgid_plural),
              unquote(n),
              unquote(bindings)
            )
  end

  def localise_dynamic(msgid, caller_module \\ nil) do
    otp_app = caller_app(caller_module) || :bonfire

    Gettext.dgettext(
      Bonfire.Common.Localise.Gettext,
      Atom.to_string(otp_app),
      "#{msgid}"
    )
  end

  @doc """
  Localise a list of strings at compile time
  """
  defmacro localise_strings(strings, caller_module \\ nil) do
    {strings, _} = Code.eval_quoted(strings)
    {caller_module, _} = Code.eval_quoted(caller_module)
    domain = Atom.to_string(caller_app(caller_module || __CALLER__.module))

    for msg <- strings do
      quote do
        # l unquote(msg)
        dgettext(unquote(domain), unquote(msg), [])
      end
    end
  end

  defp caller_app(caller_module) when is_atom(caller_module) do
    case Application.get_application(caller_module) do
      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->
        otp_app

      _ ->
        mix =
          if Bonfire.Common.Extend.module_enabled?(Mix.Project),
            do: Mix.Project.get()

        if mix, do: mix.project()[:app]
    end
  end
end
