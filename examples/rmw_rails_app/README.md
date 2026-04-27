# Read–modify–write demo (Rails + race_guard)

This directory is a **tiny Rails 7** application used to reproduce a classic read–modify–write pattern and show how `race_guard` reports it.

## Prerequisites

- Ruby 3.1+
- Bundler

## Run (under five minutes)

```bash
cd examples/rmw_rails_app
bundle install
bin/rails db:schema:load db:seed
bin/rails race_guard:demo
```

Open `log/development.log` and search for `db_lock_auditor:read_modify_write`. You should see a human-readable line describing the `Wallet#balance` pattern.

## What it does

- `db/schema.rb` defines a `wallets` table with a `balance` column.
- `config/initializers/race_guard.rb` registers `LogReporter` and tracks `Wallet` for the DB lock auditor.
- `lib/tasks/race_guard_demo.rake` runs `Wallet.first!`, reads `balance`, then `update!`s from that read—exactly the pattern the detector is built for.

## Notes

- The app uses a **checked-in** `secret_key_base` string in environment files for local demo only; do not deploy this sample as-is to production.
- The parent `race_guard` gem is loaded via `path: "../.."` in the `Gemfile`.
