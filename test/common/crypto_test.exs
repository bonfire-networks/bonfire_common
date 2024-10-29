defmodule Bonfire.Common.Crypto.Test do
  use Bonfire.Common.DataCase, async: true
  alias Bonfire.Common.Crypto

  @valid_password "correct_password"
  @invalid_password "wrong_password"

  def secret_binary do
    if Extend.module_exists?(ActivityPub.Safety.Keys), do: ActivityPub.Safety.Keys.generate_rsa_pem(), else: :crypto.strong_rand_bytes(32)
  end

  
  test "encrypt_with_auth_key returns properly structured result" do
    {:ok, secret_binary} = secret_binary()

    assert {:ok,
            %{
              encrypted: encrypted,
              salt: salt
            }} = Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    assert is_binary(encrypted)
    assert byte_size(salt) == 16
  end

  
  test "decryption succeeds with correct password" do
    {:ok, secret_binary} = secret_binary()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    assert {:ok, decrypted_secret_binary} =
             Crypto.decrypt_with_auth_key(encrypted, @valid_password, salt)

    assert decrypted_secret_binary == secret_binary
  end

  
  test "decryption fails with incorrect password" do
    {:ok, secret_binary} = secret_binary()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    assert {:error, _} = Crypto.decrypt_with_auth_key(encrypted, @invalid_password, salt)
  end

  
  test "decryption fails if ciphertext is modified" do
    {:ok, secret_binary} = secret_binary()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    # Modify the ciphertext slightly
    modified_encrypted = <<0>> <> encrypted

    assert {:error, _} = Crypto.decrypt_with_auth_key(modified_encrypted, @valid_password, salt)
  end

  
  test "key derivation is consistent" do
    {:ok, secret_binary} = secret_binary()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    assert {:ok, decrypted_secret_binary1} =
             Crypto.decrypt_with_auth_key(encrypted, @valid_password, salt)

    assert {:ok, decrypted_secret_binary2} =
             Crypto.decrypt_with_auth_key(encrypted, @valid_password, salt)

    # Ensure the same password/salt produces the same decryption result
    assert decrypted_secret_binary1 == decrypted_secret_binary2
  end

  
  test "re-encrypting produces different ciphertext but decrypts to same value" do
    {:ok, secret_binary} = secret_binary()

    assert {:ok, %{encrypted: encrypted1, salt: salt1}} =
             Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    assert {:ok, %{encrypted: encrypted2, salt: salt2}} =
             Crypto.encrypt_with_auth_key(secret_binary, @valid_password)

    assert encrypted1 != encrypted2
    assert salt1 != salt2

    assert {:ok, decrypted_secret_binary1} =
             Crypto.decrypt_with_auth_key(encrypted1, @valid_password, salt1)

    assert {:ok, decrypted_secret_binary2} =
             Crypto.decrypt_with_auth_key(encrypted2, @valid_password, salt2)

    assert decrypted_secret_binary1 == decrypted_secret_binary2
  end
end
