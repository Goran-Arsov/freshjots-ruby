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

# List your notes.
client.notes.each { |note| puts "#{note[:filename]}\t#{note[:title]}" }

# Create a note. The API derives the filename from the title — for a
# note addressable by an exact filename, use append instead.
created = client.create(title: "Research 2026 Q2", body: "Initial outline.")
puts created[:filename] # server-derived stream name
```

The whole API is four methods: `notes`, `note(filename)`, `create(title:, body:)`, `append(filename, text)`. `note` and `create` return the note hash directly (no `{ note: … }` wrapper); `notes` returns the array.

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

Mint a token at <https://freshjots.com/settings/api_tokens> (Dev or
Dev-pro tier required). Set it once:

```sh
export FRESHJOTS_TOKEN=<your-token>
```

Or pass explicitly:

```ruby
Freshjots::Client.new(token: "fjk_…")
```

## License

MIT.
