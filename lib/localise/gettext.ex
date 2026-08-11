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

  yes? = ~w(true yes 1)
  no? = ~w(false no none 0)

  compile_all_locales? =
    (System.get_env("COMPILE_ALL_LOCALES") not in no? and Bonfire.Common.Config.env() == :prod) or
      System.get_env("COMPILE_ALL_LOCALES") in yes?

  # Limit locales in non-prod environments  
  allowed_locales =
    if compile_all_locales? do
      # In prod, allow all locales discovered in priv directory (default behaviour)
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

  ## How a translation is found

  A .po entry is identified by **three** things, all of which must match between where a string is extracted and where it is looked up. Get any of them wrong and there is no error, the string simply renders in English, in every locale.

    * **domain** — one .po file per extension (`bonfire_boundaries.po`, `bonfire_social.po`). Derived from the calling module's OTP app, so `l("Follow")` in a `bonfire_boundaries` module is a *different entry* from `l("Follow")` in a `bonfire_ui_boundaries` one. A lookup only ever searches its own domain.
    * **msgid** — the English source string, byte for byte, including whitespace and punctuation.
    * **msgctxt** — an optional context, see below.

  The domain rule has a practical consequence worth stating plainly: **never localise a string that another extension declares.** Route it through a helper that extension exports (`Bonfire.Boundaries.Verbs.verb_name/1`, `Bonfire.Common.Types.object_type_display/1`), so the domain stays with the owner. Passing `__MODULE__` from the rendering component asks the wrong .po file and silently yields English.

  ## Contexts: `lc/4` vs `l/4`

  Use `lc/4` when the same English word means different things in different places, the classic case being words that are both a noun and a verb ("Post" the button vs "Post" the page). Each context gets its own independently translatable entry.

  Name the **use site, not the part of speech**. A developer can pick a use-site label without grammatical analysis, and it tells the translator what to actually do; `"noun"` tells them nothing, `"object"` carries a real instruction. The vocabulary is kept deliberately small, here it is taken through one verb, "Boost", with French alongside to show what English hides:

    * *(no context)* — a capability name in the boundaries matrix, naming what a permission grants. EN "Boost" / FR "Partager" (infinitive). This is the base sense, so it stays as the bare entry
    * `"object"` — a kind of thing, reading mid-sentence ("report this **post**"); lowercase, takes the language's own noun casing. EN "post" / FR "publication"
    * `"verb: action"` — a control the user activates to do it: a button, menu item or link. EN "Boost" / FR "Partager", "Partagez" or "Partage", depending on house style
    * `"verb: past tense"` — a feed activity line, third-person plural, landing after a name. EN "boosted" / FR "a partagé"

  **English cannot show three distinct verb forms**, as an English imperative *is* the bare form, so the permission name and the control are spelled identically and only past tense differs. That collapse is the reason the context is needed. The point is *not* that a translator must render the two differently: French controls often take the infinitive, so "Partager" may well be right for both. It is that sharing a single .po entry takes the decision away from them, they cannot tell which occurrence names a permission and which asks the reader to do something, and so cannot diverge where a language or a house style calls for it. Past tense carries a sharper trap: a translator seeing a bare "Boosted" cannot tell it follows a name.

  **Only the diverging senses carry a context.** A context disambiguates *within one domain*, and inside `bonfire_boundaries.po` nothing competes with the bare verbs — they simply are the permission list, while the buttons live in other extensions' .po files that a boundaries lookup never opens. So the permission name stays bare, which also keeps its existing translations attached rather than orphaning them, and gives `"verb: action"` and `"verb: past tense"` something to fall back to until they are filled in.

  Note this is also why the labels avoid naming grammatical forms: `"verb: imperative"` would prescribe a form the translator may not want, where `"verb: action"` describes where the string appears and leaves the form to them. `"verb: past tense"` is the deliberate exception: there the form is a requirement rather than a style choice, so stating it is the useful thing to do.

  The `"verb: …"` values are namespaced so refinements of one family sort together for translators. Add a new value only when a concrete collision appears, and only for the sense that diverges, so the composer's **Post** button takes `"verb: action"` while the posts page heading stays as the bare entry.

  A context is for *disambiguation*. When instead you need to tell a translator something they cannot infer (a length limit, what a `%{binding}` will contain, where on screen it lands), use `gettext_comment/1`, which attaches a `#.` note to the next extracted message.

  ## Runtime-only strings

  `localise_dynamic/3` handles strings not known until runtime (object type names, activity verbs). Because there is no `l(...)` call for `mix gettext.extract` to find, these must *also* be enumerated at compile time and handed to `localise_strings/3`, see `Bonfire.Common.Localise.localise_object_type_names/0`. The two sides must agree on domain *and* context, or the lookup misses.

  ## Do not concatenate

  `l("Welcome to ") <> name` freezes English word order and punctuation for every locale, and languages differ on both (French puts a space before `:`; many invert adjective/noun order). Use one interpolated msgid instead: `l("Welcome to %{name}", name: name)`, so the translator controls the whole string. Appending a purely dynamic value that carries no translatable text (an error reason, an ID) after a complete sentence is fine.
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
  Localises a string under a gettext context (`msgctxt`), so that the same English word can carry a different translation per use site.

  Takes the context first, which avoids `l/3`'s awkward empty-bindings call (`l("Post", [], "verb")`).

  See the module docs for when to reach for a context and which value to use as the vocabulary is defined there, worked through one verb in English and French.

  Only the contextual msgid is registered for extraction, so translators see one unit per string rather than two. At runtime the lookup falls back to the context-less entry, see `translate_with_context/4`, including why that fallback is meant to be temporary.

  The context string must be byte-identical between here and any other reference to the same entry; a mismatch is silent, degrading to the context-less translation.

  The gettext domain defaults to the calling module's extension, and can be overridden with the fourth argument. Domains are as strict as contexts, a lookup in one never sees a msgid extracted into another so an override is needed whenever a string is declared by a *different* extension than the one rendering it. Prefer a helper exported by the declaring extension, which keeps the domain with its owner rather than restating it at each call site.

  ## Examples

      iex> lc("verb: action", "Post")
      "Post"
      iex> lc("verb: action", "Follow %{name}", name: "Bookchin")
      "Follow Bookchin"
  """
  defmacro lc(context, msgid, bindings \\ [], domain \\ nil)

  defmacro lc(context, msgid, bindings, domain) when is_binary(context) and is_binary(msgid) do
    # an explicit domain is the escape hatch for looking up a string another extension declares;
    # prefer a helper exported by that extension, since it keeps the domain with its owner
    domain = if is_binary(domain), do: domain, else: extension_name(__CALLER__.module)

    pot_patch_ast =
      Bonfire.Common.Localise.POAnnotator.maybe_patch_pot_with_url_ast(
        msgid,
        domain,
        __CALLER__.file,
        __CALLER__.line
      )

    quote do
      require Gettext.Macros
      unquote(pot_patch_ast)

      # registers ONLY the contextual msgid for extraction (no runtime cost), so the .po carries
      # one unit per string rather than a bare/contextual pair
      _ =
        Gettext.Macros.dpgettext_noop_with_backend(
          Bonfire.Common.Localise.Gettext,
          unquote(domain),
          unquote(context),
          unquote(msgid)
        )

      Bonfire.Common.Localise.Gettext.Helpers.translate_with_context(
        unquote(domain),
        unquote(context),
        unquote(msgid),
        unquote(bindings)
      )
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
  def localise_dynamic(msgid, module \\ nil, context \\ nil)

  def localise_dynamic(msgid, module, nil) when is_binary(msgid) do
    otp_app = extension_name(module) || "bonfire"

    Gettext.dgettext(
      Bonfire.Common.Localise.Gettext,
      otp_app,
      msgid
    )
  end

  def localise_dynamic(msgid, module, context) when is_binary(msgid) and is_binary(context) do
    translate_with_context(extension_name(module) || "bonfire", context, msgid)
  end

  def localise_dynamic(msgid, _module, _context), do: msgid

  @doc """
  Looks a msgid up under `context` first, falling back to the context-less entry in the same domain, and finally to the msgid itself.

  This is what makes a context safe to add to an already-translated string: the contextual entry starts out untranslated in every locale, and until a translator fills it in the existing context-less translation keeps rendering. Only `Gettext.Backend.lgettext/5` can distinguish those cases — `Gettext.dpgettext/5` always returns a binary (the msgid on a miss), so a `dpgettext(...) || dpgettext(...)` form can never fall through.

  Note the trade-off this buys: where the context-less entry carries the *wrong* sense for this call site, the fallback renders that wrong sense rather than English. Filling in the contextual entry is what resolves it.

  > #### Intended to be temporary {: .warning}
  >
  > This fallback exists to carry existing translations across the introduction of contexts. Once the contextual entries are translated across the locales we ship, it is dead weight — and worse, it is the only thing that can silently render a wrong-sense translation. Remove it (and this function, folding callers back onto plain `dpgettext`) once that migration has landed.
  """
  def translate_with_context(domain, context, msgid, bindings \\ %{})

  def translate_with_context(domain, context, msgid, bindings) when is_list(bindings),
    do: translate_with_context(domain, context, msgid, Map.new(bindings))

  def translate_with_context(domain, context, msgid, bindings)
      when is_binary(msgid) and is_binary(context) and is_map(bindings) do
    backend = Bonfire.Common.Localise.Gettext
    domain = to_string(domain)

    case backend.lgettext(Gettext.get_locale(backend), domain, context, msgid, bindings) do
      {:ok, translated} -> translated
      # `:default` (no contextual entry) or missing bindings — retry without the context
      _ -> Gettext.dgettext(backend, domain, msgid, bindings)
    end
  end

  # Map/keyword keys whose string values are user-facing by convention, used as the default `keys`
  # for `localise_tree/3`. Pass an explicit `keys` list when a structure has non-display values under
  # any of these names, to avoid sending an identifier through gettext.
  @default_localised_keys [
    :name,
    :label,
    :description,
    :help,
    :tooltip,
    :disabled,
    :page_title,
    :feed_title,
    :feedback_title,
    :feedback_message
  ]

  @doc """
  Recursively re-localises the values of known display-string `keys` within a (possibly deeply
  nested) data structure of maps, keyword lists, and lists, via `localise_dynamic/2` (domain derived
  from `module`). Structs, non-string values, and values under other keys are left untouched.

  This is the single point of translation for user-facing strings sourced from a
  `ConfigModule.config/0`: those are wrapped in `l/1`, but `config/0` is evaluated once at boot under
  the default locale (so the value is effectively the untranslated msgid), and they must be
  re-translated per-request at the point of display — which is what this does.

  Selection is by key name (a fixed default set, overridable via the `keys` arg), which is a
  deliberate convention: it keeps call sites terse, but a binary stored under e.g. a non-display
  `:name` key *would* be sent through gettext. When a structure mixes display and identifier values
  under these names, pass an
  explicit `keys` list scoped to the display fields.

  ## Examples

      iex> localise_tree(%{label: "Hi", icon: "x", opts: [help: "Yo", n: 1]}, nil, [:label, :help])
      %{label: "Hi", icon: "x", opts: [help: "Yo", n: 1]}
  """
  def localise_tree(data, module \\ nil, keys \\ @default_localised_keys, context \\ nil)

  def localise_tree(data, module, keys, context) when is_map(data) and not is_struct(data) do
    Map.new(data, fn {k, v} -> {k, localise_tree_value(k, v, module, keys, context)} end)
  end

  def localise_tree(data, module, keys, context) when is_list(data) do
    Enum.map(data, fn
      {k, v} -> {k, localise_tree_value(k, v, module, keys, context)}
      other -> localise_tree(other, module, keys, context)
    end)
  end

  def localise_tree(data, _module, _keys, _context), do: data

  defp localise_tree_value(key, value, module, keys, context) when is_binary(value) do
    if key in keys, do: localise_dynamic(value, module, context), else: value
  end

  defp localise_tree_value(_key, value, module, keys, context),
    do: localise_tree(value, module, keys, context)

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

  defmacro localise_strings(strings, caller_module \\ nil, context \\ nil) do
    {strings, _} = Code.eval_quoted(strings)
    {caller_module, _} = Code.eval_quoted(caller_module)
    {context, _} = Code.eval_quoted(context)
    domain = extension_name(caller_module || __CALLER__.module)

    for msg <- strings do
      if is_binary(context) do
        quote do
          require Gettext.Macros

          _ =
            Gettext.Macros.dpgettext_noop_with_backend(
              Bonfire.Common.Localise.Gettext,
              unquote(domain),
              unquote(context),
              unquote(msg)
            )
        end
      else
        quote do
          # l unquote(msg)
          dgettext(unquote(domain), unquote(msg), [])
        end
      end
    end
  end

  @doc """
  Registers a translator comment (a `#.` line in the .po) for the next message extracted in this module.

  Re-exported from `Gettext.Macros`: it is imported *into* this module by `use Gettext`, but not re-exported to modules that only `import Bonfire.Common.Localise.Gettext.Helpers`, which is most of them.

  Reach for this instead of a context when the ambiguity is not about *which* entry a string is, but about what a translator needs to know to translate it well — length constraints, what the `%{}` bindings will contain, or where on screen it lands.

      gettext_comment("Shown in a 200px-wide sidebar; keep under 20 characters")
      l("Recent activity")
  """
  defmacro gettext_comment(comment) do
    quote do
      require Gettext.Macros
      Gettext.Macros.gettext_comment(unquote(comment))
    end
  end

  # a gettext domain must be `:default` or a binary (see `Gettext.dpgettext/5`'s `is_domain/1`
  # guard), so this returns a string like the clauses below — returning the `:bonfire` atom raised
  # a FunctionClauseError for every `localise_dynamic/2` call without a module
  defp extension_name(nil), do: "bonfire"

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
