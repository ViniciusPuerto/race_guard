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

```ruby
require "race_guard"

RaceGuard.configure do |c|
  # Options land here in later releases (e.g. feature flags, severity).
  c
end
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
rake   # RSpec + RuboCop
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
