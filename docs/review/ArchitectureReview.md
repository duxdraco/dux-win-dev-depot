# DevDepot — Phase 2.5 Architecture Review

**Scope:** critical review of Phase 1–2, with refactoring applied where a better
architecture exists. **Verdict legend:** ✅ implemented this phase · 🟡 partially
implemented / framework in place · ⏸️ deliberately deferred with rationale.

This document walks the 14 review areas. Companion deliverables:
[RiskAssessment](RiskAssessment.md), [TechnicalDebt](TechnicalDebt.md),
[BreakingChanges](BreakingChanges.md), [MigrationPlan](MigrationPlan.md).

---

## 1. Provider engine review ✅

**Findings (Phase 2):** the declarative descriptor was sound but thin. It could
not express prerequisites, ordering, conflicts, or environment requirements, and
the seven actions mixed "what" (data) with "how" (imperative loop in `Migrate`).

**Decisions & changes:**

- **Can every future provider fit?** Mostly. Declarative mappings cover the ~90%
  case (cache dir + env var + junction). The `Hooks` escape hatch covers the
  imperative 10% (Docker data-root, WSL VHDX). We validated a hook fully replaces
  any single action. **Kept**, now documented as the extension contract.
- **Are the 7 actions sufficient?** Yes, with one correction: `Rollback` is no
  longer a per-provider action driven by scanning — it is driven by the **state
  database** (area 3). Provider-level `Rollback` remains available via hook for
  exotic tools.
- **Dependencies / conflicts / prerequisites / supported versions** — added via
  provider **Metadata** (area 4) plus a resolver:
  `Resolve-DevDepotProviderOrder` performs a stable topological sort
  (dependencies first, then `Priority`), and reports conflicts, missing
  dependencies and cycles. `Test-DevDepotProviderCapable` gates on
  `MinimumPowerShell`, `MinimumWindows` and `RequiresAdmin`.
- **Duplicated behavior** — the old `Migrate` duplicated move/env/junction logic
  and its inverse lived separately in rollback. Both now share one **operation**
  abstraction (area 2), so do/undo/verify are defined once per operation type.

## 2. Transaction engine ✅

`modules/DevDepot.Transaction.psm1`. Migration is now transactional. Each unit of
work is an **operation** with `Do` / `Verify` / `Undo`. `Invoke-DevDepotTransaction`
applies then verifies each operation; on any failure it undoes the failing
operation and all previously-committed operations **in reverse order**, so no run
leaves a partially-migrated state. Verified against a forced-failure test
(committed env var is proven to be undone).

Mapping to the requested API: `Begin` = build op list + safety gate; `Move` /
`Configure` / `CreateJunction` = `New-DevDepot{Move,EnvVar,Junction}Operation`;
`Verify` = per-op `Verify` + engine gate; `Commit` = persist to state DB;
`Rollback` = reverse `Undo`.

## 3. State database ✅

`modules/DevDepot.State.psm1` → `.state/state.json` + `.state/history/`. Records
per provider: operations (move/env/junction with original `previousValue`),
provider version, tool version, timestamps, status. **Rollback reads state, not
Windows.** Every save archives the prior state to `history/`.

Non-obvious correctness fix found in review: re-running `install` must not
overwrite the recorded baseline (which would lose the original `Move` record and
capture an already-modified `previousValue`). `Merge-DevDepotOperations` keeps the
**original** record on key collision and appends only genuinely new operations.
Verified by the idempotency + rollback tests.

## 4. Provider metadata ✅

`Get-DevDepotProviderMetadata` merges a descriptor's `Metadata`/`Version` over
defaults, so old descriptors keep working (non-breaking to author). Fields:
`Dependencies`, `Conflicts`, `Priority`, `RequiresAdmin`, `MinimumPowerShell`,
`MinimumWindows`, `SupportsRollback/Analyze/Migrate`, `Version`.

## 5. Migration verification ✅

`modules/DevDepot.Verify.psm1` with three levels (config `verification`):
`None` / `Stats` (file count, dir count, bytes — default) / `Hash`
(order-independent SHA-256 over `relpath:size:filehash`). The `Move` operation
captures source stats/hash before moving and verifies the destination after;
a mismatch **fails the operation**, which rolls back the transaction. Junction
target and env-var value are verified by their operations. `Hash` is opt-in
because it is O(bytes) and impractical to force on multi-GB caches.

## 6. Analyzer improvements 🟡

**Framework implemented:** accurate size/stat collection
(`Get-DevDepotDirectoryStats`), reparse-point/junction validity checks, and the
state DB (enables orphan/duplicate reasoning). **Detectors deferred (⏸️ Phase 3):**
duplicate/unused SDKs & JDKs, unused Docker images / WSL distros / Android SDKs,
extremely-old caches. Rationale: most of these require the Phase-3 providers
(Docker, WSL, Android) and tool-specific probes that do not exist yet; building
detectors now would be speculative. Tracked in [MigrationPlan](MigrationPlan.md).

