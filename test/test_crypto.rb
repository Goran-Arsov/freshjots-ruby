# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/freshjots"

class FreshjotsCryptoTest < Minitest::Test
  # A fixed known-answer vector, embedded verbatim in the JS, Python, and Ruby
  # test suites. All three decrypting this same token to the same plaintext is
  # the cross-client interoperability guarantee for the fj1 format.
  KAT_PASSPHRASE = "test-passphrase-123"
  KAT_PLAINTEXT  = "Fresh Jots ✔ interop\nline two"
  KAT_TOKEN      = "fj1:n0zMBI1YWjNr84OlkYe1UZ6NQlez9Bre77p2CJe/BgmsOPFghVmAhriP+JEw0WXn7znpaiJHZrH42EgoZSTcp9pgDySf5dciijwvUVdUouwSC6ZyDpbIelOnvE+WFiUO"

  def test_round_trips_arbitrary_utf8
    ["", "hello", "línea ñ 日本語 🔐", "a\nb\nc"].each do |msg|
      token = Freshjots.encrypt(msg, "pw")
      assert Freshjots.encrypted?(token)
      assert_equal msg, Freshjots.decrypt(token, "pw")
    end
  end

  def test_output_is_single_line_with_prefix
    token = Freshjots.encrypt("multi\nline\nplaintext", "pw")
    assert token.start_with?("fj1:")
    refute_includes token, "\n"
  end

  def test_decrypts_shared_cross_client_vector
    assert_equal KAT_PLAINTEXT, Freshjots.decrypt(KAT_TOKEN, KAT_PASSPHRASE)
  end

  def test_wrong_passphrase_raises
    token = Freshjots.encrypt("secret", "right")
    assert_raises(Freshjots::EncryptionError) { Freshjots.decrypt(token, "wrong") }
  end

  def test_tampered_ciphertext_raises
    token = Freshjots.encrypt("secret", "pw")
    i = 8 # inside the base64 body (corrupts the salt -> key mismatch)
    swap = token[i] == "A" ? "B" : "A"
    tampered = token[0...i] + swap + token[(i + 1)..]
    assert_raises(Freshjots::EncryptionError) { Freshjots.decrypt(tampered, "pw") }
  end

  def test_rejects_non_fj1
    refute Freshjots.encrypted?("plain text")
    assert_raises(Freshjots::EncryptionError) { Freshjots.decrypt("plain text", "pw") }
  end

  def test_randomized_output
    refute_equal Freshjots.encrypt("x", "pw"), Freshjots.encrypt("x", "pw")
  end

  # ---- client_encrypted wiring ----

  def test_create_sends_client_encrypted
    client = Freshjots::Client.new(token: "t")
    captured = {}
    client.define_singleton_method(:request) do |_method, _path, body = nil|
      captured[:body] = body
      { filename: "creds.txt" }
    end
    client.create(title: "creds", body: "fj1:abc", client_encrypted: true)
    assert_equal true, captured[:body][:note][:client_encrypted]
  end

  def test_create_omits_client_encrypted_by_default
    client = Freshjots::Client.new(token: "t")
    captured = {}
    client.define_singleton_method(:request) do |_method, _path, body = nil|
      captured[:body] = body
      { filename: "x.txt" }
    end
    client.create(title: "x", body: "y")
    refute captured[:body][:note].key?(:client_encrypted)
  end

  def test_append_sends_client_encrypted
    client = Freshjots::Client.new(token: "t")
    captured = {}
    client.define_singleton_method(:request) do |_method, _path, body = nil|
      captured[:body] = body
      true
    end
    client.append("log.txt", "fj1:abc", client_encrypted: true)
    assert_equal true, captured[:body][:client_encrypted]
  end
end
