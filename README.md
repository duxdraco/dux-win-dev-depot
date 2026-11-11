<div align="center">

# DevDepot

**Free up your Windows `C:` drive by moving developer caches to another drive — safely and reversibly.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)](#install)
[![Tests](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/test.yml/badge.svg)](https://github.com/duxdraco/dux-win-dev-depot/actions/workflows/test.yml)

</div>

npm, Gradle, NuGet, pip, Chrome, Claude Code and friends quietly fill `C:` with
gigabytes of cache. DevDepot moves that data to a drive of your choice and leaves a
link at the old path, so **every tool keeps working unchanged**. One command undoes it.

```text
C:\Users\you\.gradle  ──junction──►  D:\DevDepot\java\gradle   (18 GB now off C:)
```

## Install

Needs **Windows 10/11** and **PowerShell 7** (`winget install Microsoft.PowerShell`).

```powershell
git clone https://github.com/duxdraco/dux-win-dev-depot.git
cd dux-win-dev-depot
```

Pick the destination drive once: copy `config\config.example.json` to
`config\config.json` and set `"root"` (e.g. `"D:\\DevDepot"`).

## Use

```powershell
pwsh -File .\DevDepot.ps1 analyze          # 1. see what can be moved (changes nothing)
pwsh -File .\DevDepot.ps1 install -WhatIf  # 2. preview
pwsh -File .\DevDepot.ps1 install          # 3. move it
```

> **Close the apps first.** Tools that keep files open (Chrome, Claude, Devin, Codex)
> are skipped with a warning while running. Close them and run `install` again.

Open a new terminal afterwards so tools see the new locations.

## Free even more space

Some space can't be moved, only cleaned. `clean` handles temp files, browser caches,
old Windows Store app versions and the hibernation file:

```powershell
pwsh -File .\DevDepot.ps1 clean -WhatIf    # show how much each task would free
pwsh -File .\DevDepot.ps1 clean            # run it (as Administrator for all tasks)
```

Details per task: [docs/commands.md](docs/commands.md#clean).

## Undo or fix

```powershell
pwsh -File .\DevDepot.ps1 rollback                  # put everything back
pwsh -File .\DevDepot.ps1 rollback --provider npm   # just one tool
pwsh -File .\DevDepot.ps1 doctor                    # check links are healthy
pwsh -File .\DevDepot.ps1 repair                    # fix what doctor found
```

## What it covers

| Area | Tools |
|------|-------|
| Java | Gradle, Maven, sbt / Coursier, IDE-downloaded JDKs, Eclipse p2 |
| Node.js | npm, pnpm, Yarn, Bun, Deno |
| .NET / Python | NuGet · pip, uv, Poetry, Conda |
| AI tools | Claude Code, OpenAI Codex, Devin, TabNine |
| Apps | Chrome, JetBrains IDEs, Postman, `~\.local` tools |
| Report only | WSL, Docker Desktop (shows where they live; never moved automatically) |

Exact paths: [SUPPORTED_PROVIDERS.md](SUPPORTED_PROVIDERS.md).
Turn a tool off: `pwsh -File .\DevDepot.ps1 provider disable <id>`.

## Is it safe?

- Data is copied, **verified**, and only then removed from `C:`; any failure rolls the whole step back.
- Every change is recorded, so `rollback` restores the exact original layout.
- Safe to re-run: already-moved tools are skipped.
- No administrator rights needed, except for two `clean` tasks.

More answers in the [FAQ](FAQ.md) and [Troubleshooting](docs/Troubleshooting.md).

## More

[All commands](docs/commands.md) · [Configuration & architecture](docs/Architecture.md) ·
[Write a provider](docs/Providers.md) · [Roadmap](ROADMAP.md) ·
[Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

MIT licensed · developed and maintained by **Dux Draco**.
