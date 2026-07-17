# Quick start

The typical workflow is **analyze → preview → install**, with rollback always available.

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

## Target one provider

Every command accepts `--provider <id>` (or `-Provider <id>`) to work on a single tool —
ideal for trying DevDepot on one cache first:

```powershell
pwsh -File .\DevDepot.ps1 analyze --provider npm
pwsh -File .\DevDepot.ps1 install --provider npm
pwsh -File .\DevDepot.ps1 rollback --provider npm
```

## What a migration looks like

`install` prints a verification block per provider:

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

## Choose the destination

By default DevDepot migrates to `D:\DevDepot`. Change it with a flag, an environment
variable, or `config/config.json`:

```powershell
pwsh -File .\DevDepot.ps1 install -Root E:\DevDepot
```

See [Commands](commands.md) for the full command reference and
[Configuration](https://github.com/duxdraco/dux-win-dev-depot/blob/main/docs/Architecture.md#configuration)
for every option.

!!! tip "Open a new terminal after installing"
    Environment-variable changes apply to newly started processes. Open a new terminal (or
    restart your IDE) so tools pick up the redirected cache locations.
