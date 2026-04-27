Nice—this is exactly the kind of problem that benefits from a spec-driven OSS approach. I’ll treat this like a real project backlog you could drop into GitHub Issues + Projects.

---

# 🧠 Project: `race_guard`
**Mission:** Detect race conditions in Ruby/Rails apps via static + runtime analysis, with an agnostic extension API.

---

# 📌 PRODUCT SPEC (v0.1)

## ✅ Core Principles
- Framework-agnostic (Rails support is a plugin layer, not a requirement)
- Safe-by-default (dev/test only unless explicitly enabled)
- Low false positives > high coverage
- Composable (users can wrap ANY code path)
- Zero required code changes (optional DSL enhances coverage)

---

# 🧩 EPICS & BACKLOG

---

## EPIC 1 — Core Engine & Configuration

### 🎯 Goal
Provide the backbone: config, lifecycle, instrumentation registry, reporting.

---

### Task 1.1 — Gem Skeleton
- Create gem structure (`bundle gem race_guard`)
- Add CI (GitHub Actions)
- Add RuboCop + RSpec

✅ **DoD**
- Gem installs locally
- `RaceGuard.configure {}` works
- CI passes

---

### Task 1.2 — Configuration System

```ruby
RaceGuard.configure do |c|
  c.enable :db_lock_auditor
  c.severity :warn
end
```

- Feature flags per detector
- Severity levels (`:info, :warn, :error, :raise`)
- Environment scoping

✅ **DoD**
- Config accessible globally
- Features toggleable at runtime
- Defaults documented

---

### Task 1.3 — Reporter System

- Logger output
- JSON formatter
- Pluggable reporters (file, webhook)

✅ **DoD**
- `RaceGuard.report(event)` works
- Supports multiple reporters
- Structured payload schema defined

---

### Task 1.4 — Context Engine (Thread-local state)

- Track:
  - current thread id
  - transaction state
  - protected blocks

✅ **DoD**
- `RaceGuard.context.current` returns state
- Thread-safe
- No memory leaks

---

## EPIC 2 — Agnostic Protection API (CORE DIFFERENTIATOR)

### 🎯 Goal
Allow users to wrap ANY code and get protection automatically.

---

### Task 2.1 — `RaceGuard.protect`

```ruby
RaceGuard.protect(:payment_flow) do
  # monitored
end
```

- Push context
- Activate detectors
- Capture events

✅ **DoD**
- Nested blocks supported
- Context name appears in reports

---

### Task 2.2 — Method Wrapping API

```ruby
RaceGuard.watch(MyService, :call)
```

- Monkey-patch method safely
- Preserve original behavior

✅ **DoD**
- Works with instance + class methods
- No double-wrapping
- Thread-safe

---

### Task 2.3 — Rule Engine (Extensibility)

```ruby
RaceGuard.define_rule(:no_side_effects_in_txn) do |rule|
  rule.detect { condition }
  rule.message { "..." }
end
```

✅ **DoD**
- Rules can register hooks
- Rules receive context + metadata
- Users can enable/disable rules

---

## EPIC 3 — Commit Safety Guard

### 🎯 Goal
Detect side-effects inside uncommitted transactions.

---

### Task 3.1 — Transaction Tracking

- Patch:
  - `ActiveRecord::Base.transaction`
- Maintain thread-local flag

✅ **DoD**
- Nested transactions handled
- Works with `requires_new: true`

---

### Task 3.2 — Built-in Interceptors

Support:
- ActiveJob (`perform_later`)
- ActionMailer
- HTTP (Net::HTTP, Faraday)

✅ **DoD**
- Each interceptor emits event
- Works without crashing app

---

### Task 3.3 — Custom Interceptors API

```ruby
config.watch_commit_safety :custom do |w|
  w.intercept(MyClient, :call)
end
```

✅ **DoD**
- Works for any class/method
- Supports multiple interceptors

---

### Task 3.4 — After Commit Helper

```ruby
RaceGuard.after_commit { ... }
```

✅ **DoD**
- Executes only after commit
- Falls back safely if no transaction

---

## EPIC 4 — DB Lock Auditor

### 🎯 Goal
Detect unsafe DB mutation patterns.

---

### Task 4.1 — Read-Modify-Write Detection

Detect:
```ruby
model.update(balance: model.balance - x)
```

Approach:
- Instrument `update`, `save`
- Track prior reads

