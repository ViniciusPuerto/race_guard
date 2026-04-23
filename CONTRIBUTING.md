# Contributing to race_guard

Thanks for your interest. This project is under active development; the [product spec](docs/specs.md) tracks epics and definition of done.

## Principles (carry these into changes)

- **Framework-agnostic core** — Rails pieces stay behind optional require paths.
- **Safe by default** — do not change production behavior unless the user opts in (see configuration defaults in the README).
- **Low false positives** — new detectors and rules should be conservative; noisy warnings erode trust.
- **Thread-safe and resilient** — failures in instrumentation must not take down the host app.

## Development setup

- Ruby 3.1+ (see CI matrix in [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).
- From the repository root:

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

Or: `rake` (runs RSpec and RuboCop).

## Before you open a PR

1. **Tests** — add or update specs for the behavior you change. Prefer unit tests; integration tests when touching Rails or ActiveRecord.
2. **Style** — `bundle exec rubocop` passes.
3. **Changelog** — for user-visible fixes or features, add a line under `[Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md) (or note “skip changelog” in the PR if the change is internal-only).

## Adding detectors, rules, or reporters

- **Detectors** — keep boundaries clear, respect `RaceGuard.configuration` and whether the current environment is active.
- **Rules** — use [`RaceGuard.define_rule`](README.md#rules-raceguarddefine_rule) and document new rule names in the PR.
- **Reporters** — follow the `report(event)` contract and [`RaceGuard::Event::SCHEMA`](lib/race_guard/event.rb).

See [docs/specs.md](docs/specs.md) for planned areas (commit safety, DB lock auditor, static analysis, etc.).

## Security

Do **not** file security issues in public GitHub issues. See [`SECURITY.md`](SECURITY.md).

## Code of conduct

This project uses the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.
