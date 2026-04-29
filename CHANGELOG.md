# Changelog

All notable changes to `soot_core` are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project adheres to semantic versioning.

## [Unreleased]

### Added
- `mix soot_core.install` now generates AshPostgres-backed consumer
  resource modules for all six soot_core resources (`Tenant`,
  `SerialScheme`, `ProductionBatch`, `Device`, `DeviceShadow`,
  `EnrollmentToken`) under `lib/<app>/` and registers them in
  `config/config.exs` under `:soot_core, <key>:`. The installer
  composes `ash_postgres.install` to wire the consumer's Repo and the
  `:ash_postgres` dep. The library's own concrete defaults stay on
  `Ash.DataLayer.Ets` for the soot_core test suite; consumer projects
  always boot against AshPostgres, which is mandatory in the soot
  stack.