✅ **DoD**
- Detects at runtime
- Low false positives

---

### Task 4.2 — Lock Awareness

- Detect presence of:
  - `with_lock`
  - `lock!`

✅ **DoD**
- No warnings when lock exists
- Handles nested locks

**Implementation (race_guard):** the same RMW detector (`db_lock_auditor:read_modify_write`) is skipped when a tracked row is written under a pessimistic `with_lock` block (per-record nested block depth) or after `lock!` in the same `transaction` scope as tracked on `RaceGuard.context` (transaction-scoped set cleared when the outermost AR transaction frame ends for the thread). See `lib/race_guard/db_lock_auditor/read_modify_write.rb`.

---

### Task 4.3 — SQL Atomic Detection

- Allow safe patterns:
```ruby
update_all("balance = balance - 1")
```

✅ **DoD**
- No false positives for atomic SQL

**Implementation (race_guard):** when tracked models execute atomic SQL via `ActiveRecord::Relation#update_all` (string / SQL literal updates), RaceGuard clears matching row read-journal entries for that relation scope so subsequent writes do not get stale read-modify-write warnings. See `lib/race_guard/db_lock_auditor/read_modify_write.rb`.

---

## EPIC 5 — Index Integrity Auditor (STATIC)

### 🎯 Goal
Prevent validation-only uniqueness.

**Pipeline:** model source scan (5.1) → index facts from `schema.rb` or DB (5.2) → compare validations to unique indexes (5.3) → `rake race_guard:index_integrity` in CI (5.4). Layers 5.1–5.3 are usable without booting a full request cycle; the rake task expects a Rails app layout so `Rails.root`, `db/schema.rb`, and `ActiveRecord` are available.

**Limitation:** inferred **table name** from `app/models/**/*.rb` paths is convention-based (`Admin::User` → `admin_users`). Custom `self.table_name` is not read in this epic; override support may come later.

---

### Task 5.1 — Model Scanner

- Parse:
  - `validates :field, uniqueness: true`

✅ **DoD**
- Extract field + scope

**Implementation (race_guard):** static scan via `Parser` on Ruby source; `require "race_guard/index_integrity/model_scanner"` then `RaceGuard::IndexIntegrity::ModelScanner.scan_source` / `scan_file` returns `UniquenessValidation` structs (`fields`, `scope`, `filename`). See `lib/race_guard/index_integrity/model_scanner.rb`.

---

### Task 5.2 — Schema Analyzer

- Parse `schema.rb` or DB

**Inputs:** default path `db/schema.rb` (callers pass absolute path); optional **from DB** via `ActiveRecord::Base.connection` when the connection is available (same index shape as file parsing).

**Outputs:** list of `IndexDefinition` values: `table` (symbol), `columns` (array of symbols, order preserved as in schema), `unique` (boolean), optional `name` (string). File parsing returns **only** `unique: true` indexes (non-unique and partial `where:` entries are omitted). `from_connection` returns only unique indexes as well.

**Rules:** collect `add_index` at file scope and inside `change` / `Schema.define` blocks; collect `t.index` inside `create_table` blocks; read `unique: true` and column array/string arguments. **Expression / partial** indexes (SQL fragments, `where:`) are skipped—they cannot be matched reliably to validation columns.

✅ **DoD**
- Detect indexes accurately (fixture-driven specs for Rails 7-style `schema.rb`; parity check against `connection.indexes` on a small in-memory SQLite schema where applicable).

**Implementation (race_guard):** `require "race_guard/index_integrity/schema_analyzer"` then `SchemaAnalyzer.parse_file` / `parse_source` / `from_connection` → `IndexDefinition` (`table`, `columns`, `unique`, `name`). Partial indexes (`where:`) are skipped. See `lib/race_guard/index_integrity/schema_analyzer.rb`.

---

### Task 5.3 — Comparison Engine

**Inputs:** `UniquenessValidation` list from the model scanner + `IndexDefinition` list from the schema analyzer (typically unique indexes only).

**Rule:** For each validation, build **required column set** = scope columns (nil → none; symbol → one; array → many) **plus** `fields`, as a **set** (order ignored). A validation is satisfied if **any** index on the inferred table has `unique: true` and its column set equals that required set. Multi-attribute `validates :a, :b, uniqueness:` implies one composite requirement on `[:a, :b]` plus scope columns.

