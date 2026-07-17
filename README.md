# DevDepot

**Move developer caches, SDKs and package repositories off your Windows system
drive — safely, idempotently, and reversibly.**

DevDepot relocates the large, regenerable data that development tools scatter
across `C:` (npm/NuGet/Gradle/pip caches, `.m2`, Coursier, …) to a single
consolidated root such as `D:\DevDepot`, keeping your system drive clean while
preserving full tool compatibility.

> Status: **v0.1.0 — first usable release.** 13 Java/Node/.NET/Python cache
> providers, transactional migration, state-based rollback, verification and
> safety levels. Docker/WSL/IDEs come in Phase 3. See
> [CHANGELOG](CHANGELOG.md) and the [architecture review](docs/review/ArchitectureReview.md).

---

## Why

- **Reclaim system-drive space** without uninstalling anything.
- **Compatibility first** — tools keep working because DevDepot uses each tool's
  official redirection (environment variable) *and* a filesystem junction at the
  original location. Nothing needs to "know" about DevDepot.
- **Safe & reversible** — every change is recorded in the state database; `rollback`
  puts everything back.

## Requirements

- **PowerShell 7.0+** (`pwsh`). Windows PowerShell 5.1 is *not* supported.
- Windows 10/11.
- No administrator rights required for the default strategy (directory junctions
  and user-scope environment variables). Machine-scope changes need elevation.

## Quick start

```powershell
# 1. See what could be moved and how much space you'd reclaim (read-only):
pwsh -File .\DevDepot.ps1 analyze

# 2. Preview the migration without changing anything:
pwsh -File .\DevDepot.ps1 install -WhatIf

# 3. Do it:
pwsh -File .\DevDepot.ps1 install

# 4. Check health any time:
pwsh -File .\DevDepot.ps1 doctor

# 5. Undo everything (or one provider):
pwsh -File .\DevDepot.ps1 rollback
pwsh -File .\DevDepot.ps1 rollback --provider npm
```

Convenience wrappers exist for each command: `.\analyze.ps1`, `.\install.ps1`,
`.\doctor.ps1`, `.\repair.ps1`, `.\rollback.ps1`, `.\status.ps1`.

## Commands

| Command    | What it does                                                        |
|------------|---------------------------------------------------------------------|
| `analyze`  | Detects tools, measures cache sizes, groups them (ready / optimized / not installed). Read-only. |
| `install`  | Migrates installed providers transactionally. Idempotent. Records state for rollback. |
| `doctor`   | Diagnoses broken junctions, missing/incorrect env vars, drift.      |
| `repair`   | Fixes issues found by `doctor`.                                     |
| `rollback` | Reverses migrations from the state database (all or `--provider <id>`). |
| `status`   | Shows current configuration and per-provider health.               |
| `report`   | Regenerates reports from the current state.                         |
| `provider` | `list` / `enable <id>` / `disable <id>` / `info <id>`.              |

Every mutating command supports `-WhatIf` for a dry run, and `--provider <id>`
(or `-Provider <id>`) to target a single provider.

## Example output

`DevDepot analyze` groups everything it finds:

```text
DevDepot analyze
  Root: E:\00 DevDepot

READY TO MIGRATE
  npm            3.9 GB   C:\Users\me\AppData\Local\npm-cache
  pip          455.2 MB   C:\Users\me\AppData\Local\pip\Cache

ALREADY OPTIMIZED
  Gradle, Maven, NuGet, uv

NOT INSTALLED
  sbt / Coursier, Bun, Deno, Yarn, Conda, Poetry

Reclaimable from system drive: 4.4 GB
```

`DevDepot install` prints a verification block per provider:

```text
========================================

npm

Current:
C:\Users\me\AppData\Local\npm-cache

New:
E:\00 DevDepot\node\npm-cache

Status:
SUCCESS

Space moved:
3.9 GB

Verification:
PASS

========================================
```

## Configuration

Copy [`config/config.example.json`](config/config.example.json) to
`config/config.json` and edit. See [docs/Architecture.md](docs/Architecture.md#configuration)
for every option.

```json
{
  "root": "D:\\DevDepot",
  "linkStrategy": "Both",
  "envVarScope": "User",
  "providers": { "docker": false },
  "exclude": []
}
```

- `linkStrategy`: `EnvVar` (redirect via env var only), `Junction` (junction
  only), or `Both` (default — most compatible).
- Unlisted providers are **enabled by default**, so new providers work without
  touching your config. Disable one with `"providers": { "id": false }` or via
  `exclude`.

## Project layout

```
DevDepot.ps1        Main CLI dispatcher
install.ps1 …       Thin command wrappers
config/             Default + example configuration
modules/            Core modules (logging, migration, junction, rollback, …)
providers/          One declarative *.provider.ps1 per technology
reports/            Generated JSON/Markdown/HTML reports (git-ignored)
logs/               Timestamped run logs, human + JSONL (git-ignored)
.state/             State database + history for rollback (git-ignored)
tests/              Pester 5 unit + integration + hardening tests
docs/               Architecture, provider guide, contributing, roadmap, FAQ
```

## Documentation

- [Architecture](docs/Architecture.md)
- [Providers](docs/Providers.md)
- [Developer guide](docs/DeveloperGuide.md)
- [Contributing](docs/Contributing.md)
- [Roadmap](docs/Roadmap.md)
- [Changelog](CHANGELOG.md)
- [Troubleshooting](docs/Troubleshooting.md)
- [FAQ](docs/FAQ.md)
- Phase 2.5 review: [Architecture Review](docs/review/ArchitectureReview.md) ·
  [Risk](docs/review/RiskAssessment.md) · [Tech Debt](docs/review/TechnicalDebt.md) ·
  [Breaking Changes](docs/review/BreakingChanges.md) · [Migration Plan](docs/review/MigrationPlan.md)

## Safety model

DevDepot never deletes user data. Migrations move data with `robocopy`, verify
the move (file/byte counts, optionally content hash), then place a junction at the
original path. Sources inside the Windows directory, Program Files or drive roots
are refused. Every reversible action is recorded in the state database
(`.state/state.json`, with history), and any operation failure rolls back the whole
transaction. See [docs/Architecture.md](docs/Architecture.md#safety) for details.

## License

MIT — see [LICENSE](LICENSE).
