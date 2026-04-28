# race_guard Concurrency Demo (Rails API + Docker)

This demo is a standalone Rails API that showcases concurrency failures and safer alternatives using `race_guard`.

## Stack

- Rails API
- PostgreSQL (transactional state)
- Redis (Sidekiq + distributed locks)
- Sidekiq workers (concurrent execution)
- `race_guard` loaded from the repository source (`path: ".."`)

## Quick start

```bash
cd demo
make up
make db
make seed
```

API: `http://localhost:3000`

## Seeded entities

`make seed` creates:

- one `User`
- one `Wallet` with starting balance
- one `Product` with stock

## Endpoints

- `POST /wallets/:id/charge_naive`
  - Parameters: `amount_cents`
  - Demonstrates read-modify-write risk and commit safety events.
- `POST /wallets/:id/charge_safe`
  - Parameters: `amount_cents`
  - Uses row lock + `RaceGuard.after_commit` pattern.
- `POST /products/:id/reserve`
  - Parameters: `user_id`, `quantity`
  - Demonstrates stock decrement under transaction and lock.
- `POST /jobs/once_charge_run`
  - Parameters: `run_key`, `wallet_id`, `amount_cents`
  - Enqueues multiple jobs, guarded by `RaceGuard.distributed_once`.
- `POST /simulations/:scenario/run`
  - Scenarios: `wallet_race`, `stock_race`, `once_run`
  - Parameters vary by scenario (`times`, ids, amount/quantity).

## Scenario matrix

- **wallet_race**
  - Failure mode: read-modify-write lost updates
  - Feature: `db_lock_auditor` + `RaceGuard.protect`
  - Signal: events in `log/race_guard_events.jsonl`
- **stock_race**
  - Failure mode: concurrent reservation attempts
  - Feature: transaction + row lock + DB uniqueness
  - Signal: reservation uniqueness/stock behavior in logs and DB rows
- **once_run**
  - Failure mode: duplicate multi-worker execution
  - Feature: `distributed_guard` with Redis lock store
  - Signal: only one active settlement per `run_key` lock window
- **commit safety**
  - Failure mode: enqueue side effects before transaction commit
  - Feature: commit safety watchers + `RaceGuard.after_commit`
  - Signal: `commit_safety:*` events when unsafe patterns are triggered

## Useful commands

```bash
make logs
make simulate-wallet
make simulate-stock
make simulate-once
```

Tail race_guard events:

```bash
docker compose exec api bash -lc "tail -f log/race_guard_events.jsonl"
```

## Troubleshooting

- If gem install fails, rebuild images: `make down && make up`.
- If DB errors on first boot, run `make db` again after containers are healthy.
- If distributed lock behavior seems odd, verify Redis is reachable and `REDIS_URL` matches compose service name.