<div align="center">

# DevDepot

**Move developer caches, SDKs and package repositories off your Windows system drive — safely, idempotently, and reversibly.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)](#requirements)
[![Release](https://img.shields.io/github/v/release/duxdraco/dux-win-dev-depot?sort=semver)](https://github.com/duxdraco/dux-win-dev-depot/releases)
[![Build](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/build.yml/badge.svg)](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/build.yml)
[![Tests](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/test.yml/badge.svg)](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/test.yml)
[![Lint](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/lint.yml/badge.svg)](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/lint.yml)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

</div>

---

DevDepot is a **Windows CLI** that relocates the large, regenerable data your development
tools scatter across `C:` — npm, pnpm, Yarn, NuGet, Gradle, Maven, pip and more — into a
single consolidated root such as `D:\DevDepot`. It keeps your system drive clean while every
tool keeps working, because DevDepot uses each tool's official redirection **and** a
filesystem junction at the original location.

## Table of contents

- [Why DevDepot](#why-devdepot)
- [Before / After](#before--after)
- [Features](#features)
- [Supported providers](#supported-providers)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Example output](#example-output)
- [Screenshots](#screenshots)
- [Configuration](#configuration)
- [How it works](#how-it-works)
- [Safety](#safety)
- [Roadmap](#roadmap)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Why DevDepot

Modern development environments quietly consume tens of gigabytes on the system drive.
A single machine can hold multi-gigabyte npm, pip and Gradle caches, a NuGet package
store, and SDK downloads — all on `C:`, often the smallest and most valuable drive.

DevDepot exists to solve that without uninstalling anything or breaking your tools:

- **Reclaim system-drive space** by moving regenerable caches to a bigger/secondary drive.
- **Compatibility first** — tools keep working because DevDepot uses the tool's own
  environment variable (e.g. `npm_config_cache`, `GRADLE_USER_HOME`, `PIP_CACHE_DIR`)
  *and* leaves a directory junction at the original path. Nothing needs to know about DevDepot.
- **Safe and reversible** — every change is recorded in a local state database; one command
  puts everything back.
- **Idempotent** — run it as often as you like; it only moves what hasn't been moved.

## Before / After

```text
BEFORE                                   AFTER
C:\                                       C:\
├─ Users\you\.gradle        (18 GB)       ├─ Users\you\.gradle        → junction ─┐
├─ Users\you\.nuget         ( 6 GB)       ├─ Users\you\.nuget         → junction  │
├─ AppData\Local\npm-cache  ( 4 GB)       ├─ AppData\Local\npm-cache  → junction  │
└─ AppData\Local\pip\Cache  ( 0.5 GB)     └─ AppData\Local\pip\Cache  → junction  │
                                                                                  ▼
   ~28 GB stuck on C:                      D:\DevDepot\   (data lives here; C: is clean)
                                           ├─ java\gradle
                                           ├─ dotnet\nuget-packages
                                           ├─ node\npm-cache
                                           └─ python\pip-cache
```

The original paths still resolve (via the junction) and each tool's cache environment
variable now points to the new location, so builds, installs and restores are unaffected.

## Features

- **13 cache providers** across the Java, Node.js, .NET and Python ecosystems.
- **Grouped `analyze`** that classifies every tool as **Ready to migrate**,
  **Already optimized**, or **Not installed**, and estimates reclaimable space — read-only.
- **Transactional migration** — each step is applied, verified, and automatically rolled
  back as a unit if anything fails; you are never left half-migrated.
- **Per-provider rollback** from a local state database (no Windows scanning).
- **Idempotent** installs — safe to re-run.
- **Verification levels** — `Stats` (file/byte counts, default) or `Hash` (content SHA-256).
- **No admin required** for the default setup (directory junctions + user-scope env vars).
- **Structured logging** (human `.log` + machine-readable `.jsonl`) and JSON/Markdown/HTML reports.
- **Extensible** — a new provider is a small declarative file. See
  [docs/Providers.md](docs/Providers.md).

## Supported providers

| Ecosystem | Providers |
|-----------|-----------|
| Java      | Gradle, Maven, sbt / Coursier |
| Node.js   | npm, pnpm, Yarn, Bun, Deno |
| .NET      | NuGet |
| Python    | pip, uv, Poetry, Conda |

Full details, paths and environment variables are in
[SUPPORTED_PROVIDERS.md](SUPPORTED_PROVIDERS.md). Docker, WSL, IDEs and more are on the
[roadmap](ROADMAP.md).

## Requirements

- **PowerShell 7.0+** (`pwsh`). Windows PowerShell 5.1 is not supported.
- **Windows 10 or 11.**
- Administrator rights are only needed for machine-scope environment variables (optional).

Install PowerShell 7 with:

```powershell
winget install Microsoft.PowerShell
```

## Installation

Clone the repository (no build step required):

```powershell
git clone https://github.com/duxdraco/dux-win-dev-depot.git
cd dux-win-dev-depot
```

If script execution is restricted, allow it for the current process only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Quick start

```powershell
# 1. See what could be moved and how much space you'd reclaim (read-only):
pwsh -File .\DevDepot.ps1 analyze

# 2. Preview the migration without changing anything:
pwsh -File .\DevDepot.ps1 install -WhatIf

# 3. Migrate:
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

| Command    | Description |
|------------|-------------|
| `analyze`  | Detect tools, measure cache sizes, group them (ready / optimized / not installed). Read-only. |
| `install`  | Migrate installed providers transactionally. Idempotent. Records state for rollback. |
| `doctor`   | Diagnose broken junctions, missing/incorrect environment variables, and drift. |
| `repair`   | Fix issues found by `doctor`. |
| `rollback` | Reverse migrations from the state database (all, or `--provider <id>`). |
| `status`   | Show current configuration and per-provider health. |
| `report`   | Regenerate JSON/Markdown/HTML reports from the current state. |
| `provider` | `list` / `enable <id>` / `disable <id>` / `info <id>`. |

Every mutating command supports `-WhatIf` for a dry run, and `--provider <id>`
(or `-Provider <id>`) to target a single provider.

## Example output

`DevDepot analyze` groups everything it finds and estimates reclaimable space:

```text
DevDepot analyze
  Root: D:\DevDepot

READY TO MIGRATE
  npm            3.9 GB   C:\Users\you\AppData\Local\npm-cache
  pip          455.2 MB   C:\Users\you\AppData\Local\pip\Cache
  Gradle        18.4 GB   C:\Users\you\.gradle

ALREADY OPTIMIZED
  Maven, NuGet, uv

NOT INSTALLED
  sbt / Coursier, Bun, Deno, Yarn, Conda, Poetry

Reclaimable from system drive: 22.8 GB
```

`DevDepot install` prints a verification block per provider:

```text
========================================

npm

Current:
C:\Users\you\AppData\Local\npm-cache

New:
D:\DevDepot\node\npm-cache

Status:
SUCCESS

Space moved:
3.9 GB

Verification:
PASS

========================================
```

## Screenshots

> Screenshots are welcome — see [`docs/assets/`](docs/assets/). Suggested captures:

<!-- Replace these placeholders with real images once captured. -->
<!-- ![DevDepot analyze](docs/assets/analyze.png) -->
<!-- ![DevDepot install](docs/assets/install.png) -->
<!-- ![DevDepot status](docs/assets/status.png) -->

| `analyze` | `install` | `status` |
|-----------|-----------|----------|
| _add `docs/assets/analyze.png`_ | _add `docs/assets/install.png`_ | _add `docs/assets/status.png`_ |

## Configuration

Copy [`config/config.example.json`](config/config.example.json) to `config/config.json`
and edit. Every option is documented in
[docs/Architecture.md](docs/Architecture.md#configuration).

```json
{
  "root": "D:\\DevDepot",
  "linkStrategy": "Both",
  "envVarScope": "User",
  "verification": "Stats",
  "safetyLevel": "Safe",
  "providers": { "conda": false },
  "exclude": []
}
```

- `linkStrategy`: `EnvVar` (redirect via env var only), `Junction` (junction only),
  or `Both` (default — most compatible).
- Unlisted providers are **enabled by default**, so new providers work without editing
  your config. Disable one with `"providers": { "id": false }` or via `exclude`.

Configuration is layered (lowest to highest precedence): built-in defaults → machine
config → user config → environment variables (`DEVDEPOT_*`) → CLI flags.

## How it works

DevDepot is a modular PowerShell 7 application, not a single script. A declarative
**provider** describes *what* to move; a **transactional engine** implements *how*, with
verification and automatic rollback; a local **state database** records every change so
rollback never has to guess. See [docs/Architecture.md](docs/Architecture.md) for the full
design.

## Safety

DevDepot never deletes user data. Migrations copy with `robocopy`, verify the copy, then
place a junction at the original path — the source is only removed after verification.
Sources inside the Windows directory, Program Files, or a drive root are refused. Every
reversible action is recorded in `.state/state.json` (with history), and any operation
failure rolls back the entire transaction.

## Roadmap

The current release focuses on the Java, Node.js, .NET and Python ecosystems. Docker,
WSL, JetBrains/VS Code, and AI/cloud tooling are planned. See [ROADMAP.md](ROADMAP.md).

## FAQ

Common questions — "Is my data safe?", "Do I need admin?", "Will this break my tools?" —
are answered in [FAQ.md](FAQ.md).

## Contributing

Contributions are welcome, and new providers are small and low-risk. Read
[CONTRIBUTING.md](CONTRIBUTING.md) and our [Code of Conduct](CODE_OF_CONDUCT.md) to get
started. Have an idea or a question? Open a
[Discussion](https://github.com/duxdraco/dux-win-dev-depot/discussions) or an
[Issue](https://github.com/duxdraco/dux-win-dev-depot/issues/new/choose).

## License

DevDepot is released under the [MIT License](LICENSE).

---

<div align="center">

**DevDepot** — developed and maintained by **Dux Draco**.

If DevDepot saved space on your machine, consider leaving a ⭐ to help others find it.

</div>
