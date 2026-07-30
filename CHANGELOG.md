# Changelog

All notable changes to DevDepot are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

DevDepot is developed and maintained by **Dux Draco**.

## [Unreleased]

### Added

- **8 new providers**, all derived from real-world migrations verified on a live machine:
  - `jetbrains` — JetBrains IDE config/plugins (`%APPDATA%\JetBrains`) and
    caches/indexes (`%LOCALAPPDATA%\JetBrains`).
  - `postman`, `tabnine` — application data and downloaded models.
  - `eclipse` — Eclipse p2 bundle pool (`~\.p2`).
  - `jdks` — IDE-downloaded JDKs (`~\.jdks`).
  - `user-local` — user-installed CLI tools (`~\.local`).
  - `wsl`, `docker` — **report-only**: they detect and report where WSL2
    distributions and the Docker Desktop data-root live (including whether they sit
    on the system drive), but never migrate automatically, because relocating them
    requires stopping services and would disrupt running containers.
- Documented manual WSL relocation procedure in
  [Troubleshooting](docs/Troubleshooting.md#moving-a-wsl-distribution).

### Known limitations

- Junctions created outside DevDepot (manually) are not recorded in the state
  database, so `rollback` cannot reverse them. `doctor` and `repair` work
  correctly against them. A migration performed by `install` from the start
  records state normally and remains fully reversible.
- Providers with no detectable command (e.g. `jetbrains`, `jdks`) whose source
  directory is absent are treated as "not installed" and skipped by `install`.
  Use `repair` to recreate a missing junction when the data already sits at the
  target.

## [0.1.0] - 2026-07-17

First usable release. Migrates developer caches, SDKs and package repositories off
the Windows system drive to a configurable root, safely and reversibly.

### Added

- **CLI** (`DevDepot.ps1` + wrappers): `analyze`, `install`, `doctor`, `repair`,
  `rollback`, `status`, `report`, `provider list|enable|disable|info`, `version`.
  All mutating commands support `-WhatIf`.
- **Provider filtering** via `--provider <id>` / `-Provider <id>` on `analyze`,
  `install` and `rollback`.
- **Grouped analyze output** distinguishing **Ready to migrate**,
  **Already optimized** and **Not installed**, with reclaimable-space total.
- **Per-provider verification summary** block after `analyze`/`install`.
- **Transactional migration engine**: each operation is applied, verified, and
  automatically rolled back (whole transaction) on any failure.
- **State database** (`.state/state.json` + history) as the authoritative record;
  `rollback` reads state rather than scanning Windows. Idempotent re-runs preserve
  the original baseline.
- **Verification** levels: `None`, `Stats` (default), `Hash`.
- **Safety levels**: `Safe` / `Conservative` / `Aggressive` / `Experimental`.
- **Provider metadata**: dependencies, conflicts, priority, `RequiresAdmin`,
  minimum PowerShell/Windows, with capability gating and dependency/conflict/cycle
  resolution.
- **Layered configuration**: defaults → machine → user → environment → CLI.
- **Structured logging**: human `.log` plus machine-readable `.jsonl`.
- **13 providers** across four ecosystems:
  - Java: Gradle, Maven, sbt/Coursier
  - Node.js: npm, pnpm, Yarn, Bun, Deno
  - .NET: NuGet
  - Python: pip, uv, Poetry, Conda
- **Reports** in JSON, Markdown and HTML.
- Documentation: README, Architecture, Providers, Developer/Contributing guides,
  Roadmap, Troubleshooting, FAQ, and the Phase-2.5 review set under `docs/review/`.

### Behaviour

- `install` **gracefully skips tools that are not installed** (no command on PATH
  and no real cache directory) instead of creating junctions for absent software.
- Junctions are preferred over symbolic links so no administrator rights are
  required for the default configuration.
- Nothing is hard-deleted; migrations use `robocopy` (copy-then-remove) and are
  verified before the source is replaced by a junction.

### Verified on a real machine

Migrated npm (3.9 GB) and pip (455 MB) off `C:` with functional verification
(cache relocated, tool still works, new downloads land on the new drive), plus
idempotent re-install and per-provider rollback. Providers already relocated by
their own tooling (e.g. pnpm's drive-local store, a custom Maven
`localRepository`) are reported as **Already optimized** rather than moved.

### Known limitations

- Requires **PowerShell 7.0+** (Windows only).
- Analyzer does not yet detect duplicate/unused SDKs or orphan caches.
- CI on real PowerShell 7 + Pester 5 is not yet wired (tracked for the next phase).
- Docker, WSL, IDEs and additional ecosystems are planned for Phase 3.

[Unreleased]: https://github.com/duxdraco/dux-win-dev-depot/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/duxdraco/dux-win-dev-depot/releases/tag/v0.1.0
