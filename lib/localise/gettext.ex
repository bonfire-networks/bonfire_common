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
  use Bonfire.Common.Config

  # Limit locales in non-prod environments  
  allowed_locales =
    if Config.env() == :prod or System.get_env("COMPILE_ALL_LOCALES") in ["true", "1"] do
      # In prod, allow all locales discovered in priv directory (default behavior)
      nil
    else
      # In dev/test, only compile specified locales from CLDR config
      Bonfire.Common.Config.get_ext(:bonfire_common, [Bonfire.Common.Localise.Cldr, :locales], [
        "en"
      ])
    end

  # if Bonfire.Common.Config.env() == :dev do
  #   use PseudoGettext,
  #     otp_app: :bonfire_common,
  #     default_locale: Bonfire.Common.Config.get_ext(:bonfire_common, [Bonfire.Common.Localise.Cldr, :default_locale], "en"),
  #     plural_forms: Bonfire.Common.Localise.Gettext.Plural,
  #     priv: Bonfire.Common.Config.get!(:localisation_path)
  # else
  use Gettext.Backend,
    otp_app: :bonfire_common,
    default_locale:
      Bonfire.Common.Config.get_ext(
        :bonfire_common,
        [Bonfire.Common.Localise.Cldr, :default_locale],
        "en"
      ),
    allowed_locales: allowed_locales,
    plural_forms: Bonfire.Common.Localise.Gettext.Plural,
    priv: Application.compile_env!(:bonfire_common, :localisation_path),
    split_module_by: [:locale, :domain]

  # end
end

