# Read–modify–write demo (Rails + race_guard)

This directory is a **tiny Rails 7** application used to reproduce a classic read–modify–write pattern and show how `race_guard` reports it.

## Prerequisites

- Ruby 3.1+
- Bundler
- **Redis** (for the Sidekiq demo only)

## Run (under five minutes)

```bash
cd examples/rmw_rails_app
bundle install
bin/rails db:schema:load db:seed
bin/rails race_guard:demo
```

Open `log/development.log` and search for `db_lock_auditor:read_modify_write`. You should see a human-readable line describing the `Wallet#balance` pattern.

## Sidekiq demo (concurrent jobs, same wallet)

1. Start Redis (default URL `redis://localhost:6379/0`, or set `REDIS_URL`).
2. From this directory: `RAILS_ENV=development bundle exec sidekiq`
3. In another shell: `bin/rails race_guard:sidekiq_demo` (optional: `RACE_GUARD_SIDEKIQ_JOBS=100`)

Many `WalletBumpJob` workers bump the same row using read-then-`update!` so you can observe **lost updates** when concurrency wins. **SQLite** serializes writers in a single connection; use one Sidekiq process with `:concurrency` > 1 (see `config/sidekiq.yml`) so threads still overlap in Ruby before commit, or use PostgreSQL/MySQL for clearer multi-connection races. `race_guard` DB RMW detection is **per-thread**—this example mainly shows wiring plus concurrent updates, not necessarily one detector line per job.

## Distributed execution guard (Epic 10) demo

This sample can show **fleet-wide mutual exclusion** (same logical job on many hosts / duplicate Sidekiq enqueues) using [`RaceGuard.distributed_once`](https://github.com/ViniciusPuerto/race_guard/blob/main/README.md#distributed-execution-guard-epic-10).

1. **Uncomment** the optional block in `config/initializers/race_guard.rb` that enables `:distributed_guard` and sets `distributed_redis_client` (uses the same Redis URL as Sidekiq by default).
2. Ensure Redis is running (`REDIS_URL` or default `redis://localhost:6379/0`).
3. Run **`bin/rails race_guard:distributed_cron_demo`** in two terminals at once: only one process should log the “body ran” line per TTL window; the other should skip (see `log/development.log` for `distributed_guard` JSON lines if you add `JsonReporter`).

`WalletBumpJob` wraps `perform` in `distributed_once` so duplicate jobs for the same `wallet_id` **serialize** (the guard does **not** replace idempotency keys or Sidekiq uniqueness features where those are a better fit).

## What it does

- `db/schema.rb` defines a `wallets` table with a `balance` column.
- `config/initializers/race_guard.rb` registers `LogReporter` and tracks `Wallet` for the DB lock auditor.
- `lib/tasks/race_guard_demo.rake` runs `Wallet.first!`, reads `balance`, then `update!`s from that read—exactly the pattern the detector is built for.
- `config/initializers/sidekiq.rb`, `config/sidekiq.yml`, and `app/sidekiq/wallet_bump_job.rb` power `race_guard:sidekiq_demo` (Sidekiq 7 + Active Job adapter in development). `race_guard:distributed_cron_demo` exercises cron-style duplicate triggers.

## Notes

- The app uses a **checked-in** `secret_key_base` string in environment files for local demo only; do not deploy this sample as-is to production.
- The parent `race_guard` gem is loaded via `path: "../.."` in the `Gemfile`.
