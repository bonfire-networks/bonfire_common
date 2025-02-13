defmodule Bonfire.Common.Testing.InsecurePW do
  # use Comeonin

  @impl true
  def hash_pwd_salt(password, _opts \\ []) do
    password
  end

  @impl true
  def verify_pass(_password, _stored_hash) do
    true
  end

  def no_user_verify, do: nil
end
