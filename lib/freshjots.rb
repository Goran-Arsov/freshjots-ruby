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
#   client.create(title: "Deploy log")[:filename]   # server-derived
#
# All methods raise Freshjots::ApiError on non-2xx, with code/status/details
# from the API's stable error envelope.
#
# Response shapes: GET /notes is the only endpoint that wraps its payload
# ({ notes: [...] }). show / show-by-filename / create return the note
# hash at the TOP LEVEL — there is no { note: ... } wrapper.
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

    # show-by-filename renders the serializer at the top level (no
    # { note: ... } wrapper), so the response *is* the note hash.
    def note(filename)
      request(:get, "/notes/by-filename/#{escape(filename)}")
    end

    # Create a note. The API permits note[title, plain_body, format, ...]
    # — NOT filename: the server DERIVES the filename from the title. For
    # a note addressable by an exact, caller-chosen filename, use append
    # (the by-filename endpoint creates it with that exact name on first
    # call). Returns the created note hash (top level); read [:filename]
    # for the server-derived stream name.
    def create(title:, body: "")
      if title.nil? || title.to_s.empty?
        raise ArgumentError,
              "create requires a title — the API derives the filename from it. " \
              "For a note addressable by an exact filename, use append."
      end
      payload = { note: { title: title, plain_body: body, format: "plain" } }
      request(:post, "/notes", payload)
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