**Outputs:** violations including source `filename`, inferred `table`, required columns, and an **actionable** suggested line: `add_index :table_name, [:col_a, :col_b], unique: true`.

✅ **DoD**
- Detect missing indexes
- Output actionable fixes

**Implementation (race_guard):** `require "race_guard/index_integrity/comparison_engine"` then `ComparisonEngine.missing_indexes(validations:, indexes:)` → `MissingIndexViolation` (`message`, `suggested_migration`). Table names are inferred from `app/models/…` paths via `TableInference`. See `lib/race_guard/index_integrity/comparison_engine.rb`.

---

### Task 5.4 — Rake Task

```bash
rake race_guard:index_integrity
```

**Behavior:** under `Rails.application`, glob `app/models/**/*.rb` (skip `app/models/concerns/` by default), run `ModelScanner.scan_file` on each file, load indexes from `db/schema.rb` via `SchemaAnalyzer.parse_file` or, if the file is missing, from `SchemaAnalyzer.from_connection(ActiveRecord::Base.connection)`; run the comparison engine; print a human-readable report to STDOUT; **exit 0** when there are no violations, **non-zero** when any violation exists. No interactive prompts—suitable for CI (e.g. `RAILS_ENV=test` with a checked-in `schema.rb`).

✅ **DoD**
- Works in CI
- Returns non-zero exit on failure

**Implementation (race_guard):** `RaceGuard::Railtie` loads `lib/tasks/race_guard/index_integrity.rake` when `Rails::Railtie` is defined (`require "race_guard"` after Rails in the app). Task `race_guard:index_integrity` runs `IndexIntegrity::Runner.exit_code_for(Rails.root)` and `exit(1)` on violations. See `lib/race_guard/railtie.rb` and `lib/race_guard/index_integrity/runner.rb`.

---

## EPIC 6 — Shared State / CVar Watcher

### 🎯 Goal
Detect unsafe shared memory usage.

---

### Task 6.1 — TracePoint Setup

- Listen to:
  - `:cvasgn`, `:gvasgn`

✅ **DoD**
- No major performance degradation
- Toggleable

**Implementation (race_guard):** `require "race_guard/shared_state"` (via `race_guard`). Opt in with `RaceGuard.configure { |c| c.enable(:shared_state_watcher) }`; `configure` runs `MemoRegistry.sync_from_configuration!` then `TracePoint.sync_with_configuration!`; `reset_configuration!` calls `TracePoint.uninstall!` (which resets shared-state modules). The listener attempts `TracePoint.new(:cvasgn, :gvasgn)` and invokes `Watcher.handle_tracepoint` before the optional `event_sink`. **CRuby 3.x** public TracePoint does not accept those events (`ArgumentError`); the gem then **does not install** a fallback global `:c_call` trace (that would dominate CPU). A **one-time `Kernel.warn`** documents the gap until MRI exposes assignment events. See `lib/race_guard/shared_state/trace_point.rb`.

---

### Task 6.2 — Thread Conflict Detection

- Track:
  - variable → thread ids

✅ **DoD**
- Detect concurrent writes
- Detect read/write overlap

**Implementation (race_guard):** `RaceGuard::SharedState::Watcher` normalizes TracePoint payloads to `AccessEvent` and feeds `RaceGuard::SharedState::ConflictTracker`. **Concurrent unprotected writes** from two different logical threads on the same key emit once per key until `reset!` (uninstall clears state). **Read/write overlap** is detected when `:read` and `:write` events from different threads interleave without a mutex barrier; MRI does not expose cvar/gvar **read** TracePoint events today, so reads are only present when injected (tests) or when a future engine exposes them. Without reads, the assign-only subset is still covered by concurrent-write detection. Severity: `RaceGuard.configuration.severity_for(:'shared_state:conflict')`. See `lib/race_guard/shared_state/watcher.rb` and `lib/race_guard/shared_state/conflict_tracker.rb`.

---

### Task 6.3 — Mutex Awareness

- Inspect call stack for `Mutex#synchronize`

✅ **DoD**
- No warnings when protected

**Implementation (race_guard):** `RaceGuard::SharedState::MutexStack.mutex_protected?` scans `caller_locations` for frames whose label matches MRI’s `Thread::Mutex#synchronize` (and falls back to basename `mutex.rb` + `synchronize` labels). The watcher passes this flag into the conflict tracker so protected accesses clear cross-thread state without emitting. Heuristic only; stack shapes can differ across Ruby builds. See `lib/race_guard/shared_state/mutex_stack.rb`.

