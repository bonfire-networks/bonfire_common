defmodule Bonfire.Common.Crypto do
  import Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Extend

  #  NOTE: do not change once used, otherwise users won't be able to decrypt existing secrets
  @default_algo :chacha
  # TODO: put all in config
  # for current number of recommended iterations see https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2
  @iterations 600_000
  @derived_key_length 32
  @gcm_tag "AES.GCM.V1"
  @iv_length 12

  # encrypts some text with a password
  def encrypt_with_auth_key(clear_text, password) do
    # NOTE: salt should be a unique salt per-user, and saved to be used for decryption later.
    salt = :crypto.strong_rand_bytes(16)

    with {:ok, encrypted} <- encrypt_with_auth_key(clear_text, password, salt) do
      # Return the encrypted PEM, salt, and any other necessary data
      {:ok,
       %{
         encrypted: encrypted,
         salt: salt
       }}
    else
      e ->
        error(e, "Encryption failed")
    end
  end

  def encrypt_with_auth_key(clear_text, password, salt) do
    # Derive a secret auth key from the password and salt
    secret_auth_key = derive_key(password, salt)

    cond do
      algo() == :chacha and Extend.module_exists?(Plug.Crypto.MessageEncryptor) ->
        # optionally use XChaCha20-Poly1305 `Plug.Crypto`?
        {:ok, Plug.Crypto.MessageEncryptor.encrypt(clear_text, secret_auth_key, "")}

      Extend.module_exists?(Cloak.Ciphers.AES.GCM) ->
        # use AES GCM encryption
        Cloak.Ciphers.AES.GCM.encrypt(clear_text,
          key: secret_auth_key,
          tag: @gcm_tag,
          iv_length: @iv_length
        )

      true ->
        error("No encryption library available")
    end
  end

  # Function to decrypt the RSA PEM using password
  def decrypt_with_auth_key(encrypted, password, salt) do
    # Derive the secret auth key again from the password and salt
    secret_auth_key = derive_key(password, salt)

    # Decrypt the encrypted PEM using Cloak's AES GCM decryption
    case do_decrypt(encrypted, secret_auth_key) do
      {:ok, :error} ->
        error("Unexpected decryption error, maybe the password or salt was incorrect?")

      {:ok, decrypted} ->
        {:ok, decrypted}

      :error ->
        error("Decryption error")

      e ->
        error(e, "Decryption error")
    end
  end

  defp do_decrypt(encrypted, secret_auth_key) do
    cond do
      algo() == :chacha and Extend.module_exists?(Plug.Crypto.MessageEncryptor) ->
        # optionally use XChaCha20-Poly1305 `Plug.Crypto`?
        Plug.Crypto.MessageEncryptor.decrypt(encrypted, secret_auth_key, "")

      Extend.module_exists?(Cloak.Ciphers.AES.GCM) ->
        # use AES GCM encryption
        Cloak.Ciphers.AES.GCM.decrypt(encrypted,
          key: secret_auth_key,
          tag: @gcm_tag,
          iv_length: @iv_length
        )

      true ->
        error("No encryption library available")
    end
  end

  # Derives a key using PBKDF2-HMAC from the password and salt
  defp derive_key(password, salt) do
    if Extend.module_exists?(Plug.Crypto.KeyGenerator) do
      # use helper function from `Plug.Crypto` if available
      Plug.Crypto.KeyGenerator.generate(password, salt,
        iterations: @iterations,
        length: @derived_key_length
      )
    else
      :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, @derived_key_length)
    end
  end

  defp algo do
    crypt_conf(:algo, @default_algo)
  end

  defp crypt_conf(key, default) do
    Config.get([__MODULE__, key], default)
  end
end
