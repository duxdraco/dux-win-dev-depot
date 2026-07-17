# DevDepot — Migration Plan (Phase 2.5 → Phase 3)

This plan covers (a) migrating existing 0.1.0 users to the 0.2.0 architecture and
(b) the ordered work to close Phase 2.5 debt before Phase 3 features.

## A. User migration 0.1.0 → 0.2.0

1. Pull 0.2.0. No data migration needed — the on-disk layout of *migrated caches*
   is unchanged.
2. Re-run `pwsh -File .\DevDepot.ps1 install` (idempotent) to populate `.state/`.
   Nothing moves if already migrated; state is recorded from the current layout.
3. Use `rollback` (state-based) going forward; stop passing `-ManifestPath`.
4. Review new config keys (`verification`, `safetyLevel`) — defaults are safe.

## B. Engineering work order (gate to Phase 3)

Each item ends with: tests pass, idempotency verified, rollback verified,
migration safety verified, docs updated.

### B1 — Close release-blocking debt (do first)
- **CI on real PowerShell 7 + Pester 5** (TD-12). Run `tests/Invoke-Tests.ps1` in
  GitHub Actions on `windows-latest`. Blocks all releases.
- **Path edge-case fixtures** (TD-11, R11): >260-char paths, Unicode, spaces.
- **Concurrent-run lock** (TD-18): `.state/lock` acquired before mutating runs.

### B2 — Fault-injection test suite (area 12 remainder)
- Locked files (open handle) → move fails → transaction rolls back cleanly.
- Access denied (ACL) on source/target.
- Disk-full simulation (small VHD or quota) → verify no partial state.
- Junction loop / reparse cycle → hashing/stats must not hang (already skips
  reparse points; add a test).
- Simulated interruption: kill between operations → next run reconciles from state.

### B3 — Analyzer detectors (area 6)
Build on `Get-DevDepotDirectoryStats` + state DB:
- Orphan caches (in `root` but no owning provider/state entry).
- Extremely-old caches (mtime threshold, configurable).
- Duplicate/unused SDKs & JDKs, unused NuGet/Gradle/npm/pip caches.
- Docker images / WSL distros / Android SDKs — arrive **with** their Phase-3
  providers, which own the tool-specific probes.

### B4 — Provider trust model (TD-13, R14)
Decide before accepting community providers: signed descriptors, or a data-only
(`.psd1`/JSON) descriptor format with the imperative parts restricted to
first-party hooks.

### B5 — Concurrency (area 8)
Implement `analyze -Parallel` with per-provider path-disjointness verification.
Keep `install` sequential.

## C. Definition of done for Phase 2.5

- [x] Transactional migration with automatic rollback
- [x] State database with history; rollback consumes state
- [x] Provider metadata, capability gating, dependency/conflict/cycle resolution
- [x] Verification (Stats default, Hash opt-in)
- [x] Safety levels
- [x] Structured (JSONL) logging
- [x] Layered configuration
- [x] CLI subcommands incl. provider management
- [x] Expanded automated checks (33/33 in the shim harness) + Pester suites authored
- [ ] CI on real PS7 (B1) — **required before Phase 3**
- [ ] Path edge-case + fault-injection tests (B1/B2)

Phase 3 (Docker, WSL, IDEs, Android/Flutter) starts only after B1 is green.