---

### Task 6.4 — Memoization Detection

Detect:
```ruby
@x ||= expensive_call
```

✅ **DoD**
- Flags only when multi-threaded context detected

**Implementation (race_guard):** Opt in with `RaceGuard.configure { |c| c.shared_state_memo_globs('lib/**/*.rb') }` (empty default: no memo scan). `MemoScanner` uses the **parser** gem to find `@ivar ||= rhs` (`:or_asgn` + `:ivasgn`). When `:shared_state_watcher` is enabled and globs are non-empty, a lightweight `TracePoint.new(:thread_begin)` marks multi-threaded mode on non-main threads; `MemoRegistry` then emits **one** `RaceGuard.report` per site (`detector`: `shared_state:memoization`, severity `severity_for(:'shared_state:memoization')`). No reports while only `Thread.main` runs. See `lib/race_guard/shared_state/memo_scanner.rb`, `memo_registry.rb`, and `trace_point.rb` (`install_thread_begin_unlocked!`).

---

## EPIC 7 — Reporting & Developer Experience

---

### Task 7.1 — Human-readable Logs

✅ **DoD**
- Clear message
- File + line number
- Suggested fix

---

### Task 7.2 — JSON Output

✅ **DoD**
- Machine-readable schema
- Stable format

---

### Task 7.3 — Severity Handling

- `:raise` should crash in test

✅ **DoD**
- Works with RSpec

---

## EPIC 8 — Rails Integration Layer

---

### Task 8.1 — Railtie

✅ **DoD**
- Auto-load in Rails
- Config via initializer

---

### Task 8.2 — Environment Awareness

✅ **DoD**
- Disabled in production by default

---

## EPIC 9 — OSS Readiness

---

### Task 9.1 — README

Must include:
- Problem explanation
- Quick start
- Examples
- Architecture diagram

✅ **DoD**
- New user runs gem in <5 min

**In progress** — quick start and API examples are in the repo README; architecture diagram and explicit “why race_guard” blurb TBD. README links to contributing, CoC, security, changelog.

---

### Task 9.2 — Contribution Guide

**In progress** — `CONTRIBUTING.md` (principles, dev commands, extension pointers, changelog expectation), `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` (vulnerability reporting), and `.github/ISSUE_TEMPLATE` + `PULL_REQUEST_TEMPLATE.md`.

✅ **DoD**
- Explains:
  - how to add detector
  - how to write rule

---

### Task 9.3 — Example App

- Rails demo app with intentional race conditions

✅ **DoD**
- Reproducible issues
- Shows gem catching them

---

### Task 9.4 — Versioning & Releases

**In progress** — `CHANGELOG.md` (Keep a Changelog, `[Unreleased]` + `0.1.0` placeholder); follow SemVer at release time; gem version in `lib/race_guard/version.rb`.

✅ **DoD**
- Semantic versioning
- Changelog maintained

---

## EPIC 10 — Distributed Execution Guard

