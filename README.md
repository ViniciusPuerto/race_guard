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

## Context

[`RaceGuard.context`](lib/race_guard/context.rb) exposes **thread-local** state: each Ruby thread has its own stack and transaction depth. Nothing is stored in a global `Thread` hash, so finished threads do not leave behind context entries.

- **`RaceGuard.context.current`** — immutable snapshot: `thread_id` (opaque `Thread.current.object_id`), `in_transaction` (true when nested `begin_transaction` depth is positive), `protected_blocks` (symbols, **outermost first** — first `push_protected` is index `0`, innermost is last), `current_rule` (reserved, always `nil` until the rule engine exists).
- **`push_protected` / `pop_protected`** — stack helpers; `pop` on an empty stack is a no-op.
- **`begin_transaction` / `end_transaction`** — nesting counter; extra `end_transaction` when depth is zero is a no-op.
- **`RaceGuard.context.reset!`** — clears context for the **current thread only** (use in tests; does not reset `RaceGuard.configuration`).

## Protection (`RaceGuard.protect`)

Wrap code so the thread-local context stack records a **named block** (used by future detectors and by reporting):

```ruby
RaceGuard.protect(:payment_flow) do
  # monitored
end
```

Nested `protect` calls push/pop in order (outermost block is first in `context.current.protected_blocks`). The block body runs between push and pop; **pop runs in `ensure`**, so the stack is restored even if the block raises.

When you call [`RaceGuard.report`](#reporting) inside an active `protect`, the event `context` hash is merged with **`protect`** (innermost block name as a string) and **`protect_stack`** (all nested names, outermost first).

Register optional hooks with `RaceGuard.configure { |c| c.add_protect_detector(obj) }` if `obj` responds to `on_protect_enter(name)` / `on_protect_exit(name)` (see [`RaceGuard::DetectorRuntime`](lib/race_guard/detector_runtime.rb)).

## Reporting

`RaceGuard.report` delivers events to any number of [reporters](lib/race_guard/reporters/). The payload is a [`RaceGuard::Event`](lib/race_guard/event.rb); you can also pass a Hash with string or symbol keys (`detector`, `message`, `severity` required). See `RaceGuard::Event::SCHEMA` for the field contract.

- **`add_reporter` / `remove_reporter` / `clear_reporters`:** register objects responding to `report(event)`.
- **Built-in reporters:** `RaceGuard::Reporters::LogReporter` (stdlib Logger), `JsonReporter` (one JSON line per event to an IO), `FileReporter` (append JSONL to a path), `WebhookReporter` (POST JSON; failures are swallowed so your app is not taken down by a bad URL).

`RaceGuard.report` does nothing when the configuration is **not** active in the current environment (same rules as the rest of the gem: default is development/test only).

```ruby
RaceGuard.configure do |c|
  c.add_reporter RaceGuard::Reporters::LogReporter.new(Logger.new($stderr))
  c.add_reporter RaceGuard::Reporters::JsonReporter.new($stdout)
end

RaceGuard.report(detector: "demo", message: "hello", severity: :warn, location: "app.rb:1")
```

### Try it in `irb`

From the project root, use `bundle exec irb -Ilib -r race_guard`.

1. **Reset and set dev** — `RaceGuard.reset_configuration!` then `ENV["RACK_ENV"] = "development"` (or leave unset; it defaults to `development`).
2. **Register reporters** — e.g. `log_io = StringIO.new; RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::LogReporter.new(Logger.new(log_io))) }` (in plain IRB use a real `Logger` to `$stdout` or a file if you do not have `StringIO` loaded: `require "stringio"` first).
3. **Report** — `RaceGuard.report(detector: "a", message: "b", severity: :info)`; inspect your IO or `log_io.string`.
4. **File line** — `RaceGuard.reset_configuration!`; `p = File.join(Dir.tmpdir, "rg.jsonl"); require "tmpdir";` then `configure { |c| c.add_reporter(RaceGuard::Reporters::FileReporter.new(p)) }` and `RaceGuard.report(...)`; `File.read(p)`.
5. **Production no-op** — `ENV["RACK_ENV"] = "production"`, re-add a `JsonReporter` to `$stdout`, run `report`; you should see no new output, then `ENV.delete("RACK_ENV")` and `RaceGuard.reset_configuration!`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
rake   # RSpec + RuboCop
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
