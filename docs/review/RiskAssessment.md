# DevDepot — Risk Assessment (Phase 2.5)

Likelihood × Impact, each Low/Med/High. Residual = after listed mitigation.

| # | Risk | Likelihood | Impact | Mitigation | Residual |
|---|------|:----------:|:------:|------------|:--------:|
| R1 | Data loss during move (crash/power loss mid-copy) | Low | High | `robocopy` copies before deleting source; move+verify in a transaction; source shell removed only after verification; state records the move for rollback | Low |
| R2 | Verification passes but data subtly corrupted | Low | High | `Stats` default catches count/byte drift; `Hash` mode catches content drift; mismatch fails the op and rolls back | Low |
| R3 | Partial migration leaves tools half-broken | Low | High | Transaction undoes committed ops in reverse on any failure (tested) | Low |
| R4 | Rollback cannot restore because state is lost/corrupt | Low | High | State archived to `.state/history/` on every save; `Merge` preserves the original baseline across re-runs | Low–Med |
| R5 | Env var / junction drift after external changes | Med | Med | `doctor` (Validate) detects drift; `repair` re-applies; `report` surfaces state vs live | Low |
| R6 | Provider migrates a path it shouldn't (system dir) | Low | High | `Test-DevDepotSafeSource/Target` refuse system/Program Files/drive-root/nested targets before any op | Low |
| R7 | Destructive future operation runs unintentionally | Med | High | Safety levels; destructive ops must declare `Aggressive`/`Experimental` and are gated by `config.safetyLevel` (default `Safe`) | Low |
| R8 | Machine-scope env change needs admin, fails silently | Med | Med | Capability gate (`RequiresAdmin`), user scope default, explicit warnings | Low |
| R9 | Concurrency race corrupts env/registry/state | Low | High | Migration is sequential by design (area 8); parallelism deferred | Low |
| R10 | Dependency cycle / missing prerequisite mis-orders run | Low | Med | Resolver reports cycles/missing deps; cycles logged as errors and surfaced in the report | Low |
| R11 | Long-path (>260) / Unicode path failures | Med | Med | robocopy handles long paths; **targeted tests deferred** (see MigrationPlan) | Med |
| R12 | Runs only validated via 5.1 shim, not real PS7 locally | Med | Med | Pester 5 suites authored for CI; shim strips only the version pragma; CI on PS7 required before release | Med |
| R13 | Hash verification too slow on huge caches | Med | Low | `Hash` is opt-in; default `Stats` is O(entries) | Low |
| R14 | Provider descriptor from third party runs arbitrary code | Med | Med | Descriptors are `.ps1` executed at load — **trust boundary**; document that providers are code, sign/review community providers | Med |

**Top residual risks to close before 1.0:** R11 (long/Unicode path fixtures),
R12 (CI on real PS7), R14 (provider trust model — consider a manifest-only,
non-executable descriptor format or signing).
