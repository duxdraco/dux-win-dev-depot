# Quick start

**Analyze → preview → install.** Rollback is always one command away.

```powershell
pwsh -File .\DevDepot.ps1 analyze          # see what can be moved (changes nothing)
pwsh -File .\DevDepot.ps1 install -WhatIf  # preview
pwsh -File .\DevDepot.ps1 install          # move it
pwsh -File .\DevDepot.ps1 clean -WhatIf    # see what can be cleaned
pwsh -File .\DevDepot.ps1 rollback         # undo everything
```

## Choose the destination

Set `"root"` in `config\config.json` (copy it from `config.example.json`), or pass it per run:

```powershell
pwsh -File .\DevDepot.ps1 install -Root E:\DevDepot
```

## Try one tool first

```powershell
pwsh -File .\DevDepot.ps1 install --provider npm
pwsh -File .\DevDepot.ps1 rollback --provider npm
```

!!! tip "Before and after"
    Close apps that keep their data open (Chrome, Claude, Devin, Codex) — they are skipped
    while running. Afterwards, open a new terminal so tools see the new locations.

Full reference: [Commands](commands.md).
