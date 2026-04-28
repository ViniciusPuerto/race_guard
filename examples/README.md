# Examples

## `rmw_rails_app` — read–modify–write on Rails

Minimal Rails 7 app that **intentionally** performs a read then `update!` on the same column so `race_guard` can emit `db_lock_auditor:read_modify_write`.

From the **repository root**:

```bash
cd examples/rmw_rails_app
bundle install
bin/rails db:schema:load db:seed
bin/rails race_guard:demo
```

Then inspect `log/development.log` for a line containing `db_lock_auditor:read_modify_write`.

**Sidekiq:** Redis + `RAILS_ENV=development bundle exec sidekiq` from the example directory, then `bin/rails race_guard:sidekiq_demo`. Details: [examples/rmw_rails_app/README.md](rmw_rails_app/README.md).

**Distributed guard (Epic 10):** optional `RaceGuard.distributed_once` around Sidekiq `perform` and a cron-style rake demo—see [rmw_rails_app README — Distributed demo](rmw_rails_app/README.md#distributed-execution-guard-epic-10-demo).
