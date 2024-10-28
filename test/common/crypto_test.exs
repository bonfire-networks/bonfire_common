defmodule Bonfire.Common.Crypto.Test do
  use Bonfire.Common.DataCase, async: true
  alias Bonfire.Common.Crypto
  alias ActivityPub.Safety.Keys

  @valid_password "correct_password"
  @invalid_password "wrong_password"

  @tag disabled: true
  test "encrypt_with_auth_key returns properly structured result" do
    {:ok, rsa_pem} = Keys.generate_rsa_pem()

    assert {:ok,
            %{
              encrypted: encrypted,
              salt: salt
            }} = Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    assert is_binary(encrypted)
    assert byte_size(salt) == 16
  end

  @tag disabled: true
  test "decryption succeeds with correct password" do
    {:ok, rsa_pem} = Keys.generate_rsa_pem()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    assert {:ok, decrypted_rsa_pem} =
             Crypto.decrypt_with_auth_key(encrypted, @valid_password, salt)

    assert decrypted_rsa_pem == rsa_pem
  end

  @tag disabled: true
  test "decryption fails with incorrect password" do
    {:ok, rsa_pem} = Keys.generate_rsa_pem()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    assert {:error, _} = Crypto.decrypt_with_auth_key(encrypted, @invalid_password, salt)
  end

  @tag disabled: true
  test "decryption fails if ciphertext is modified" do
    {:ok, rsa_pem} = Keys.generate_rsa_pem()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    # Modify the ciphertext slightly
    modified_encrypted = <<0>> <> encrypted

    assert {:error, _} = Crypto.decrypt_with_auth_key(modified_encrypted, @valid_password, salt)
  end

  @tag disabled: true
  test "key derivation is consistent" do
    {:ok, rsa_pem} = Keys.generate_rsa_pem()

    assert {:ok, %{encrypted: encrypted, salt: salt}} =
             Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    assert {:ok, decrypted_rsa_pem1} =
             Crypto.decrypt_with_auth_key(encrypted, @valid_password, salt)

    assert {:ok, decrypted_rsa_pem2} =
             Crypto.decrypt_with_auth_key(encrypted, @valid_password, salt)

    # Ensure the same password/salt produces the same decryption result
    assert decrypted_rsa_pem1 == decrypted_rsa_pem2
  end

  @tag disabled: true
  test "re-encrypting produces different ciphertext but decrypts to same value" do
    {:ok, rsa_pem} = Keys.generate_rsa_pem()

    assert {:ok, %{encrypted: encrypted1, salt: salt1}} =
             Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    assert {:ok, %{encrypted: encrypted2, salt: salt2}} =
             Crypto.encrypt_with_auth_key(rsa_pem, @valid_password)

    assert encrypted1 != encrypted2
    assert salt1 != salt2

    assert {:ok, decrypted_rsa_pem1} =
             Crypto.decrypt_with_auth_key(encrypted1, @valid_password, salt1)

    assert {:ok, decrypted_rsa_pem2} =
             Crypto.decrypt_with_auth_key(encrypted2, @valid_password, salt2)

    assert decrypted_rsa_pem1 == decrypted_rsa_pem2
  end
end
