defmodule Bonfire.Common.Localise.Gettext.Coverage do
  @moduledoc """
  How much of each language is translated, read from the `coverage.json` that `mix bonfire.localise_coverage` writes next to the catalogues.

  The file's shape, how it is read and how a share is added up are in `Mix.Tasks.Bonfire.LocaliseCoverage`, which writes it and cannot depend on Bonfire. This module adds the caching, the choice of path and of the domains to count.
  """
  # `Config.get/1,2` are macros
  use Bonfire.Common.Config
  use Bonfire.Common.Localise
  alias Mix.Tasks.Bonfire.LocaliseCoverage, as: CoverageFile

  @doc """
  The share (a float from 0 to 1) of strings a user sees translated in `locale`.

  It adds the counts of the domains of the apps the running flavour has loaded, so extensions from other flavours do not skew it. A regional locale's counts already include what falls back from its base language.

  Returns `nil` for English and its variants, the language the msgids are written in, which is complete by definition (not the instance's default locale: an instance defaulting to `fr` still shows `fr`'s real share), and when there is no coverage file. A locale missing from the file, with no catalogue, is `0`.

  The file is read once and kept in `:persistent_term`, as it only changes when translations are pulled.

  Options: `:path` of the file (default: the app's `priv/localisation/coverage.json`) and `:apps`, the app names to count (default: `Application.loaded_applications/0`).
  """
  def translated_share(locale, opts \\ []) do
    locale = locale |> to_string() |> String.replace("-", "_")

    if Bonfire.Common.Localise.Gettext.Fallback.language(locale) == "en" do
      nil
    else
      path = Keyword.get_lazy(opts, :path, &coverage_path/0)

      apps =
        opts
        |> Keyword.get_lazy(:apps, fn ->
          Enum.map(Application.loaded_applications(), &elem(&1, 0))
        end)
        |> Enum.map(&to_string/1)

      case coverage(path) do
        nil ->
          nil

        coverage ->
          CoverageFile.share(
            coverage,
            locale,
            Enum.filter(CoverageFile.domains(coverage), &(&1 in apps))
          )
      end
    end
  end

  @doc """
  The words the language pickers show after a language's name about how much of it is translated, or `nil` when there is nothing to say (English, or no coverage file, see `translated_share/2`). Takes the same options.

  `"not translated yet"` at 0, `"<10% translated"` below 10%, `"fully translated"` at 100%, else `"N% translated"` with N the share rounded to the nearest 10 and at most 90, so a language that is not fully translated never shows 100.
  """
  def translated_label(locale, opts \\ []) do
    case translated_share(locale, opts) do
      nil -> nil
      share when share <= 0 -> l("not translated yet")
      share when share < 0.1 -> l("<10% translated")
      share when share >= 1 -> l("fully translated")
      share -> l("%{percent}% translated", percent: min(round(share * 10) * 10, 90))
    end
  end

  # the setting lets a test point the pickers at a fixture file
  defp coverage_path do
    case Bonfire.Common.Config.get([Bonfire.Common.Localise, :coverage_path]) do
      path when is_binary(path) ->
        path

      _ ->
        case :code.priv_dir(:bonfire) do
          {:error, _} ->
            Path.join(
              Bonfire.Common.Config.get(:localisation_path, "priv/localisation"),
              "coverage.json"
            )

          dir ->
            Path.join([to_string(dir), "localisation", "coverage.json"])
        end
    end
  end

  defp coverage(path) do
    key = {__MODULE__, :coverage, path}

    case :persistent_term.get(key, :unread) do
      :unread ->
        coverage =
          case CoverageFile.read(path) do
            {:ok, coverage} -> coverage
            :error -> nil
          end

        # a missing file is cached too, so a flavour without the file does not hit the disk on every render
        :persistent_term.put(key, coverage)
        coverage

      coverage ->
        coverage
    end
  end
end