defmodule Bonfire.Common.Localise.Gettext.Helpers do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:


  # Simple translation

      iex> l("Hello")
      "Hello"
      iex> l("Hello %{name}", name: "Bookchin")
      "Hello Bookchin"
      iex> l("Hi", [], "test context")
      "Hi"


  # Plural translation

      iex> lp("Hi friend", "Hi friends", 2)
      "Hi friends"
      iex> lp("Hiya %{user_or_users}", "Hiyas %{user_or_users}", 1, [user_or_users: "Bookchin"], "test context")
      "Hiya Bookchin"

  See the [Gettext Docs](https://hexdocs.pm/gettext) for details.
  """

  # alias the gettext macros for ease-of-use

  use Gettext, backend: Bonfire.Common.Localise.Gettext
  use Untangle

  @doc """
  Translates a string with optional bindings, context, and domain.

  This macro provides translation capabilities based on Gettext. It determines the appropriate domain and context for the translation.

  ## Examples

      iex> l("Hello")
      "Hello"
      iex> l("Hello %{name}", name: "Bookchin")
      "Hello Bookchin"
      iex> l("Hi", [], "test context")
      "Hi"

  ## Parameters
    * `msgid` - The text or message ID to be translated.
    * `bindings` - (Optional) A list or map of bindings to interpolate in the message.
    * `context` - (Optional) A context for the translation.
    * `domain` - (Optional) A domain for the translation.
  """
  defmacro l(original_text_or_id, bindings \\ [], context \\ nil, domain \\ nil)

  defmacro l(msgid, bindings, nil, nil)
           when is_list(bindings) or (is_map(bindings) and is_binary(msgid)) do
    # Calculate domain based on current extension
    domain = extension_name(__CALLER__.module)

    # Generate POT patching code using the domain
    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      case domain do
        otp_app when is_binary(otp_app) ->
          quote do:
                  dgettext(
                    unquote(otp_app),
                    unquote(msgid),
                    unquote(bindings)
                  )

        _ ->
          quote do: gettext(unquote(msgid), unquote(bindings))
      end

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  defmacro l(msgid, bindings, context, nil)
           when (is_binary(context) and is_list(bindings)) or
                  (is_map(bindings) and is_binary(msgid)) do
    # Use the explicitly provided context 

    domain = extension_name(__CALLER__.module)

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      case domain do
        otp_app when is_binary(otp_app) ->
          quote do:
                  dpgettext(
                    unquote(otp_app),
                    unquote(context),
                    unquote(msgid),
                    unquote(bindings)
                  )

        _ ->
          quote do: pgettext(unquote(context), unquote(msgid), unquote(bindings))
      end

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  defmacro l(msgid, bindings, nil, domain)
           when (is_binary(domain) and is_list(bindings)) or
                  (is_map(bindings) and is_binary(msgid)) do
    # Use the explicitly provided domain 

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast = quote do: dgettext(unquote(domain), unquote(msgid), unquote(bindings))

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  defmacro l(msgid, bindings, context, domain)
           when (is_binary(domain) and is_binary(context) and is_list(bindings)) or
                  (is_map(bindings) and is_binary(msgid)) do
    # Use the explicitly provided context and domain 

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      quote do:
              dpgettext(
                unquote(domain),
                unquote(context),
                unquote(msgid),
                unquote(bindings)
              )

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  @doc """
  Translates a plural text with optional bindings, context, and domain.

  This macro provides plural translation capabilities based on Gettext. It determines the appropriate domain and context for the translation.

  ## Examples

      iex> lp("Hi friend", "Hi friends", 2)
      "Hi friends"
      iex> lp("Hiya %{user_or_users}", "Hiyas %{user_or_users}", 1, [user_or_users: "Bookchin"], "test context")
      "Hiya Bookchin"

  ## Parameters
    * `msgid` - The singular message id to be translated.
    * `msgid_plural` - The plural message id to be translated.
    * `n` - The number used to determine singular or plural form.
    * `bindings` - (Optional) A list or map of bindings to interpolate in the message.
    * `context` - (Optional) A context for the translation.
    * `domain` - (Optional) A domain for the translation.
  """
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
    domain = extension_name(__CALLER__.module)

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      case domain do
        otp_app when is_binary(otp_app) ->
          quote do:
                  dngettext(
                    unquote(otp_app),
                    unquote(msgid),
                    unquote(msgid_plural),
                    unquote(n),
                    unquote(bindings)
                  )

        _ ->
          quote do:
                  ngettext(
                    unquote(msgid),
                    unquote(msgid_plural),
                    unquote(n),
                    unquote(bindings)
                  )
      end

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  defmacro lp(msgid, msgid_plural, n, bindings, context, nil)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or
                  (is_map(bindings) and is_binary(context)) do
    # Use the explicitly provided context 

    domain = extension_name(__CALLER__.module)

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      case domain do
        otp_app when is_binary(otp_app) ->
          quote do:
                  dpngettext(
                    unquote(otp_app),
                    unquote(context),
                    unquote(msgid),
                    unquote(msgid_plural),
                    unquote(n),
                    unquote(bindings)
                  )

        _ ->
          quote do:
                  pngettext(
                    unquote(context),
                    unquote(msgid),
                    unquote(msgid_plural),
                    unquote(n),
                    unquote(bindings)
                  )
      end

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  defmacro lp(msgid, msgid_plural, n, bindings, nil, domain)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or
                  (is_map(bindings) and is_binary(domain)) do
    # Use the explicitly provided domain 

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      quote do:
              dngettext(
                unquote(domain),
                unquote(msgid),
                unquote(msgid_plural),
                unquote(n),
                unquote(bindings)
              )

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  defmacro lp(msgid, msgid_plural, n, bindings, context, domain)
           when (is_binary(msgid) and is_binary(msgid_plural) and not is_nil(n) and
                   is_list(bindings)) or
                  (is_map(bindings) and is_binary(context) and is_binary(domain)) do
    # Use the explicitly provided context and domain 

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    translation_ast =
      quote do:
              dpngettext(
                unquote(domain),
                unquote(context),
                unquote(msgid),
                unquote(msgid_plural),
                unquote(n),
                unquote(bindings)
              )

    quote do
      unquote(pot_patch_ast)
      unquote(translation_ast)
    end
  end

  @doc """
  Dynamically localises a text. This function is useful for localising strings only known at runtime (when you can't use the `l` or `lp` macros).

  ## Examples

      iex> localise_dynamic("some_message_id")
      "some_message_id"
      iex> localise_dynamic("some_message_id", MyApp.MyModule)
      "some_message_id"

  ## Parameters
    * `msgid` - The message id to be localized.
    * `caller_module` - (Optional) The module from which the call originates.
  """
  # @decorate time()
  def localise_dynamic(msgid, module \\ nil)

  def localise_dynamic(msgid, module) when is_binary(msgid) do
    otp_app = extension_name(module) || :bonfire

    Gettext.dgettext(
      Bonfire.Common.Localise.Gettext,
      otp_app,
      msgid
    )
  end

  def localise_dynamic(msgid, _module), do: msgid

  @doc """
  Localizes a list of strings at compile time.

  This macro evaluates the list of strings and localizes each string based on the domain derived from the caller module. This is useful if you want to provide a list of strings at compile time that will later be used at runtime by `localise_dynamic/2`.

  ## Examples

      iex> localise_strings(["hello", "world"])
      ["hello", "world"]
      iex> localise_strings(["hello", "world"], MyApp.MyModule)
      ["hello", "world"]

  ## Parameters
    * `strings` - A list of strings to be localized.
    * `caller_module` - (Optional) The module from which the call originates.
  """

  defmacro localise_strings(strings, caller_module \\ nil) do
    {strings, _} = Code.eval_quoted(strings)
    {caller_module, _} = Code.eval_quoted(caller_module)
    domain = extension_name(caller_module || __CALLER__.module)

    for msg <- strings do
      quote do
        # l unquote(msg)
        dgettext(unquote(domain), unquote(msg), [])
      end
    end
  end

  defp extension_name(nil), do: :bonfire

  defp extension_name(module_or_app) when is_atom(module_or_app) do
    case Application.get_application(module_or_app) do
      # ^ can't use cached result at compile time
      otp_app when is_atom(otp_app) and not is_nil(otp_app) ->
        to_string(otp_app)

      _not_a_known_module ->
        case Application.spec(module_or_app) do
          nil ->
            mix =
              if Code.ensure_loaded?(Mix.Project),
                do: Mix.Project.get()

            if mix, do: to_string(mix.project()[:app])

          _known_app_spec ->
            to_string(module_or_app)
        end
    end
  end
end
