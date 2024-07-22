defmodule Bonfire.Common.Media do
  @moduledoc "Helpers for handling images and other media"

  use Arrows
  import Untangle
  alias Bonfire.Common
  alias Common.Utils
  alias Common.Enums
  alias Common.Config
  alias Common.Cache

  @external ["link", "remote", "website", "article", "book", "profile", "url", "URL"]

  @doc "Takes a Media map (or an object containing one) and returns a URL for the media"
  def media_url(%{path: "http" <> _ = url} = _media) do
    url
  end

  def media_url(%{metadata: %{"module" => module}} = media) do
    case Common.Types.maybe_to_module(module) do
      nil -> Map.drop(media, [:metadata]) |> media_url()
      module -> Utils.maybe_apply(module, :remote_url, media)
    end
  end

  def media_url(%{metadata: %{module: module}} = media) when is_atom(module) do
    # || Map.drop(media, [:metadata]) |> media_url()
    Utils.maybe_apply(module, :remote_url, media)
  end

  def media_url(%{media_type: media_type, path: url} = _media)
      when media_type in @external and is_binary(url) do
    if String.contains?(url || "", "://") do
      url
    else
      "http://#{url}"
    end
  end

  def media_url(%{media_type: media_type} = media) do
    if String.starts_with?(media_type || "", "image") do
      image_url(media)
    else
      debug(media, "non-image url")

      Utils.e(media, :metadata, :canonical_url, nil) ||
        Bonfire.Files.DocumentUploader.remote_url(media)
    end
  end

  def media_url(%{media: media}) do
    media_url(media)
  end

  def media_url(%{changes: changeset_attrs}) do
    media_url(changeset_attrs)
  end

  def media_url(_) do
    nil
  end

  def thumbnail_url(%{metadata: %{"module" => module}} = media) do
    case Common.Types.maybe_to_module(module) do
      nil ->
        Map.drop(media, [:metadata]) |> media_url()

      module when is_atom(module) or is_binary(module) ->
        Utils.maybe_apply(module, :remote_url, [media, :thumbnail], fallback_return: nil)

      _ ->
        nil
    end
  end

  def thumbnail_url(%{media_type: media_type} = media) do
    cond do
      String.starts_with?(media_type || "", "image") ->
        image_url(media)

      String.starts_with?(media_type || "", "video") ->
        Bonfire.Files.VideoUploader.remote_url(media, :thumbnail)

      true ->
        Bonfire.Files.DocumentUploader.remote_url(media, :thumbnail)
    end
  end

  def thumbnail_url(_) do
    nil
  end

  @doc "Takes a Media map (or an object containing one) and returns the avatar's URL."
  def avatar_media(%{profile: %{icon: media}}), do: media
  def avatar_media(%{icon: media}), do: media
  def avatar_media(%{} = maybe_media), do: maybe_media
  def avatar_media(_), do: nil

  def avatar_url(%{profile: %{icon: _} = profile}), do: avatar_url(profile)
  def avatar_url(%{icon: %{url: url}}) when is_binary(url), do: url
  def avatar_url(%{icon: %{path: "http" <> _ = url}}), do: url

  def avatar_url(%{icon: %{id: _} = media}),
    do: Bonfire.Files.IconUploader.remote_url(media)

  def avatar_url(%{icon_id: icon_id}) when is_binary(icon_id),
    do: Bonfire.Files.IconUploader.remote_url(icon_id)

  def avatar_url(%{path: _} = media),
    do: Bonfire.Files.IconUploader.remote_url(media)

  def avatar_url(%{icon: url}) when is_binary(url), do: url
  # handle VF API
  def avatar_url(%{image: url}) when is_binary(url), do: url
  def avatar_url(%{id: id, shared_user: nil}), do: avatar_fallback(id)
  # for Teams/Orgs
  def avatar_url(%{id: id, shared_user: %{id: _}} = _obj),
    do: "https://picsum.photos/seed/#{id}/128/128?blur"

  # def avatar_url(%{id: id, shared_user: _} = user), do: repo().maybe_preload(user, :shared_user) |> avatar_url() # TODO: make sure this is preloaded in user queries when we need it
  # def avatar_url(obj), do: image_url(obj)
  def avatar_url(%{id: id}) when is_binary(id), do: avatar_fallback(id)
  def avatar_url(obj), do: avatar_fallback(Bonfire.Common.Enums.id(obj))

  # TODO: configurable
  def avatar_fallback(_ \\ nil), do: "/images/avatar.png"

  # def avatar_fallback(id \\ nil), do: Bonfire.Me.Fake.Helpers.avatar_url(id) # robohash

  def image_url(url) when is_binary(url), do: url

  def image_url(%{media_type: media_type} = _media) when media_type in @external do
    nil
  end

  @doc "Takes a Media map (or an object containing one) and returns the image's URL."
  def image_url(%{profile: %{image: _} = profile}), do: image_url(profile)
  def image_url(%{image: %{url: url}}) when is_binary(url), do: url

  def image_url(%{icon: %{path: "http" <> _ = url}}) do
    if String.ends_with?(url, [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def image_url(%{image: %{id: _} = media}),
    do: Bonfire.Files.ImageUploader.remote_url(media)

  def image_url(%{path: "http" <> _ = url} = _media) do
    if String.ends_with?(url || "", [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def image_url(%{path: _} = media),
    do: Bonfire.Files.ImageUploader.remote_url(media)

  def image_url(%{image_id: image_id}) when is_binary(image_id),
    do: Bonfire.Files.ImageUploader.remote_url(image_id)

  def image_url(%{image: url}) when is_binary(url), do: url
  def image_url(%{profile: profile}), do: image_url(profile)

  # WIP: https://github.com/bonfire-networks/bonfire-app/issues/151#issuecomment-1060536119

  # def image_url(%{name: name}) when is_binary(name), do: "https://loremflickr.com/600/225/#{name}/all?lock=1"
  # def image_url(%{note: note}) when is_binary(note), do: "https://loremflickr.com/600/225/#{note}/all?lock=1"
  # def image_url(%{id: id}), do: "https://picsum.photos/seed/#{id}/600/225?blur"
  # def image_url(_obj), do: "https://picsum.photos/600/225?blur"

  # If no background image is provided, default to a default one (It can be included in configurations)
  # def image_url(_obj), do: Bonfire.Me.Fake.Helpers.image_url()

  def image_url(_obj), do: nil

  @doc "Takes a Media map (or an object containing one) and returns the banner's URL."
  def banner_url(%{profile: %{image: %{id: _} = media} = _profile}), do: banner_url(media)
  def banner_url(%{image: %{url: url}}) when is_binary(url), do: url

  def banner_url(%{image: %{path: "http" <> _ = url}}) do
    if String.ends_with?(url, [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def banner_url(%{path: "http" <> _ = url} = _media) do
    if String.ends_with?(url, [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def banner_url(%{image: %{id: _} = media}),
    do: Bonfire.Files.BannerUploader.remote_url(media)

  def banner_url(%{path: path} = media) when is_binary(path),
    do: Bonfire.Files.BannerUploader.remote_url(media)

  def banner_url(%{image_id: image_id}) when is_binary(image_id),
    do: Bonfire.Files.BannerUploader.remote_url(image_id)

  def banner_url(%{image: url}) when is_binary(url), do: url
  def banner_url(%{profile: profile}), do: banner_url(profile)
  def banner_url(_obj), do: banner_fallback()

  # TODO: configurable
  def banner_fallback, do: "/images/bonfires.png"

  def maybe_dominant_color(user, avatar_url \\ nil, banner_url \\ nil, banner_fallback \\ nil) do
    avatar_url = avatar_url || avatar_url(user)
    banner_url = banner_url || banner_url(user)

    !banner_url or
      (banner_url == (banner_fallback || banner_fallback()) and
         case avatar_url do
           "http" <> _ ->
             "#AA4203"

           nil ->
             nil

           _ ->
             avatar_url != avatar_fallback(Enums.id(user)) &&
               Cache.maybe_apply_cached({Bonfire.Files.MediaEdit, :dominant_color}, [
                 Path.join(Config.get(:project_path), avatar_url),
                 15,
                 nil
               ])
         end)
  end

  @doc """
  Returns a map containing all files and their contents from a tar or compressed tar.gz archive.
  """
  def extract_tar(archive, opts \\ [:compressed, :memory]) do
    with {:ok, files} <- :erl_tar.extract(archive, opts) do
      files
      |> Enum.map(fn {filename, content} -> {to_string(filename), content} end)
      |> Map.new()
    end
  end

  def read_tar_files(archive, file_or_files, _opts \\ [:compressed, :verbose]) do
    # opts
    # |> Keyword.put_new(:cwd, Path.dirname(archive))
    # |> Keyword.put_new(:files, List.wrap(file_or_files))
    # |> debug("opts")
    # |> extract_tar(archive, ...)
    # the above doesn't seem to work so resort to tar command instead

    case System.cmd("tar", ["-xvf", archive, "-O"] ++ List.wrap(file_or_files)) do
      {contents, 0} when is_binary(contents) ->
        {:ok, String.split(contents, file_or_files)}

      {contents, 0} ->
        # FIXME: seems the filename is being included as line 1 of contents
        {:ok, contents}

      _ ->
        error("File not found")
    end
  end
end
