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

See [examples/rmw_rails_app/README.md](rmw_rails_app/README.md) for details.
