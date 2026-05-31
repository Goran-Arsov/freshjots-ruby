# freshjots — Ruby

Tiny Ruby client for the [Fresh Jots](https://freshjots.com) API. One file,
no runtime dependencies (uses `net/http` from stdlib).

## Install

```ruby
# Gemfile
gem "freshjots"
```

```sh
bundle install
```

Or globally:

```sh
gem install freshjots
```

## Use

```ruby
require "freshjots"

# Reads FRESHJOTS_TOKEN from the environment by default.
client = Freshjots::Client.new

# Append text to a note (creates it if missing).
client.append("cron-jobs-prod", "backup ok #{Time.now.utc.iso8601}")

# Read a note's body.
puts client.note("cron-jobs-prod")[:plain_body]

# List your notes (most recent activity first). Sort and filter with options:
client.notes(sort: "created", folder_id: 3, limit: 20).each do |note|
  puts "#{note[:id]}\t#{note[:filename]}\t#{note[:title]}"
end

# Create a note. The API derives the filename from the title — for a
# note addressable by an exact filename, use append instead.
created = client.create(title: "Research 2026 Q2", body: "Initial outline.")
puts created[:filename] # server-derived stream name

# Organize: move into a folder (by id or name), delete (by id or filename), list folders.
client.move("cron-jobs-prod", folder: "Ops")
client.delete("old-note")
client.folders.each { |f| puts "#{f[:id]}\t#{f[:name]}" }
```

Client methods: `notes(sort:, folder_id:, limit:, offset:)`, `note(filename)`, `note_by_id(id)`, `create(title:, body:)`, `append(filename, text)`, `delete(id_or_filename)`, `move(id_or_filename, folder:)`, and `folders`. `note`/`note_by_id`/`create` return the note hash directly (no `{ note: … }` wrapper); `notes` and `folders` return arrays. For `notes`, `sort` is `created|updated|appended` and `folder_id` may be a folder id or `"none"` (un-foldered only).

## Errors

Any non-2xx response raises `Freshjots::ApiError` with `status`, `code`,
`message`, and (when present) `details` from the API's stable error
envelope:

```ruby
begin
  client.append("huge", "x" * 5_000_000)
rescue Freshjots::ApiError => e
  puts "#{e.status} #{e.code}: #{e.message}"
  # 413 content_too_large: body exceeds the per-note 3 MB cap
end
```

Stable error codes: `unauthenticated`, `forbidden`, `not_found`,
`validation_failed`, `cap_exceeded`, `storage_cap_exceeded`,
`content_too_large`, `content_type_mismatch`, `rate_limited`. Full list:
<https://freshjots.com/docs>.

## Auth

Mint a token at <https://freshjots.com/settings/api_tokens> (Pro or
Team tier required). Set it once, persisted for every new shell
(macOS defaults to zsh; use `~/.bashrc` on bash):

```sh
echo 'export FRESHJOTS_TOKEN=<your-token>' >> ~/.zshrc && source ~/.zshrc
```

Or pass explicitly:

```ruby
Freshjots::Client.new(token: "fjk_…")
```

## License

MIT.
