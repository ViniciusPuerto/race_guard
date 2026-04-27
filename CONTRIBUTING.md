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

### How to add a runtime detector

1. **Decide the surface** — prepend or wrap a small API (for example ActiveRecord persistence hooks), subscribe to TracePoint, or listen to domain events. Keep failure paths rescued so the host app never crashes because of `race_guard`.
2. **Gate on configuration** — call `RaceGuard.configuration` only after checking `active?` where appropriate. Use `severity_for(:your_detector)` (and `RaceGuard.configure { |c| c.severity(:your_detector, :warn) }`) so operators can tune noise.
3. **Emit findings with `RaceGuard.report`** — build a payload consistent with [`RaceGuard::Event::SCHEMA`](lib/race_guard/event.rb): at minimum `detector`, `message`, `severity`; add `location` and `context` (for example `context['suggested_fix']`) when it helps operators.
4. **Register opt-in wiring** — if the detector needs models or globs, expose configuration on [`RaceGuard::Configuration`](lib/race_guard/configuration.rb) and document it in the README and [`docs/specs.md`](docs/specs.md).
5. **Test** — add specs under `spec/race_guard/` that prove both “fires when expected” and “stays quiet when expected”. The DB read–modify–write auditor is a concrete reference: [`lib/race_guard/db_lock_auditor/read_modify_write.rb`](lib/race_guard/db_lock_auditor/read_modify_write.rb) and [`spec/race_guard/db_lock_auditor/read_modify_write_spec.rb`](spec/race_guard/db_lock_auditor/read_modify_write_spec.rb).

### How to add a rule (`RaceGuard.define_rule`)

Rules are **named** pieces of logic evaluated from [`RaceGuard::RuleEngine`](lib/race_guard/rule_engine.rb) when an event is dispatched or when `RuleEngine.evaluate` runs.

1. **Define** — in library or app initializer:

   ```ruby
   RaceGuard.define_rule(:my_rule) do |r|
     r.detect { |_ctx, meta| meta[:flag] == true }
     r.message { |_ctx, _meta| "explain why this matters" }
   end
   ```

   You must supply both `detect` and `message` procs (see [`lib/race_guard/rule.rb`](lib/race_guard/rule.rb)). Optional: `r.run_on :protect_enter` / `:protect_exit` so `RuleEngine.dispatch` runs the rule when `RaceGuard.protect` fires; optional `r.hook(:protect_enter) { |ctx, meta| ... }` for side effects without reporting.

2. **Enable** — rules are off until `RaceGuard.configure { |c| c.enable_rule(:my_rule) }` (and the environment allowlist includes the current `RACK_ENV` / `RAILS_ENV`).

3. **Run** — call `RaceGuard::RuleEngine.evaluate(:my_rule, metadata: { flag: true })` for explicit checks, or rely on `RaceGuard.protect` (which calls `RuleEngine.dispatch(:protect_enter, protect: name)` / `:protect_exit` for you) when the rule lists matching `run_on` events.

4. **Test** — mirror patterns in [`spec/race_guard/rule_engine_spec.rb`](spec/race_guard/rule_engine_spec.rb): registry reset in `after`, environment isolation with `with_isolated_env`, and expectations on `RaceGuard.report` side effects.

### Reporters

- Implement `report(event)` accepting a [`RaceGuard::Event`](lib/race_guard/event.rb). Use `event.to_h` for JSON lines. Do not raise into application code; swallow or log internal failures.

See [docs/specs.md](docs/specs.md) for planned areas (commit safety, DB lock auditor, static analysis, etc.).

## Security

Do **not** file security issues in public GitHub issues. See [`SECURITY.md`](SECURITY.md).

## Code of conduct

This project uses the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.
