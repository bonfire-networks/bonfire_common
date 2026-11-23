defmodule Bonfire.Common.ConfigPutStringKeysTest do
  @moduledoc "`Config.put` into a level that has string keys, as instance settings can when they're loaded or saved with a key whose atom doesn't exist yet (eg. a custom widget's id)."
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  alias Bonfire.Common.Config
  # `Config.get/3` is a macro
  require Config

  @otp_app :bonfire_common
  @key __MODULE__.TestKey

  setup do
    original = Application.get_env(@otp_app, @key)

    on_exit(fn ->
      if original,
        do: Application.put_env(@otp_app, @key, original),
        else: Application.delete_env(@otp_app, @key)
    end)

    :ok
  end

  test "a level stored with a string key takes a new value, and the key becomes its atom" do
    # `:custom_text` exists (it's written here), so the stored string is that key
    Application.put_env(@otp_app, @key, include: %{"custom_text" => true})

    Config.put([@key, :include, :other], false, @otp_app)

    assert Config.get([@key, :include, :custom_text], nil, @otp_app) == true
    assert Config.get([@key, :include, :other], nil, @otp_app) == false
  end

  test "a string key with no atom of that name is kept as it is" do
    unknown = "no_atom_" <> Integer.to_string(System.unique_integer([:positive]))
    Application.put_env(@otp_app, @key, include: %{unknown => true})

    Config.put([@key, :include, :other], false, @otp_app)

    include = Application.get_env(@otp_app, @key)[:include]
    assert Enum.find_value(include, fn {k, v} -> k == unknown && v end) == true
    assert Config.get([@key, :include, :other], nil, @otp_app) == false
  end
end
