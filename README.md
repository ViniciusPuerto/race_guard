# race_guard

`race_guard` helps detect **race conditions** in Ruby and Rails applications by combining static and runtime analysis behind an extensible API.

- **Principles (v0.1):** framework-agnostic core, safe-by-default, prefer low false positives, composable protection, and optional DSLs (see [`docs/specs.md`](docs/specs.md)).
- This repository is the gem source. Install for local development from a path or git checkout.

## Requirements

- Ruby 3.1+

## Install (local / development)

Add to your `Gemfile`:

```ruby
gem "race_guard", path: "path/to/race_guard"
```

Or build and install the gem from this directory:

```bash
bundle install
gem build race_guard.gemspec
gem install race_guard-0.1.0.gem
```

## Configuration

`RaceGuard` keeps a per-process [configuration](lib/race_guard/configuration.rb) object. Use `RaceGuard.configure` or read `RaceGuard.configuration` / `RaceGuard.config` (aliases).

```ruby
require "race_guard"

RaceGuard.configure do |c|
  c.enable :db_lock_auditor
  c.severity :warn
end
```

- **`enable` / `disable`:** turn detectors on and off. Nothing is active until you call `enable`, so you can load the gem in production with no work unless you opt in and widen **environments** (below).
- **`severity`:** with one argument, sets the default level for all detectors. With two arguments, sets the level for a single detector (overrides the default for that name). Valid levels: `:info`, `:warn`, `:error`, `:raise`.
- **`environments`:** pass a list of `RACK_ENV` / `RAILS_ENV` names (as symbols) where race_guard may run. Default is **development and test only**; in **production** the config is *inactive* until you add `:production` (or otherwise include your deploy environment).

`ENV['RACK_ENV']` is read first, then `ENV['RAILS_ENV']` if the former is unset. If both are missing, the current environment is treated as `development` for that check.

| Setting | Default |
|--------|---------|
| Enabled detectors | None (all off until `enable`) |
| Default severity | `:info` |
| `environments` | `development`, `test` |
| Active in default production deploy | No (unless you add `production` to `environments`) |

Use `reset_configuration!` in tests or console to drop the cached singleton and start from defaults.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
rake   # RSpec + RuboCop
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
