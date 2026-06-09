# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/freshjots"

# Token/ApiError checks are pure; the method tests stub the transport
# (the private #request) so they assert the real request shape and
# response handling — these would have caught the top-level-serializer
# and unpermitted-filename bugs.
class FreshjotsTest < Minitest::Test
  # Replace the instance's private #request with a recorder that returns
  # `return_value`. Returns the calls array; each entry is
  # [method, path, body].
  def stub_request(client, return_value)
    calls = []
    client.define_singleton_method(:request) do |method, path, body = nil|
      calls << [method, path, body]
      return_value
    end
    calls
  end

  def client
    Freshjots::Client.new(token: "mn_x")
  end

  def test_version_is_pinned_to_1_0_2
    assert_equal "1.0.2", Freshjots::VERSION
  end

  def test_client_requires_a_token
    err = assert_raises(ArgumentError) { Freshjots::Client.new(token: nil) }
    assert_match(/FRESHJOTS_TOKEN/, err.message)
  end

  def test_client_accepts_explicit_token
    assert_kind_of Freshjots::Client, Freshjots::Client.new(token: "mn_test")
  end

  def test_api_error_carries_code_and_status
    err = Freshjots::ApiError.new(status: 422, code: "cap_exceeded", message: "over the limit")
    assert_equal 422, err.status
    assert_equal "cap_exceeded", err.code
    assert_equal "over the limit", err.message
  end

  def test_note_returns_top_level_body
    c = client
    calls = stub_request(c, { id: 7, filename: "cron jobs", plain_body: "hello" })
    note = c.note("cron jobs")
    assert_equal 7, note[:id]
    assert_equal "hello", note[:plain_body] # nil with the old [:note]
    assert_equal :get, calls[0][0]
    assert_equal "/notes/by-filename/cron+jobs", calls[0][1] # filename escaped
  end

  def test_notes_unwraps_the_notes_array
    c = client
    stub_request(c, { notes: [{ id: 1 }, { id: 2 }] })
    assert_equal [1, 2], c.notes.map { |n| n[:id] }
  end

  def test_create_requires_a_title
    err = assert_raises(ArgumentError) { client.create(title: "") }
    assert_match(/create requires a title/, err.message)
  end

  def test_create_posts_title_never_filename
    c = client
    calls = stub_request(c, { id: 9, filename: "research-2026-q2", title: "Research 2026 Q2" })
    created = c.create(title: "Research 2026 Q2", body: "o")
    assert_equal 9, created[:id]
    assert_equal "research-2026-q2", created[:filename] # server-derived
    method, path, body = calls[0]
    assert_equal :post, method
    assert_equal "/notes", path
    assert_equal "Research 2026 Q2", body[:note][:title]
    assert_equal "plain", body[:note][:format]
    refute body[:note].key?(:filename), "API does not permit note[filename]"
  end

  def test_append_posts_text_to_by_filename
    c = client
    calls = stub_request(c, { id: 1, created: false })
    assert_equal true, c.append("deploys", "shipped")
    method, path, body = calls[0]
    assert_equal :post, method
    assert_equal "/notes/by-filename/deploys/append", path
    assert_equal({ text: "shipped" }, body)
  end

  def test_notes_builds_query_from_params
    c = client
    calls = stub_request(c, { notes: [] })
    c.notes(sort: "created", folder_id: "none", limit: 5, offset: 10)
    path = calls[0][1]
    assert_match(%r{\A/notes\?}, path)
    assert_match(/sort=created/, path)
    assert_match(/folder_id=none/, path)
    assert_match(/limit=5/, path)
    assert_match(/offset=10/, path)
  end

  def test_notes_with_no_params_hits_bare_path
    c = client
    calls = stub_request(c, { notes: [] })
    c.notes
    assert_equal "/notes", calls[0][1]
  end

  def test_note_by_id
    c = client
    calls = stub_request(c, { id: 42, plain_body: "b" })
    note = c.note_by_id(42)
    assert_equal 42, note[:id]
    assert_equal :get, calls[0][0]
    assert_equal "/notes/42", calls[0][1]
  end

  def test_delete_by_id
    c = client
    calls = stub_request(c, {})
    assert_equal true, c.delete(42)
    assert_equal :delete, calls[0][0]
    assert_equal "/notes/42", calls[0][1]
  end

  def test_delete_by_filename_resolves_to_id
    c = client
    calls = stub_request(c, { id: 7, filename: "n" })
    c.delete("my-note")
    assert_equal :get, calls[0][0] # resolve via by-filename
    assert_equal "/notes/by-filename/my-note", calls[0][1]
    assert_equal :delete, calls[1][0]
    assert_equal "/notes/7", calls[1][1]
  end

  def test_move_to_folder_id
    c = client
    calls = stub_request(c, { id: 1, folder_id: 3 })
    c.move(1, folder: 3)
    assert_equal :post, calls[0][0]
    assert_equal "/notes/1/move", calls[0][1]
    assert_equal({ folder_id: 3 }, calls[0][2])
  end

  def test_move_to_root_sends_null_folder
    c = client
    calls = stub_request(c, { id: 1 })
    c.move(1, folder: nil)
    assert_equal({ folder_id: nil }, calls[0][2])
  end

  def test_move_resolves_folder_name
    c = client
    calls = stub_request(c, { folders: [{ id: 3, name: "Work" }] })
    c.move(5, folder: "Work")
    assert_equal :get, calls[0][0] # resolve /folders first
    assert_equal "/folders", calls[0][1]
    move = calls.last
    assert_equal "/notes/5/move", move[1]
    assert_equal({ folder_id: 3 }, move[2])
  end

  def test_folders_unwraps
    c = client
    stub_request(c, { folders: [{ id: 3, name: "Work" }] })
    assert_equal "Work", c.folders.first[:name]
  end
end