### 🎯 Goal
Provide a **Redis-backed Ruby block wrapper** so only one execution proceeds across **threads, processes, and servers** when the same logical work is triggered from many places (e.g. **multi-server cron**, **Sidekiq** schedules or duplicate enqueues, overlapping rake tasks). Same product class as [`race_block`](https://github.com/joeyparis/race_block)—*multiple servers run the same cron jobs, but only one should execute a given job*—aligned with RaceGuard’s **configuration, severity, and reporting** (EPIC 1, EPIC 7), not a verbatim port of `race_block`’s sleep-then-verify flow.

**Principles:**
- Prefer **atomic Redis claims** (e.g. `SET key token NX EX ttl`) for mutual exclusion; avoid wall-clock **sleep** as the primary correctness mechanism under skew or slow networks.
- **Owner token** + **TTL** for crash safety; optional **compare-and-delete** on release.
- **Opt-in for production** consistent with EPIC 8 (no surprise Redis traffic in prod unless enabled).

---

### Task 10.1 — Block wrapper API

```ruby
RaceGuard.distributed_once("cron:daily_report", ttl: 300) { ... }
# or
RaceGuard.distributed_protect(:export_job, resource: "tenant_#{id}", ttl: 120) { ... }
```

- Stable string/symbol **namespace** plus optional **resource** segment for composed lock keys (document key format; avoid unbounded cardinality from raw user input—hash or segment length limits in implementation notes).
- **On skip** (lost the race): configurable behavior—no-op (block not run), return a sentinel / `nil`, or raise when severity / feature flags allow.
- **Re-entrancy:** define behavior when the same process/thread holds the same logical key (e.g. allow nested calls with refcount vs. second call skips); document chosen semantics.

✅ **DoD**
- Public API documented and gated via `RaceGuard.configure` (feature flag + Redis client hook).
- Multi-server cron and Sidekiq duplicate-enqueue scenarios appear in examples or README pointer from this epic.

---

### Task 10.2 — Redis adapter and claim semantics

- **Claim:** set key to an opaque **owner token** only if absent (`NX`), with **TTL** ≥ worst-case block duration + configurable margin.
- **Renew (optional):** extend TTL for long-running blocks only when the stored value still equals the owner token (Lua script or documented atomic pattern).
- **Release:** best-effort **compare-and-delete** (delete only if value matches owner token) so a slow loser cannot delete the winner’s key after expiry races.
- **Crash / partition:** TTL guarantees the lock eventually clears; document **at-most-one concurrent runner** vs **job idempotency** (retries may still run work twice without domain-level dedupe).
- Pluggable **`LockStore`** interface with Redis as the default adapter; accept a user-configured Redis client (e.g. `redis` gem) to match app connection pools.

✅ **DoD**
- Claim, renew, release, and TTL-expiry semantics documented in one place.
- No requirement on fixed `sleep_delay`-style leader election for correctness.

---

### Task 10.3 — Sidekiq and server integration

- **Sidekiq:** documented pattern or optional helper/middleware to guard `perform` for scheduled, recurring, or fan-out-prone workers (same logical `jid`/argument class of work).
- **Cron / duplicate triggers:** same API from rake tasks, systemd timers, `whenever`, or duplicate app-server cron—one winner across the fleet.
- **Scope:** integration is **opt-in**; Sidekiq is not a hard gem dependency of `race_guard` core (optional require / railtie hook).

✅ **DoD**
- At least one concrete Sidekiq + one cron-oriented example (specs or README) linked from this epic.
- Clear statement that distributed guard **serializes concurrent attempts** but does not replace **idempotency keys** or Sidekiq’s own uniqueness features where those are preferable.

---

### Task 10.4 — Observability and reporting

- Emit structured events: `claimed`, `skipped`, `released`, `renewed`, and configuration errors (e.g. missing Redis when feature enabled).
- Events include lock **name**, **owner token** (or hash for logs), **ttl**, and **caller context** where safe.
- Integrate with EPIC 7 reporters; respect EPIC 1 **severity** (e.g. warn vs raise when Redis is unreachable—explicit default documented).

✅ **DoD**
- Machine-readable fields stable enough for log aggregation.
- No silent no-op when Redis is required but misconfigured, unless explicitly configured to degrade silently.

---

### Task 10.5 — Test strategy for distributed guard

- **Unit:** in-memory fake `LockStore` for API, key composition, skip vs run, and re-entrancy rules.
- **Contract:** Redis `SET NX EX` behavior (CI with `redis-server` or documented stub that asserts the same command shape).
- **Concurrency:** N threads or forked processes racing on one key—**exactly one** body execution (or documented skip path) under test timeouts.

✅ **DoD**
- Tests run in default CI matrix without flaky timing under normal load (bounded waits, retry limits).
- Documented mitigations for TTL-too-short (work killed mid-flight) and Redis unavailability.

---

# 📊 NON-FUNCTIONAL REQUIREMENTS

- Overhead < 10% in dev/test
- No production impact unless enabled
- Thread-safe
- Ruby 3.x compatible

---

# 🧪 TEST STRATEGY

- Unit tests per detector
- Integration tests with Rails dummy app
- Concurrency tests (threads)
- False-positive benchmarks

---

# 🚀 MVP CUT (Realistically)

If you want a strong v0.1:

1. ✅ Core Engine
2. ✅ Commit Safety Guard
3. ✅ Index Integrity
4. ✅ Basic Protect API

Then iterate toward:
- DB Lock Auditor
- CVar Watcher
- Distributed Execution Guard (EPIC 10)

---

# 🔥 What Makes This Project Stand Out (Important for OSS)

- First "race condition observability" tool in Ruby ecosystem
- Not just linting — **runtime-aware**
- Fully extensible rule engine

---