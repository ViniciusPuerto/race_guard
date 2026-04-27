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

---

### Task 5.1 — Model Scanner

- Parse:
  - `validates :field, uniqueness: true`

✅ **DoD**
- Extract field + scope

---

### Task 5.2 — Schema Analyzer

- Parse `schema.rb` or DB

✅ **DoD**
- Detect indexes accurately

---

### Task 5.3 — Comparison Engine

✅ **DoD**
- Detect missing indexes
- Output actionable fixes

---

### Task 5.4 — Rake Task

```bash
rake race_guard:index_integrity
```

✅ **DoD**
- Works in CI
- Returns non-zero exit on failure

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

---

### Task 6.2 — Thread Conflict Detection

- Track:
  - variable → thread ids

✅ **DoD**
- Detect concurrent writes
- Detect read/write overlap

---

### Task 6.3 — Mutex Awareness

- Inspect call stack for `Mutex#synchronize`

✅ **DoD**
- No warnings when protected

---

### Task 6.4 — Memoization Detection

Detect:
```ruby
@x ||= expensive_call
```

✅ **DoD**
- Flags only when multi-threaded context detected

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

---

# 🔥 What Makes This Project Stand Out (Important for OSS)

- First "race condition observability" tool in Ruby ecosystem
- Not just linting — **runtime-aware**
- Fully extensible rule engine

---