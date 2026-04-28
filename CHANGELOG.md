# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable.

## [Unreleased]

## [0.2.0] - 2026-04-27

### Added

- **Epic 10 — Distributed execution guard:** `RaceGuard.distributed_once` / `distributed_protect` with a pluggable `LockStore` (Redis via `SET … NX EX` and Lua compare-and-delete, or an in-memory store for tests); key builder, TTL/renewal, and structured `RaceGuard.report` events for claim, skip, release, renew, and configuration errors.
- Community documentation: contributing guidelines, code of conduct, security policy, and GitHub issue/PR templates.
- README: problem statement, quick start, architecture diagram, and Epic 10 usage; links to [`examples/`](examples/README.md).
- `examples/rmw_rails_app`: Rails sample with `db_lock_auditor:read_modify_write`, optional Sidekiq + Redis for distributed demos, and rake tasks.
- CONTRIBUTING: step-by-step notes for adding detectors and rules.

### Changed

- CONTRIBUTING expanded with concrete references to specs and core files for contributors.
- Development dependency on `redis` for distributed lock store tests and example apps.

## [0.1.0] - initial development

Pre-1.0 public API; see git history and [`README.md`](README.md) for capabilities.
