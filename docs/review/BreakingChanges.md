# DevDepot — Breaking Changes Report (Phase 2.5)

Version 0.1.0 → 0.2.0. DevDepot is pre-1.0, so breaking changes are acceptable
now; this documents them for anyone who tried 0.1.0.

## CLI

- **`rollback -ManifestPath <path>` removed.** Rollback now uses the state
  database automatically. Use `rollback` (all providers) or `rollback -Provider
  <id>`. *Migration:* drop the `-ManifestPath` argument.
- **New subcommands:** `report`, and `provider list|enable|disable|info`. The old
  top-level `list` still works (aliased to `provider list`).
- **New options:** `-SafetyLevel`, `-Verification`, `-MachineConfig`, positional
  `Arg1`/`Arg2` for `provider`.

## Configuration

- **New keys** `verification` (`None|Stats|Hash`, default `Stats`) and
  `safetyLevel` (`Safe|Conservative|Aggressive|Experimental`, default `Safe`).
  Old config files remain valid (defaults fill the gaps).
- **New precedence:** environment variables (`DEVDEPOT_*`) and CLI now override
  file config. If you set these env vars for other reasons, they will influence
  DevDepot. *Migration:* unset unintended `DEVDEPOT_*` variables.

## Provider descriptor

- **Additive, non-breaking.** New optional `Version` and `Metadata`
  (`Dependencies`, `Conflicts`, `Priority`, `RequiresAdmin`, `MinimumPowerShell`,
  `MinimumWindows`, `Supports*`) and per-mapping `SafetyLevel`. Descriptors from
  0.1.0 load unchanged (defaults applied).
- **Behavioural:** a provider whose `MinimumPowerShell`/`MinimumWindows` exceeds
  the host, or `RequiresAdmin` without elevation, is now **skipped** by `install`
  (was: attempted). Defaults (`7.0` / `10.0.0` / not-admin) match Phase-2 assumptions.

## State / on-disk

- **New `.state/` directory** at the repo root (git-ignored) is now the source of
  truth for rollback. Per-run `backups/manifest-*.json` are still written by the
  Backup module but are **no longer used by `rollback`**. *Migration:* a machine
  migrated with 0.1.0 has no `.state/`; re-run `install` (idempotent) to populate
  state before relying on the new `rollback`.

## Module API (for embedders)

- `New-DevDepotContext` gained `-State`, `-PowerShellVersion`, `-WindowsVersion`.
- `Invoke-EngineMigrate` now routes through `Invoke-DevDepotTransaction`; the
  `Migrate` result `Details` shape changed (`Committed`, `RolledBack`, `Skipped`,
  `Warnings` instead of `Actions`).
- New exported functions across `Verify`, `State`, `Transaction`, and the engine
  (metadata/capability/ordering). See module `Export-ModuleMember` lists.
