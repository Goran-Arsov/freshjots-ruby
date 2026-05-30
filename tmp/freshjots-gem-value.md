# What a Rails project gains from the `freshjots` gem

_Generated 2026-05-18. Based on `lib/freshjots.rb` (107 lines, zero runtime dependencies — stdlib `net/http` + `json` only)._

## What it actually is

A thin wrapper around the Fresh Jots REST API — append-only plain-text notebooks. It exposes exactly four operations:

| Method | Purpose |
|---|---|
| `client.notes` | list all notes |
| `client.note(filename)` | fetch one note's contents |
| `client.create(title:, body:)` | make a new note (server derives filename from title) |
| `client.append(filename, text)` | append a line to a note (creates it on first call) |

Auth is a bearer token from `FRESHJOTS_TOKEN`. Errors raise `Freshjots::ApiError` with `status` / `code` / `details` from a stable error envelope.

## What your Rails project gains

**A remote, append-only log/journal you can write to from anywhere — without standing up infrastructure for it.** Concretely useful for:

- **Cron / scheduled jobs** — append "nightly backup OK @ 03:14" so there's a human-readable trail outside your app's DB and log files.
- **Deploy scripts** — append release markers ("deployed v0.2.1, migrations ran clean").
- **Background jobs / bots** — drop a breadcrumb when something noteworthy (or alarming) happens, visible in a browser without SSH or log aggregation.
- **Out-of-band audit** — a record that survives even if the app DB is the thing that's broken.

The honest pitch: it's `Rails.logger` for things you want a *person* to read later, persisted off-box, reachable from a one-liner.

## What it does *not* give you

- Not a logging backend, not a `Rails.logger` adapter — no batching, no async, no retry/backoff. A failed call raises and (unless rescued) can break the surrounding job.
- Synchronous blocking HTTP. Calling it inside a request cycle adds the round-trip to response time — use it from jobs/rake/cron, not controllers.
- Append-only. No update, no delete, no search via this client.
- An external dependency on `freshjots.com` being up and the token being valid.

## Cost of adding it

Near zero: one line in `Gemfile`, no transitive dependencies, requires Ruby >= 3.0. Typical usage:

```ruby
# config/initializers/freshjots.rb  (or just instantiate where needed)
FRESHJOTS = Freshjots::Client.new   # reads FRESHJOTS_TOKEN

# in a job / rake task
FRESHJOTS.append("deploys-prod", "#{Time.current.iso8601} deployed #{ENV['GIT_SHA']}")
```

To never break a job when the API is down, wrap calls in `rescue Freshjots::ApiError` (or use an `ActiveJob` with `discard_on` / `retry_on`).