## 7. Safety improvements ✅

Four levels — `Safe` < `Conservative` < `Aggressive` < `Experimental`. Each
mapping/operation declares a `SafetyLevel` (default `Safe`); the transaction runs
an operation only if its level is at or below the configured ceiling
(`config.safetyLevel`). Verified: an `Aggressive` op is skipped under a `Safe`
ceiling. This gives destructive future operations (e.g. pruning orphan caches) a
principled opt-in.

## 8. Concurrency ⏸️ (analyzed; scoped decision)

**Analysis:** `analyze` is read-only and embarrassingly parallel across
providers — a clear future win via `ForEach-Object -Parallel`. `install` mutates
**process-global** state (environment variables, registry, the single
`state.json`) and shares the destination root; parallelizing it invites env/registry
races and state-file write contention for little wall-clock gain (work is I/O-bound
on one disk pair). **Decision:** keep migration **sequential and dependency-ordered**;
parallelism is reserved for `analyze` and gated behind an explicit future
`-Parallel` switch with per-provider path-disjointness checks. Documented rather
than implemented to avoid shipping a race.

## 9. Logging ✅

`modules/DevDepot.Logger.psm1` now writes a machine-readable **JSONL** sink
(`<cmd>-<ts>.jsonl`) alongside the human log, and exposes `.Event(level, message,
data)` for structured records. Levels Trace→Error unchanged. The CLI emits a
structured startup event (root/strategy/safety/verification/config-sources).

## 10. CLI review ✅

`DevDepot.ps1` now supports:
`analyze | install | doctor | repair | rollback | status | report` and
`provider list | enable <id> | disable <id> | info <id>`. `provider enable/disable`
persists to the user `config.json`. `report` renders current state + live
validation. All mutating commands honor `-WhatIf`.

## 11. Configuration review ✅

`Import-DevDepotLayeredConfig` merges, lowest→highest:
**defaults → machine config → user config → environment variables → CLI overrides**.
Environment layer maps `DEVDEPOT_ROOT`, `DEVDEPOT_LINKSTRATEGY`,
`DEVDEPOT_ENVVARSCOPE`, `DEVDEPOT_LOGLEVEL`, `DEVDEPOT_VERIFICATION`,
`DEVDEPOT_SAFETYLEVEL`. Resolved config carries a `configSources` audit trail
(shown in `status`). Verified: CLI beats environment.

## 12. Testing review 🟡

**Added and passing** (unit/integration + a 33-check end-to-end harness):
transaction rollback-on-failure, verification mismatch, dependency ordering,
priority ordering, conflict detection, missing-dependency detection, cycle
detection, capability gating, safety gating, layered-config precedence, repeated
install (idempotency), repeated/again rollback, state round-trip, hash
verification.

**Deferred (⏸️, tracked):** OS-level fault injection that cannot be simulated
deterministically in CI without elevation/special mounts — disk-full, network
drives, locked files (partially: we handle robocopy failure), junction loops,
long-path (>260) and Unicode paths (need targeted fixtures), true power-failure.
"Interrupted migration" and "partial failure" **are** covered logically by the
transaction rollback test. See [MigrationPlan](MigrationPlan.md) §Testing.

**Environment caveat:** the developer machine has only Windows PowerShell 5.1
(no PS7, Pester 3.4). The Pester 5 suites are authored for CI; local validation
runs the same module code via a shim that strips only the `#Requires -Version 7.0`
pragma. 33/33 checks pass.

## 13. Documentation review ✅ (updated this phase)

`Architecture.md` updated with the transaction/state/verification/safety/metadata
layers and a new diagram; `Providers.md` documents metadata; `Roadmap.md` marks
Phase 2.5. These review docs are new.

## 14. Deliverables ✅

This report + [RiskAssessment](RiskAssessment.md) +
[TechnicalDebt](TechnicalDebt.md) + [BreakingChanges](BreakingChanges.md) +
[MigrationPlan](MigrationPlan.md).

---

## Summary of new modules

| Module | Responsibility |
|--------|----------------|
| `DevDepot.Verify.psm1` | Directory stats, content hash, comparison |
| `DevDepot.State.psm1` | State database, history, operation merge |
| `DevDepot.Transaction.psm1` | Operations (Do/Verify/Undo), atomic transaction, safety gate |

Engine (`DevDepot.Provider.psm1`) gained metadata resolution, capability gating,
dependency/conflict/cycle resolution, and a transactional `Migrate`. Logger,
Config, Rollback and the CLI were extended as above.
