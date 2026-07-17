# DevDepot

**Move developer caches, SDKs and package repositories off your Windows system drive —
safely, idempotently, and reversibly.**

DevDepot is a Windows command-line tool that relocates the large, regenerable data your
development tools scatter across `C:` — npm, pnpm, Yarn, NuGet, Gradle, Maven, pip and
more — into a single consolidated root such as `D:\DevDepot`. Your system drive stays
clean, and every tool keeps working, because DevDepot uses each tool's official
redirection **and** leaves a filesystem junction at the original location.

[Install DevDepot](installation.md){ .md-button .md-button--primary }
[Quick start](quick-start.md){ .md-button }

## Why DevDepot

Modern development environments quietly consume tens of gigabytes on the system drive.
DevDepot solves that without uninstalling anything or breaking your tools:

- **Reclaim system-drive space** by moving regenerable caches to a bigger or secondary drive.
- **Compatibility first** — tools keep working via their own environment variable *and* a
  junction at the original path. Nothing needs to know about DevDepot.
- **Safe and reversible** — every change is recorded in a local state database; one command
  puts everything back.
- **Idempotent** — run it as often as you like; it only moves what hasn't been moved.

## What it looks like

```text
DevDepot analyze
  Root: D:\DevDepot

READY TO MIGRATE
  npm            3.9 GB   C:\Users\you\AppData\Local\npm-cache
  pip          455.2 MB   C:\Users\you\AppData\Local\pip\Cache

ALREADY OPTIMIZED
  Maven, NuGet, uv

NOT INSTALLED
  sbt / Coursier, Bun, Deno, Yarn, Conda, Poetry

Reclaimable from system drive: 4.4 GB
```

## Highlights

- **13 cache providers** across the Java, Node.js, .NET and Python ecosystems.
- **Transactional migration** — each step is applied, verified, and rolled back as a unit
  if anything fails.
- **Per-provider rollback** from a local state database.
- **No administrator rights** required for the default configuration.

!!! note "Requirements"
    DevDepot requires **PowerShell 7.0+** on **Windows 10 or 11**. See
    [Installation](installation.md).

---

DevDepot is open source under the [MIT License](https://github.com/duxdraco/dux-win-dev-depot/blob/main/LICENSE),
developed and maintained by **Dux Draco**.
