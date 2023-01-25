defmodule Bonfire.Common.Media do
  def media_url(%{media_type: "remote", path: url} = _media) do
    url
  end

  def media_url(%{path: "http" <> _ = url} = _media) do
    url
  end

  def media_url(%{media_type: media_type} = media) do
    if String.starts_with?(media_type, "image") do
      image_url(media)
    else
      Bonfire.Files.DocumentUploader.remote_url(media)
    end
  end

  def avatar_url(%{profile: %{icon: _} = profile}), do: avatar_url(profile)
  def avatar_url(%{icon: %{url: url}}) when is_binary(url), do: url

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
  def avatar_url(%{id: id, shared_user: %{id: _}} = obj),
    do: "https://picsum.photos/seed/#{id}/128/128?blur"

  # def avatar_url(%{id: id, shared_user: _} = user), do: repo().maybe_preload(user, :shared_user) |> avatar_url() # TODO: make sure this is preloaded in user queries when we need it
  # def avatar_url(obj), do: image_url(obj)
  def avatar_url(%{id: id}) when is_binary(id), do: avatar_fallback(id)
  def avatar_url(obj), do: avatar_fallback(Bonfire.Common.Types.ulid(obj))

  def avatar_fallback(_ \\ nil), do: "/images/avatar.png"

  # def avatar_fallback(id \\ nil), do: Bonfire.Me.Fake.Helpers.avatar_url(id) # robohash

  def image_url(url) when is_binary(url), do: url
  def image_url(%{profile: %{image: _} = profile}), do: image_url(profile)
  def image_url(%{image: %{url: url}}) when is_binary(url), do: url

  def image_url(%{image: %{id: _} = media}),
    do: Bonfire.Files.ImageUploader.remote_url(media)

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

  def banner_url(%{profile: %{image: _} = profile}), do: banner_url(profile)
  def banner_url(%{image: %{url: url}}) when is_binary(url), do: url

  def banner_url(%{image: %{id: _} = media}),
    do: Bonfire.Files.BannerUploader.remote_url(media)

  def banner_url(%{path: _} = media),
    do: Bonfire.Files.BannerUploader.remote_url(media)

  def banner_url(%{image_id: image_id}) when is_binary(image_id),
    do: Bonfire.Files.BannerUploader.remote_url(image_id)

  def banner_url(%{image: url}) when is_binary(url), do: url
  def banner_url(%{profile: profile}), do: banner_url(profile)
  def banner_url(_obj), do: "/images/bonfires.png"
end
