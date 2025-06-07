defmodule Bonfire.Common.Media do
  @moduledoc "Helpers for handling images and other media"

  use Arrows
  import Untangle
  use Bonfire.Common.E
  use Bonfire.Common.Localise
  use Bonfire.Common.Config
  alias Common.Utils
  alias Common.Enums
  alias Common.Cache

  @external ["link", "remote", "website", "article", "book", "profile", "url", "URL"]

  @doc """
  Takes a Media map (or an object containing one) and returns a URL for the media.

  ## Examples

      iex> media_url(%{path: "http://example.com/image.jpg"})
      "http://example.com/image.jpg"

      iex> media_url(%{path: "remote.jpg", metadata: %{"module" => "MyModule"}})
      # Assume MyModule.remote_url/1 is defined and returns "http://example.com/remote.jpg"
      "http://example.com/remote.jpg"

      iex> media_url(%{media_type: "image/jpeg", path: "image.jpg"})
      "http://image.jpg"

      iex> media_url(%{media_type: "text/plain", path: "document.txt"})
      "http://document.txt"

      iex> media_url(%{changes: %{path: "http://changed.example.com/image.jpg"}})
      "http://changed.example.com/image.jpg"

      iex> media_url(%{path: "image.jpg"})
      "http://image.jpg"

      iex> media_url(%{media: %{path: "http://nested.example.com/image.jpg"}})
      "http://nested.example.com/image.jpg"

      iex> media_url(%{nonexistent_key: "value"})
      nil
  """

  def media_url(%{metadata: %{"module" => module}} = media) do
    case Common.Types.maybe_to_module(module) do
      nil -> Map.drop(media, [:metadata]) |> media_url()
      module -> Utils.maybe_apply(module, :remote_url, media, fallback_return: nil)
    end
  end

  def media_url(%{metadata: %{module: module}} = media) when is_atom(module) do
    # || Map.drop(media, [:metadata]) |> media_url()
    Utils.maybe_apply(module, :remote_url, media, fallback_return: nil)
  end

  def media_url(%{path: "http" <> _ = url} = _media) do
    url
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

      e(media, :metadata, :canonical_url, nil) ||
        Utils.maybe_apply(Bonfire.Files.DocumentUploader, :remote_url, [media],
          fallback_return: nil
        )
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

  @doc """
  Takes a Media map (or an object containing one) and returns the thumbnail's URL.

  ## Examples

      iex> thumbnail_url(%{path: "thumbnail.jpg", metadata: %{"module" => "MyModule"}})
      # Assume MyModule.remote_url/2 with :thumbnail returns "http://example.com/thumbnail.jpg"
      "http://example.com/thumbnail.jpg"

      iex> thumbnail_url(%{media_type: "image/jpeg", path: "thumbnail.jpg"})
      "http://thumbnail.jpg"

      iex> thumbnail_url(%{media_type: "video/mp4", path: "video.mpeg"})
      # Assume Bonfire.Files.VideoUploader.remote_url/2 with :thumbnail returns "http://video-thumbnail.jpg"
      "http://video-thumbnail.jpg"

      iex> thumbnail_url(%{path: "document.pdf", media_type: "document"})
      # Assume Bonfire.Files.DocumentUploader.remote_url/2 with :thumbnail returns "http://document-thumbnail.jpg"
      "http://document-thumbnail.jpg"

      iex> thumbnail_url(%{nonexistent_key: "value"})
      nil
  """
  def thumbnail_url(%{metadata: %{"module" => module}} = media) do
    case Common.Types.maybe_to_module(module) do
      nil ->
        Map.drop(media, [:metadata]) |> image_url() |> debug("imggg1")

      module when is_atom(module) or is_binary(module) ->
        Utils.maybe_apply(module, :remote_url, [media, :thumbnail], fallback_return: nil)

      _ ->
        nil
    end
    |> debug("t1")
  end

  def thumbnail_url(%{media_type: media_type} = media) do
    cond do
      String.starts_with?(media_type || "", "image") ->
        image_url(media) |> debug("imggg2")

      String.starts_with?(media_type || "", "video") ->
        Utils.maybe_apply(Bonfire.Files.VideoUploader, :remote_url, [media, :thumbnail],
          fallback_return: nil
        )

      true ->
        Utils.maybe_apply(Bonfire.Files.DocumentUploader, :remote_url, [media, :thumbnail],
          fallback_return: nil
        )
    end
    |> debug("t2")
  end

  def thumbnail_url(_) do
    nil
  end

  @doc """
  Takes a Media map (or an object containing one) and returns the avatar's URL.

  ## Examples

      iex> avatar_url(%{profile: %{icon: %{url: "http://example.com/avatar.png"}}})
      "http://example.com/avatar.png"

      iex> avatar_url(%{icon: %{path: "http://example.com/path.png"}})
      "http://example.com/path.png"

      iex> avatar_url(%{icon_id: "icon123"})
      # Assume Bonfire.Files.IconUploader.remote_url/1 returns "http://example.com/icon123.png"
      "http://example.com/icon123.png"

      iex> avatar_url(%{path: "image.jpg"})
      # Assume Bonfire.Files.IconUploader.remote_url/1 returns "http://example.com/image.jpg"
      "http://example.com/image.jpg"

      iex> avatar_url(%{icon: "http://example.com/icon.png"})
      "http://example.com/icon.png"

      iex> avatar_url(%{image: "http://example.com/image.png"})
      "http://example.com/image.png"

      iex> avatar_url(%{id: "user123", shared_user: nil})
      # Assume avatar_fallback/1 returns "/images/avatar.png"
      "/images/avatar.png"

      iex> avatar_url(%{id: "user456", shared_user: %{id: "shared123"}})
      "https://picsum.photos/seed/user456/128/128?blur"

      iex> avatar_url(%{id: "user789"})
      # Assume avatar_fallback/1 returns "/images/avatar.png"
      "/images/avatar.png"
  """
  def avatar_url(%{profile: %{icon: _} = profile}), do: avatar_url(profile)
  def avatar_url(%{icon: %{url: url}}) when is_binary(url), do: url
  def avatar_url(%{icon: %{path: "http" <> _ = url}}), do: url

  def avatar_url(%{icon: %{id: _} = media}),
    do: Utils.maybe_apply(Bonfire.Files.IconUploader, :remote_url, [media], fallback_return: nil)

  def avatar_url(%{icon_id: icon_id}) when is_binary(icon_id),
    do:
      Utils.maybe_apply(Bonfire.Files.IconUploader, :remote_url, [icon_id], fallback_return: nil)

  def avatar_url(%{path: _} = media),
    do: Utils.maybe_apply(Bonfire.Files.IconUploader, :remote_url, [media], fallback_return: nil)

  def avatar_url(%{file: _} = media),
    do: Utils.maybe_apply(Bonfire.Files.IconUploader, :remote_url, [media], fallback_return: nil)

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

  def avatar_url(obj) do
    debug(obj, "no avatar found")
    avatar_fallback(Bonfire.Common.Enums.id(obj))
  end

  def avatar_fallback(_ \\ nil),
    do:
      Config.get([:ui, :default_images, :avatar], "/images/avatar.png",
        name: l("Default avatar image")
      )

  # def avatar_fallback(id \\ nil), do: Bonfire.Me.Fake.Helpers.avatar_url(id) # robohash

  def image_url(url) when is_binary(url), do: url

  def image_url(%{media_type: media_type} = _media) when media_type in @external do
    nil
  end

  @doc """
  Takes a Media map (or an object containing one) and returns the image's URL.

  ## Examples

      iex> image_url("http://example.com/image.png")
      "http://example.com/image.png"

      iex> image_url(%{media_type: "text/plain"})
      nil

      iex> image_url(%{profile: %{image: %{url: "http://example.com/image.png"}}})
      "http://example.com/image.png"

      iex> image_url(%{image: %{url: "http://example.com/image.png"}})
      "http://example.com/image.png"

      iex> image_url(%{icon: %{path: "http://example.com/image.png"}})
      "http://example.com/image.png"

      iex> image_url(%{path: "http://example.com/image.png"})
      "http://example.com/image.png"

      iex> image_url(%{image_id: "image123"})
      # Assume Bonfire.Files.ImageUploader.remote_url/1 returns "http://example.com/image123.png"
      "http://example.com/image123.png"

      iex> image_url(%{image: "http://example.com/image.png"})
      "http://example.com/image.png"

      iex> image_url(%{profile: %{image: "http://example.com/profile_image.png"}})
      "http://example.com/profile_image.png"

      iex> image_url(%{nonexistent_key: "value"})
      nil
  """
  def image_url(%{profile: %{image: _} = profile}), do: image_url(profile)
  def image_url(%{image: %{url: url}}) when is_binary(url), do: url

  def image_url(%{icon: %{path: "http" <> _ = url}}) do
    if String.ends_with?(url, [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def image_url(%{image: %{id: _} = media}),
    do: Utils.maybe_apply(Bonfire.Files.ImageUploader, :remote_url, [media], fallback_return: nil)

  def image_url(%{path: "http" <> _ = url} = _media) do
    if String.ends_with?(url || "", [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def image_url(%{path: _} = media) do
    url =
      Utils.maybe_apply(Bonfire.Files.ImageUploader, :remote_url, [media], fallback_return: nil)

    if String.ends_with?(url || "", [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def image_url(%{image_id: image_id}) when is_binary(image_id),
    do:
      Utils.maybe_apply(Bonfire.Files.ImageUploader, :remote_url, [image_id],
        fallback_return: nil
      )

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

  @doc """
  Takes a Media map (or an object containing one) and returns the banner's URL.

  ## Examples

      iex> banner_url(%{profile: %{image: %{id: "banner123"}}})
      # Assume Bonfire.Files.BannerUploader.remote_url/1 returns "http://example.com/banner123.png"
      "http://example.com/banner123.png"

      iex> banner_url(%{image: %{url: "http://example.com/banner.png"}})
      "http://example.com/banner.png"

      iex> banner_url(%{image: %{path: "http://example.com/banner.png"}})
      "http://example.com/banner.png"

      iex> banner_url(%{path: "http://example.com/banner.png"})
      "http://example.com/banner.png"

      iex> banner_url(%{image_id: "banner456"})
      # Assume Bonfire.Files.BannerUploader.remote_url/1 returns "http://example.com/banner456.png"
      "http://example.com/banner456.png"

      iex> banner_url(%{image: "http://example.com/banner.png"})
      "http://example.com/banner.png"

      iex> banner_url(%{profile: %{image: %{id: "banner789"}}})
      # Assume Bonfire.Files.BannerUploader.remote_url/1 returns "http://example.com/banner789.png"
      "http://example.com/banner789.png"

      iex> banner_url(%{nonexistent_key: "value"})
      # Assume banner_fallback/0 returns "/images/bonfires.png"
      "/images/bonfires.png"
  """
  def banner_url(%{profile: %{image: %{id: _} = media} = _profile}), do: banner_url(media)
  def banner_url(%{image: %{url: url}}) when is_binary(url), do: url

  def banner_url(%{image: %{path: "http" <> _ = url}}) do
    if String.ends_with?(url, [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def banner_url(%{path: "http" <> _ = url} = _media) do
    if String.ends_with?(url, [".gif", ".jpg", ".jpeg", ".png"]), do: url, else: nil
  end

  def banner_url(%{image: %{id: _} = media}),
    do:
      Utils.maybe_apply(Bonfire.Files.BannerUploader, :remote_url, [media], fallback_return: nil)

  def banner_url(%{path: path} = media) when is_binary(path),
    do:
      Utils.maybe_apply(Bonfire.Files.BannerUploader, :remote_url, [media], fallback_return: nil)

  def banner_url(%{image_id: image_id}) when is_binary(image_id),
    do:
      Utils.maybe_apply(Bonfire.Files.BannerUploader, :remote_url, [image_id],
        fallback_return: nil
      )

  def banner_url(%{image: url}) when is_binary(url), do: url
  def banner_url(%{profile: profile}), do: banner_url(profile)
  def banner_url(_obj), do: banner_fallback()

  def banner_fallback,
    do:
      Config.get([:ui, :default_images, :banner], "/images/bonfires.png",
        name: l("Default banner image")
      )

  def emoji_url(media),
    do: Utils.maybe_apply(Bonfire.Files.EmojiUploader, :remote_url, [media], fallback_return: nil)

  @doc """
  Determines the dominant color for a given user’s avatar or banner.

  ## Examples

      iex> maybe_dominant_color(%{profile: %{icon: "http://example.com/avatar.png"}})
      "#AA4203" # Example dominant color

      iex> maybe_dominant_color(%{profile: %{icon: "http://example.com/avatar.png"}}, nil, "http://example.com/banner.png")
      "#AA4203" # Example dominant color

      iex> maybe_dominant_color(%{profile: %{icon: "http://example.com/avatar.png"}}, nil, nil, "/images/bonfires.png")
      "#AA4203" # Example dominant color

      iex> maybe_dominant_color(%{profile: %{icon: nil}}, "http://example.com/banner.png")
      nil
  """
  def maybe_dominant_color(user, avatar_url \\ nil, banner_url \\ nil, banner_fallback \\ nil) do
    avatar_url = avatar_url || avatar_url(user)
    banner_url = banner_url || banner_url(user)

    !banner_url or
      (banner_url == (banner_fallback || banner_fallback()) and
         case avatar_url do
           "http" <> _ ->
             # "#AA4203"
             nil

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

  ## Examples

      > extract_tar("path/to/archive.tar.gz")
      %{"file1.txt" => <<...>> , "file2.txt" => <<...>>}

      > extract_tar("path/to/archive.tar", [:memory])
      %{"file1.txt" => <<...>> , "file2.txt" => <<...>>}

      > extract_tar("path/to/archive.tar", [:compressed, :memory])
      %{"file1.txt" => <<...>> , "file2.txt" => <<...>>}
  """
  def extract_tar(archive, opts \\ [:compressed, :memory]) do
    with {:ok, files} <- :erl_tar.extract(archive, opts) do
      files
      |> Enum.map(fn {filename, content} -> {to_string(filename), content} end)
      |> Map.new()
    end
  end

  @doc """
  Reads specific files from a tar archive and returns their contents.

  ## Examples

      iex> read_tar_files("path/to/archive.tar", "file1.txt")
      {:ok, "file1 contents"}

      iex> read_tar_files("path/to/archive.tar", ["file1.txt", "file2.txt"])
      {:ok, ["file1 contents", "file2 contents"]}

      iex> read_tar_files("path/to/nonexistent.tar", "file1.txt")
      {:error, "File not found"}

      iex> read_tar_files("path/to/archive.tar", "nonexistent_file.txt")
      {:error, "File not found"}

  """
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
