defmodule Bonfire.Common.QRCode do
  @moduledoc "Renders text (usually a link) as a QR code, for a phone to scan: the two-factor setup secret, and anything else handed out in person."

  @doc """
  The QR code for `text` as an SVG string, `width` pixels wide (264 unless set), or nil when `eqrcode` (an optional dependency) isn't available.

      iex> Bonfire.Common.QRCode.svg("https://example.local") =~ "<svg"
      true
  """
  def svg(text, opts \\ []) when is_binary(text) do
    if Code.ensure_loaded?(EQRCode) do
      text
      |> EQRCode.encode()
      |> EQRCode.svg(width: opts[:width] || 264)
    end
  end
end
