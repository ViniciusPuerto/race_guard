# Rails 8 Concurrency Demo Guide

This document explains how to run and validate the Dockerized Rails API demo in `demo/` that showcases `race_guard` features under concurrent workload.

## What this demo covers

- **Read-modify-write detection** on wallet balance updates.
- **Stock reservation contention** with DB constraints and locks.
- **Distributed execution guard** with `RaceGuard.distributed_once` + Redis.
- **Commit safety instrumentation** for enqueue/side-effect timing.

## Stack

- Rails 8 API
- PostgreSQL 16
- Redis 7
- Sidekiq 7
- `race_guard` loaded from local source (`gem "race_guard", path: ".."`).

## Start the demo

From repository root:

```bash
cd demo
make up
make db
make seed
```

Services:

- API: `http://localhost:3000`
- Postgres: `localhost:5433`
- Redis: `localhost:6379`

## Simulation commands

```bash
make simulate-wallet
make simulate-stock
make simulate-once
```

What each does:

- `simulate-wallet`: enqueues 20 `ConcurrentChargeJob` jobs.
- `simulate-stock`: enqueues 20 `StockReservationJob` jobs.
- `simulate-once`: enqueues 20 `OnceOnlySettlementJob` jobs for one `run_key`.

## How to prove `race_guard` is working

### 1) Confirm worker processing

```bash
docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml logs -f sidekiq api
```

You should see Sidekiq dequeue and execute jobs.

### 2) Confirm structured events are emitted

```bash
docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml exec api \
  bash -lc "tail -n 50 /app/demo/log/race_guard_events.jsonl"
```

Expected detector examples:

- `db_lock_auditor:read_modify_write`
- `commit_safety:*` (when those hooks trigger)

### 3) Validate DB-side outcomes

Wallet value:

```bash
docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml exec api \
  bundle exec rails runner "puts Wallet.find(1).balance_cents"
```

Stock + reservations:

```bash
docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml exec api \
  bundle exec rails runner "p({stock: Product.find(1).stock, reservations: Reservation.where(product_id: 1).count})"
```

Distributed once-run records:

```bash
docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml exec api \
  bundle exec rails runner "p BillingRun.order(created_at: :desc).limit(10).pluck(:run_key, :status)"
```

## Scenario-to-feature mapping

- **wallet_race**
  - Risk: read-modify-write lost update shape.
  - Feature: `db_lock_auditor` + `RaceGuard.protect`.
  - Proof: `db_lock_auditor:read_modify_write` events in JSONL.

- **stock_race**
  - Risk: concurrent decrements and duplicate reservation attempts.
  - Feature: transaction + row lock + unique index.
  - Proof: stable stock semantics and uniqueness preserved.

- **once_run**
  - Risk: duplicate multi-worker execution.
  - Feature: `distributed_guard` with Redis lock client.
  - Proof: only one active lock-holder path per `run_key` lock window.

## Troubleshooting

- **`Could not find gem 'race_guard' in source at '/'`**
  - Cause: wrong Docker build context.
  - Fix: build must include repo root (`docker-compose.yml` already configured).

- **`yaml.h not found` while installing gems**
  - Cause: missing `libyaml` headers in image.
  - Fix: `libyaml-dev` and `pkg-config` installed in Dockerfile.

- **`relation ... already exists` on wallet migration**
  - Cause: duplicate index creation (`t.references` + explicit `add_index`).
  - Fix: migration uses `index: false` on `t.references` and explicit unique index.

- **Docker volume error on `demo_bundle_cache` path exists**
  - Cause: stale/corrupt volume data.
  - Fix:
    ```bash
    docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml down -v
    docker volume rm demo_bundle_cache 2>/dev/null || true
    ```

- **No `race_guard_events.jsonl` created**
  - Cause: reporter initialized with path object instead of IO.
  - Fix: initializer opens file handle and passes IO to `JsonReporter`.

## Reset everything

```bash
docker compose -f /Users/viniciusporto/code/race_guard/demo/docker-compose.yml down -v
docker volume rm demo_bundle_cache 2>/dev/null || true
make up
make db
make seed
```
