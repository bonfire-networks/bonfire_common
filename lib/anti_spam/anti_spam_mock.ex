defmodule Bonfire.Common.AntiSpam.Mock do
  @moduledoc """
  Mock for Anti-spam Provider implementations.

  Credit to https://joinmobilizon.org for the original code.
  """

  alias Bonfire.Common.AntiSpam.Provider

  @behaviour Provider

  @impl Provider
  def ready?, do: true

  @impl Provider
  def check_current_user(_context), do: :ham

  @impl Provider
  def check_profile("spam", _context), do: :spam
  def check_profile(_text, _context), do: :ham

  @impl Provider
  def check_object("some spam object", _context), do: :spam
  def check_object(_event_body, _context), do: :ham

  @impl Provider
  def check_comment("some spam text", _is_reply?, _context), do: :spam
  def check_comment(_comment_body, _is_reply?, _context), do: :ham
end
