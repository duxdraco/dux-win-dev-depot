# DevDepot

**Move developer caches, SDKs and package repositories off your Windows system
drive — safely, idempotently, and reversibly.**

DevDepot relocates the large, regenerable data that development tools scatter
across `C:` (npm/NuGet/Gradle/pip caches, `.m2`, Coursier, …) to a single
consolidated root such as `D:\DevDepot`, keeping your system drive clean while
preserving full tool compatibility.

> Status: **Phase 1–2 complete** (core architecture + Java/Node/.NET/Python
> ecosystems). See [docs/Roadmap.md](docs/Roadmap.md) for what's next.

---

## Why

- **Reclaim system-drive space** without uninstalling anything.
- **Compatibility first** — tools keep working because DevDepot uses each tool's
  official redirection (environment variable) *and* a filesystem junction at the
  original location. Nothing needs to "know" about DevDepot.
- **Safe & reversible** — every change is recorded in a manifest; `rollback`
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

# 5. Undo the last run:
pwsh -File .\DevDepot.ps1 rollback -ManifestPath .\backups
```

Convenience wrappers exist for each command: `.\analyze.ps1`, `.\install.ps1`,
`.\doctor.ps1`, `.\repair.ps1`, `.\rollback.ps1`, `.\status.ps1`.

## Commands

| Command    | What it does                                                        |
|------------|---------------------------------------------------------------------|
| `analyze`  | Detects tools, measures cache sizes, estimates reclaimable space, writes reports. Read-only. |
| `install`  | Migrates all enabled providers. Idempotent. Writes a rollback manifest. |
| `doctor`   | Diagnoses broken junctions, missing/incorrect env vars, drift.      |
| `repair`   | Fixes issues found by `doctor`.                                     |
| `rollback` | Reverses a run using its manifest.                                  |
| `status`   | Shows current configuration and per-provider health.               |
| `list`     | Lists all registered providers and whether they are enabled.        |

Every mutating command supports `-WhatIf` for a dry run.

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
logs/               Timestamped run logs (git-ignored)
backups/            Rollback manifests (git-ignored)
tests/              Pester 5 unit + integration tests
docs/               Architecture, provider guide, contributing, roadmap, FAQ
```

## Documentation

- [Architecture](docs/Architecture.md)
- [Providers](docs/Providers.md)
- [Developer guide](docs/DeveloperGuide.md)
- [Contributing](docs/Contributing.md)
- [Roadmap](docs/Roadmap.md)
- [Troubleshooting](docs/Troubleshooting.md)
- [FAQ](docs/FAQ.md)

## Safety model

DevDepot never deletes user data. Migrations move data with `robocopy`, verify
the move, then place a junction at the original path. Sources inside the Windows
directory, Program Files or drive roots are refused. Every reversible action is
appended to a per-run manifest under `backups/`. See
[docs/Architecture.md](docs/Architecture.md#safety) for details.

## License

MIT — see [LICENSE](LICENSE).
