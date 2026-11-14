defmodule Bonfire.Common.QRCodeTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  alias Bonfire.Common.QRCode

  test "renders a link as an SVG QR code, 264 pixels wide unless told otherwise" do
    svg = QRCode.svg("https://example.local/signup/invitation/x")

    assert svg =~ ~r/^<\?xml.*<svg|^<svg/s
    # eqrcode writes the width as a float
    assert svg =~ ~s(<svg width="264.0")
    assert QRCode.svg("https://example.local/x", width: 100) =~ ~s(<svg width="100.0")
  end
end
