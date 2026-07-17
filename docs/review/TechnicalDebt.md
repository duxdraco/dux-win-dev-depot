# DevDepot — Technical Debt Report (Phase 2.5)

Ranked by priority. "Paid" items were resolved during this phase; the rest are
tracked for Phase 3+.

## Paid down this phase

- **TD-01 (was High): duplicated migrate/rollback logic.** Unified under one
  operation abstraction (`Do`/`Verify`/`Undo`). Resolved.
- **TD-02 (was High): non-transactional migration.** Now atomic with automatic
  rollback on failure. Resolved.
- **TD-03 (was High): rollback by scanning/manifest only.** Authoritative state
  DB with history. Resolved.
- **TD-04 (was Med): empty-array return unwrap → `$null.Count` crashes.** Audited
  every collection return; leading-comma idiom for function returns, plain arrays
  for property values. Resolved (regression-tested indirectly by the 33-check
  harness).
- **TD-05 (was Med): no capability/version gating.** Added. Resolved.

## Outstanding

| Id | Debt | Priority | Notes |
|----|------|:--------:|-------|
| TD-10 | Analyzer detectors (duplicate/unused/orphan/old) are unimplemented | High | Framework exists; needs Phase-3 providers + tool probes |
| TD-11 | Long-path (>260) & Unicode path test fixtures missing | High | Behaviour likely fine (robocopy) but unproven |
| TD-12 | CI pipeline on real PowerShell 7 + Pester 5 not yet wired | High | Local dev box is 5.1-only; shim is a stopgap |
| TD-13 | Provider descriptors are executable `.ps1` (trust/security) | Med | Consider signed or data-only (psd1/json) descriptors for community providers |
| TD-14 | Parallel `analyze` not implemented (only analyzed) | Med | Gate behind `-Parallel`; needs path-disjointness check |
| TD-15 | Tool-version detection is opt-in per provider (`VersionCommand`); none declared yet | Low | Populate for Phase-2 providers |
| TD-16 | Machine-scope config path not standardised (no default under %ProgramData%) | Low | Layer supported; default location TBD |
| TD-17 | `robocopy` is an external dependency with parsed exit codes | Low | Acceptable on Windows; abstracted behind `Move-DevDepotDirectory` |
| TD-18 | No concurrency lock preventing two DevDepot runs at once | Med | Add a lock file under `.state/` before mutating runs |
| TD-19 | Reports don't yet diff before/after across runs (state history unused in UI) | Low | History is captured; reporting on it is future work |

## Recommended next actions

1. Wire CI on PS7 (closes TD-12, de-risks everything).
2. Add path-edge-case fixtures (TD-11).
3. Add a `.state/lock` guard for concurrent-run safety (TD-18).
4. Decide the community-provider trust model (TD-13) before opening contributions.
