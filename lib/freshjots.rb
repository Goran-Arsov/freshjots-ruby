# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "freshjots/version"

# Tiny client for the Fresh Jots API (https://freshjots.com/docs).
#
# Usage:
#
#   client = Freshjots::Client.new          # reads FRESHJOTS_TOKEN from ENV
#   client.append("cron-jobs-prod", "backup ok")
#   client.note("cron-jobs-prod")[:plain_body]
#
# All methods raise Freshjots::ApiError on non-2xx, with code/status/details
# from the API's stable error envelope.
module Freshjots
  class ApiError < StandardError
    attr_reader :status, :code, :details

    def initialize(status:, code:, message:, details: nil)
      super(message)
      @status, @code, @details = status, code, details
    end
  end

  class Client
    DEFAULT_BASE_URL = "https://freshjots.com/api/v1"

    def initialize(token: ENV["FRESHJOTS_TOKEN"], base_url: DEFAULT_BASE_URL)
      raise ArgumentError, "FRESHJOTS_TOKEN missing — pass token: or set the env var" if token.nil? || token.empty?

      @token, @base_url = token, base_url
    end

    def notes
      request(:get, "/notes")[:notes]
    end

    def note(filename)
      request(:get, "/notes/by-filename/#{escape(filename)}")[:note]
    end

    def create(filename:, body: "", title: nil)
      payload = { note: { filename: filename, plain_body: body, format: "plain" } }
      payload[:note][:title] = title if title
      request(:post, "/notes", payload)[:note]
    end

    def append(filename, text)
      request(:post, "/notes/by-filename/#{escape(filename)}/append", { text: text })
      true
    end

    private

    def request(method, path, body = nil)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
      req["Authorization"] = "Bearer #{@token}"
      if body
        req["Content-Type"] = "application/json"
        req.body = body.to_json
      end

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
      data = res.body.to_s.empty? ? {} : JSON.parse(res.body, symbolize_names: true)
      raise_for_error!(res, data)
      data
    end

    def raise_for_error!(res, data)
      return if res.is_a?(Net::HTTPSuccess)

      err = data[:error] || {}
      raise ApiError.new(
        status:  res.code.to_i,
        code:    err[:code]    || "unknown",
        message: err[:message] || "request failed",
        details: err[:details]
      )
    end

    def escape(value)
      URI.encode_www_form_component(value.to_s)
    end
  end
end
