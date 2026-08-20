# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "freshjots/version"
require_relative "freshjots/crypto"

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

    # List notes (summary projection). Keyword options mirror the API
    # query params: sort (created|updated|appended, default updated),
    # folder_id (a folder id, or "none" for un-foldered notes only), and
    # limit/offset for pagination (the server caps a page at 200).
    def notes(sort: nil, folder_id: nil, limit: nil, offset: nil)
      query = {}
      query[:sort]      = sort      if sort
      query[:folder_id] = folder_id unless folder_id.nil? || folder_id.to_s.empty?
      query[:limit]     = limit     unless limit.nil?
      query[:offset]    = offset    unless offset.nil?
      path = query.empty? ? "/notes" : "/notes?#{URI.encode_www_form(query)}"
      request(:get, path)[:notes]
    end

    # show-by-filename renders the serializer at the top level (no
    # { note: ... } wrapper), so the response *is* the note hash.
    def note(filename)
      request(:get, "/notes/by-filename/#{escape(filename)}")
    end

    # Full note by numeric id (GET /notes/:id) — top-level serializer.
    def note_by_id(id)
      request(:get, "/notes/#{escape(id)}")
    end

    # Create a note. The API permits note[title, plain_body, format, ...]
    # — NOT filename: the server DERIVES the filename from the title. For
    # a note addressable by an exact, caller-chosen filename, use append
    # (the by-filename endpoint creates it with that exact name on first
    # call). Returns the created note hash (top level); read [:filename]
    # for the server-derived stream name.
    # Pass client_encrypted: true to mark the note as a client-encrypted note
    # — body is opaque ciphertext you produced with Freshjots.encrypt; the
    # server stores it verbatim and never reads it. Personal accounts only.
    def create(title:, body: "", client_encrypted: false)
      if title.nil? || title.to_s.empty?
        raise ArgumentError,
              "create requires a title — the API derives the filename from it. " \
              "For a note addressable by an exact filename, use append."
      end
      note = { title: title, plain_body: body, format: "plain" }
      note[:client_encrypted] = true if client_encrypted
      request(:post, "/notes", { note: note })
    end

    # On first-touch creation, pass client_encrypted: true to open the stream
    # as a client-encrypted note (send one ciphertext line per append).
    # Ignored once the note exists.
    def append(filename, text, client_encrypted: false)
      body = { text: text }
      body[:client_encrypted] = true if client_encrypted
      request(:post, "/notes/by-filename/#{escape(filename)}/append", body)
      true
    end

    # Delete a note. Accepts a numeric id or a filename (resolved to its
    # id via the by-filename lookup). Locked (append-only) notes are
    # refused by the API with note_locked. Returns true on success.
    def delete(id_or_filename)
      request(:delete, "/notes/#{resolve_note_id(id_or_filename)}")
      true
    end

    # Move a note into a folder. `folder` may be a folder id, a folder
    # name (resolved via /folders), or nil / "none" / "root" to send the
    # note back to the root.
    def move(id_or_filename, folder: nil)
      id = resolve_note_id(id_or_filename)
      request(:post, "/notes/#{id}/move", { folder_id: resolve_folder_id(folder) })
    end

    # List folders ({ folders: [...] } envelope).
    def folders
      request(:get, "/folders")[:folders]
    end

    private

    # A note reference is either a numeric id (used as-is) or a
    # filename/title resolved to an id via the by-filename lookup.
    def resolve_note_id(value)
      return value if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

      note(value.to_s)[:id]
    end

    # A folder reference resolves to an id (or nil for the root). Names go
    # through /folders; an unknown or ambiguous name is an ArgumentError.
    def resolve_folder_id(value)
      return nil if value.nil? || %w[none root null].include?(value.to_s.downcase)
      return value if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

      matches = folders.select { |f| f[:name] == value.to_s }
      raise ArgumentError, "no folder named '#{value}'" if matches.empty?
      raise ArgumentError, "ambiguous folder name '#{value}' — use its id" if matches.size > 1

      matches.first[:id]
    end

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
