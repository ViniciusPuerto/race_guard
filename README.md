# race_guard

<p align="center">
  <img src="docs/assets/race-guard-logo.png" alt="Race Guard" width="320">
</p>

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

### ActiveRecord transactions (optional)

For Rails apps, you can mirror **`ActiveRecord::Base.transaction`** onto the same thread-local depth counter (`in_transaction?` becomes true for the duration of each nested `transaction` block, including **`requires_new: true`** inner blocks).

```ruby
require "active_record" # or load via Rails
require "race_guard"
require "race_guard/active_record" # prepends once; or call RaceGuard::ActiveRecord.install_transaction_tracking!

ActiveRecord::Base.transaction do
  RaceGuard.context.current.in_transaction? # => true
end
```

Core [`RaceGuard.context`](#context) already exposes **`begin_transaction` / `end_transaction`** for tests or non-AR code paths; the optional file wires ActiveRecord only. Implementation: [`lib/race_guard/active_record.rb`](lib/race_guard/active_record.rb).

### Commit safety interceptors (optional, Task 3.2)

After [`RaceGuard.configure`](#configuration) (active environment + reporters as needed), load and install hooks that emit **`RaceGuard.report`** events with detector names `commit_safety:active_job`, `commit_safety:action_mailer`, `commit_safety:net_http`, and `commit_safety:faraday`. Reporting and emitter logic are wrapped so **failures do not break the host app**.

```ruby
require "race_guard"
require "race_guard/interceptors"

RaceGuard::Interceptors.install_active_job!      # ActiveJob::Base.perform_later
RaceGuard::Interceptors.install_action_mailer! # ActionMailer::MessageDelivery#deliver_later
RaceGuard::Interceptors.install_net_http!      # Net::HTTP#request (requires "net/http")
RaceGuard::Interceptors.install_faraday!     # Faraday::Connection#run_request
# or RaceGuard::Interceptors.install_all! for each constant that is already loaded
```

- **ActionMailer:** the event is emitted **after** enqueue so Rails is not tripped by reading the message before `MailDeliveryJob` runs.
- **Faraday / ActiveJob:** require those libraries before calling the matching `install_*` method (or call `install_all!` once dependencies are loaded). Each `install_*` is idempotent per process.

Implementation: [`lib/race_guard/interceptors.rb`](lib/race_guard/interceptors.rb).

### Custom commit-safety watches (`watch_commit_safety`)

Register **your own** side-effect boundaries so they emit the same style of `commit_safety:*` events as the built-in interceptors, without wrapping calls in [`RaceGuard.protect`](#protection-raceguardprotect).

```ruby
RaceGuard.configure do |c|
  c.watch_commit_safety :custom do |w|
    w.intercept(MyClient, :call)
  end
end
```

- **`intercept(klass, method_name, scope: :auto)`** — same resolution rules as [`RaceGuard.watch`](#method-watch-raceguardwatch): only **public** methods **defined on** `klass` (not inherited-only); `:auto` prefers an instance method when both instance and singleton match.
- **Detector name** — events use `commit_safety:<name>` where `<name>` is the symbol or string you passed to `watch_commit_safety`.
- **Idempotent per watch** — the same `intercept` line does not double-prepend; you may register **different** watch names that wrap the same method (each emits once per call in prepend order).
- **Implementation:** [`lib/race_guard/commit_safety/watcher.rb`](lib/race_guard/commit_safety/watcher.rb).

### After successful transaction (`RaceGuard.after_commit`)

Run work **after** the current **ActiveRecord** `transaction` block finishes **without** raising (same nesting level). If the current thread is **not** in a transaction, the block runs **immediately**. Errors inside the block are **rescued** so they do not take down the host app.

```ruby
require "race_guard/active_record" # AR transaction patch + depth tracking

ActiveRecord::Base.transaction do
  RaceGuard.after_commit { enqueue_follow_up }
end
```

- **Prerequisite:** load [`race_guard/active_record`](#activerecord-transactions-optional) so `ActiveRecord::Base.transaction` drives `RaceGuard.context` depth and passes a **success** flag when the block completes. Without it, use [`begin_transaction` / `end_transaction`](#context) manually; deferred callbacks flush on `end_transaction(success: true)`.
- **Nesting:** inner frames flush first; a raised inner block discards that frame’s deferred callbacks while outer frames follow normal success/failure rules.
- **`RaceGuard.context.reset!`** clears deferred callbacks for the current thread (useful in tests).

Implementation: [`lib/race_guard/context.rb`](lib/race_guard/context.rb), [`lib/race_guard/active_record.rb`](lib/race_guard/active_record.rb), [`lib/race_guard.rb`](lib/race_guard.rb).

### DB read–modify–write (Epic 4.1) and lock awareness (4.2)

Opt-in **runtime** signal when a **configured** ActiveRecord model reads an attribute in the current thread, then a **successful** `save` / `save!` persists a change to that same attribute. Reports use detector **`db_lock_auditor:read_modify_write`**.

- **Requires** ActiveRecord and that you load the integration that prepends the patches, e.g. `require "race_guard/active_record"`.
- **Configure the model classes** to audit; untracked classes are not instrumented.
- **Semantics:** reads are tracked via `read_attribute` and `_read_attribute` (the path used by generated column readers). The write check runs **after** a successful `save`/`save!` using `saved_changes`. `update` / `update!` are covered because they end in `save`. Paths like `update_columns` are out of scope for this detector.
- **Lock awareness (4.2):** if the same row is written under a pessimistic lock via `with_lock` (including nested) or `lock!` inside a tracked ActiveRecord `transaction` (as mirrored onto `RaceGuard.context` by the integration), the RMW report for that change is **suppressed** for that model; another tracked model in the same process can still report if it is not under an observed lock. Journal state for a row is cleared on `lock!` to avoid spurious RMW for reads taken before locking.
- **Thread-local journal** with a short TTL and max key count (see [`RaceGuard::Context::MutableStore`](lib/race_guard/context.rb)); reads in another thread do not correlate. `RaceGuard.context.reset!` clears the journal for the current thread and the read–modify–write “inside save” / read re-entrancy thread flags (so a stuck depth from a bad stack unwind in IRB does not skip read capture, which would make `rmw_read_age_ms_for` return nil and suppress reports).
- **Severity:** e.g. `c.severity(:'db_lock_auditor:read_modify_write', :warn)`.

```ruby
require "active_record"
require "race_guard"
require "race_guard/active_record" # prepends RMW + transaction patches

class Account < ApplicationRecord
end

RaceGuard.configure do |c|
  c.add_reporter(RaceGuard::Reporters::LogReporter.new(Logger.new($stdout)))
  c.db_lock_read_modify_write_models(Account) # or pass several classes
  c.severity(:'db_lock_auditor:read_modify_write', :warn)
end
```

Implementation: [`lib/race_guard/db_lock_auditor/read_modify_write.rb`](lib/race_guard/db_lock_auditor/read_modify_write.rb).

**Smoke test (IRB-quality scenarios, no `mtmpdir` typo):** from the repo root, with dev dependencies installed:

```bash
ruby script/smoke_db_lock_rmw.rb
# or: bundle exec ruby -Ilib script/smoke_db_lock_rmw.rb
```

The script prepends the repo `lib/` directory to `$LOAD_PATH`, so you do not need `-Ilib` when you run it from the repository root. It uses `require "tmpdir"` and `Dir.tmpdir` for a file-backed SQLite DB, asserts one RMW JSON line without a lock, then checks that `with_lock`, `lock!` in a transaction, nested `with_lock`, and two threads using `with_lock` produce **no** RMW lines and leaves balance **8** after two decrements.

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

## Method watch (`RaceGuard.watch`)

Install a **prepend** wrapper so every call to a **public method defined directly** on the class or module runs inside [`RaceGuard.protect`](#protection-raceguardprotect) (same stack and reporting hooks as a manual `protect`):

```ruby
RaceGuard.watch(MyService, :call)
```

- **`scope:`** `:auto` (default) picks an **own** instance method if one exists on `klass`, otherwise an **own** singleton (class) method. If both exist, **instance wins**. Use `scope: :instance` or `scope: :singleton` to force.
- **Idempotent:** calling `watch` again for the same `klass`, method name, and owner is a no-op (no double wrap). Registration is guarded by a mutex so concurrent `watch` calls are safe.
- **v0.1 limitation:** only **public** methods declared **on that class** (`public_instance_methods(false)` / `singleton_class.public_instance_methods(false)`) are eligible; inherited-only methods are not matched by `:auto`.

Implementation: [`RaceGuard::MethodWatch`](lib/race_guard/method_watch.rb).

## Rules (`RaceGuard.define_rule`)

Register named rules with a **detect** / **message** pair and optional **hooks** on protect boundaries. Callbacks receive [`RaceGuard.context.current`](#context) (a frozen snapshot) and a **metadata** `Hash` with symbol keys (for example `event:`, `protect:`).

```ruby
RaceGuard.define_rule(:no_side_effects_in_txn) do |rule|
  rule.detect { |ctx, meta| ctx.in_transaction? }
  rule.message { |_ctx, _meta| "Side effect while in transaction" }
  rule.hook(:protect_enter) { |ctx, meta| # observe only }
  rule.run_on :protect_exit # when set, dispatch runs detect on these events
  rule.severity :warn       # optional; else `severity_for(:rule_name)` from config
end

RaceGuard.configure do |c|
  c.enable_rule :no_side_effects_in_txn
end
```

- **Enablement:** rules are **off** until `enable_rule` on [`RaceGuard::Configuration`](lib/race_guard/configuration.rb). In inactive environments (same rules as the rest of the gem), `enabled_rule?` is false even if the name was toggled on.
- **`run_on`:** if you omit it, `detect` / `message` are **not** run automatically from `protect`; use [`RaceGuard::RuleEngine.evaluate`](lib/race_guard/rule_engine.rb) from tests or future detectors. With `run_on :protect_enter` / `:protect_exit`, [`DetectorRuntime`](lib/race_guard/detector_runtime.rb) dispatches after each `protect` push/pop.
- **`hook`:** only `:protect_enter` and `:protect_exit` are supported in v0.1. Hook failures are swallowed so your app keeps running.
- **Registry:** duplicate rule names raise; tests can call `RaceGuard::RuleEngine.reset_registry!` to clear definitions (prepended modules from `watch` are separate).

Implementation: [`RaceGuard::RuleEngine`](lib/race_guard/rule_engine.rb), [`RaceGuard::Rule`](lib/race_guard/rule.rb).

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
4. **File line** — `RaceGuard.reset_configuration!`; `require "tmpdir"; p = File.join(Dir.tmpdir, "rg.jsonl")` then `configure { |c| c.add_reporter(RaceGuard::Reporters::FileReporter.new(p)) }` and `RaceGuard.report(...)`; `File.read(p)`. (Use `Dir.tmpdir`, not `Dir.mtmpdir`.)
5. **Production no-op** — `ENV["RACK_ENV"] = "production"`, re-add a `JsonReporter` to `$stdout`, run `report`; you should see no new output, then `ENV.delete("RACK_ENV")` and `RaceGuard.reset_configuration!`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
ruby script/smoke_db_lock_rmw.rb   # DB lock RMW + lock awareness (optional; from repo root)
rake   # RSpec + RuboCop
```

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md). For conduct expectations see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). To report a security issue, use [SECURITY.md](SECURITY.md) (do not use public issues). Release history: [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
