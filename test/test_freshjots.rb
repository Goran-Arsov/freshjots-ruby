# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/freshjots"

class FreshjotsTest < Minitest::Test
  def test_version_is_a_string
    assert_kind_of String, Freshjots::VERSION
  end

  def test_client_requires_a_token
    err = assert_raises(ArgumentError) { Freshjots::Client.new(token: nil) }
    assert_match(/FRESHJOTS_TOKEN/, err.message)
  end

  def test_client_accepts_explicit_token
    client = Freshjots::Client.new(token: "fjk_test")
    assert_kind_of Freshjots::Client, client
  end

  def test_api_error_carries_code_and_status
    err = Freshjots::ApiError.new(status: 422, code: "cap_exceeded", message: "over the limit")
    assert_equal 422, err.status
    assert_equal "cap_exceeded", err.code
    assert_equal "over the limit", err.message
  end
end
