# Commands

Run any command through the main dispatcher:

```powershell
pwsh -File .\DevDepot.ps1 <command> [options]
```

or use the matching wrapper script (e.g. `.\analyze.ps1`).

## Overview

| Command    | Description |
|------------|-------------|
| `analyze`  | Detect tools, measure cache sizes, group them (ready / optimized / not installed). Read-only. |
| `install`  | Migrate installed providers transactionally. Idempotent. Records state for rollback. |
| `doctor`   | Diagnose broken junctions, missing/incorrect environment variables, and drift. |
| `repair`   | Fix issues found by `doctor`. |
| `rollback` | Reverse migrations from the state database (all, or `--provider <id>`). |
| `status`   | Show current configuration and per-provider health. |
| `report`   | Regenerate JSON/Markdown/HTML reports from the current state. |
| `provider` | Manage providers: `list`, `enable <id>`, `disable <id>`, `info <id>`. |
| `version`  | Print the DevDepot version. |

## Common options

| Option | Applies to | Description |
|--------|------------|-------------|
| `-WhatIf` | mutating commands | Dry run — show what would happen without making changes. |
| `--provider <id>` / `-Provider <id>` | analyze, install, rollback | Target a single provider. |
| `-Root <path>` | all | Override the migration root for this run. |
| `-SafetyLevel <level>` | install | `Safe` / `Conservative` / `Aggressive` / `Experimental`. |
| `-Verification <mode>` | install | `None` / `Stats` / `Hash`. |
| `-Quiet` | all | Suppress console log output. |

## analyze

Read-only. Detects each tool, measures its cache, and groups the results:

- **Ready to migrate** — real cache data on the system drive.
- **Already optimized** — installed, but nothing left on the system drive to move.
- **Not installed** — tool not found; `install` will skip it.

```powershell
pwsh -File .\DevDepot.ps1 analyze
```

## install

Migrates installed providers inside a transaction (apply → verify → auto-rollback on
failure) and records the result for rollback. Safe to re-run.

```powershell
pwsh -File .\DevDepot.ps1 install
pwsh -File .\DevDepot.ps1 install -WhatIf          # preview
pwsh -File .\DevDepot.ps1 install --provider npm   # one provider
```

## doctor & repair

`doctor` reports configuration drift (broken junctions, wrong or missing environment
variables). `repair` re-applies the correct configuration.

```powershell
pwsh -File .\DevDepot.ps1 doctor
pwsh -File .\DevDepot.ps1 repair
```

## rollback

Reverses migrations using the state database — no Windows scanning.

```powershell
pwsh -File .\DevDepot.ps1 rollback                 # everything
pwsh -File .\DevDepot.ps1 rollback --provider npm  # one provider
```

## status & report

```powershell
pwsh -File .\DevDepot.ps1 status
pwsh -File .\DevDepot.ps1 report
```

## provider

```powershell
pwsh -File .\DevDepot.ps1 provider list
pwsh -File .\DevDepot.ps1 provider info npm
pwsh -File .\DevDepot.ps1 provider disable conda
pwsh -File .\DevDepot.ps1 provider enable conda
```
