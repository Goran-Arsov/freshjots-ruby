# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"

# Client-side encryption for Fresh Jots notes — format "fj1".
#
# Encrypt locally with your own passphrase; the server stores only the
# ciphertext and can never read it. Wire format:
#
#   "fj1:" + base64( salt[16] | iv[16] | ciphertext | mac[32] )
#
# A single PBKDF2-HMAC-SHA256 pass (210_000 iterations) derives 64 bytes from
# the passphrase and salt: the first 32 are the AES-256-CBC key, the last 32 the
# HMAC-SHA256 key. The note is AES-256-CBC encrypted, then authenticated
# encrypt-then-MAC over iv|ciphertext; decryption verifies the MAC before
# decrypting. The output is a single line (base64 carries no newlines), so it
# survives the server's newline append separator. The format is identical
# across the Fresh Jots JS, Python, Ruby, and shell clients: a note encrypted
# by one decrypts with the others. (CBC+HMAC, not GCM, because it is the one
# authenticated construction every client — including the bash CLI, whose
# openssl refuses AEAD — can implement identically.) Uses only Ruby's stdlib
# openssl (no gem deps).
module Freshjots
  class EncryptionError < StandardError; end

  FJ_PREFIX     = "fj1:"
  FJ_ITERATIONS = 210_000
  FJ_SALT_LEN   = 16
  FJ_IV_LEN     = 16
  FJ_MAC_LEN    = 32

  # True if the text carries the Fresh Jots ciphertext prefix ("fj1:"). A
  # declaration of shape, not a guarantee it decrypts.
  def self.encrypted?(text)
    text.is_a?(String) && text.start_with?(FJ_PREFIX)
  end

  # Encrypt a string with a passphrase; returns an "fj1:" token.
  def self.encrypt(plaintext, passphrase)
    raise ArgumentError, "encrypt requires a passphrase" if passphrase.nil? || passphrase.empty?

    salt = SecureRandom.random_bytes(FJ_SALT_LEN)
    iv   = SecureRandom.random_bytes(FJ_IV_LEN)
    enc_key, mac_key = fj_derive_keys(passphrase, salt)
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = enc_key
    cipher.iv  = iv
    ciphertext = cipher.update(plaintext.to_s) + cipher.final
    mac = OpenSSL::HMAC.digest("SHA256", mac_key, iv + ciphertext)
    FJ_PREFIX + Base64.strict_encode64(salt + iv + ciphertext + mac)
  end

  # Decrypt an "fj1:" token back to its plaintext. Raises EncryptionError on a
  # malformed token, a wrong passphrase, or tampering.
  def self.decrypt(token, passphrase)
    raise ArgumentError, "decrypt requires a passphrase" if passphrase.nil? || passphrase.empty?
    raise EncryptionError, "not a Fresh Jots ciphertext (missing 'fj1:' prefix)" unless encrypted?(token)

    blob =
      begin
        Base64.strict_decode64(token[FJ_PREFIX.length..])
      rescue ArgumentError
        raise EncryptionError, "ciphertext is not valid base64"
      end
    if blob.bytesize < FJ_SALT_LEN + FJ_IV_LEN + FJ_MAC_LEN + 16
      raise EncryptionError, "ciphertext is truncated or corrupted"
    end

    salt   = blob.byteslice(0, FJ_SALT_LEN)
    iv     = blob.byteslice(FJ_SALT_LEN, FJ_IV_LEN)
    mac    = blob.byteslice(blob.bytesize - FJ_MAC_LEN, FJ_MAC_LEN)
    ct_len = blob.bytesize - FJ_SALT_LEN - FJ_IV_LEN - FJ_MAC_LEN
    ct     = blob.byteslice(FJ_SALT_LEN + FJ_IV_LEN, ct_len)

    enc_key, mac_key = fj_derive_keys(passphrase, salt)
    expected = OpenSSL::HMAC.digest("SHA256", mac_key, iv + ct)
    unless mac.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(mac, expected)
      raise EncryptionError, "decryption failed — wrong passphrase or corrupted ciphertext"
    end

    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.decrypt
    cipher.key = enc_key
    cipher.iv  = iv
    begin
      (cipher.update(ct) + cipher.final).force_encoding("UTF-8")
    rescue OpenSSL::Cipher::CipherError
      raise EncryptionError, "decryption failed — wrong passphrase or corrupted ciphertext"
    end
  end

  # PBKDF2-HMAC-SHA256 -> 64 bytes split into (AES-256-CBC key, HMAC-SHA256 key).
  def self.fj_derive_keys(passphrase, salt)
    dk = OpenSSL::KDF.pbkdf2_hmac(
      passphrase.to_s,
      salt: salt, iterations: FJ_ITERATIONS, length: 64, hash: "sha256"
    )
    [dk.byteslice(0, 32), dk.byteslice(32, 32)]
  end
  private_class_method :fj_derive_keys
end
