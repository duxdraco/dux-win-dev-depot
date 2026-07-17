# Contributing

Thanks for helping make DevDepot better! Most contributions are new providers,
which are small and low-risk.

## Ground rules

1. Target **PowerShell 7+**. Do not add Windows PowerShell 5.1 workarounds.
2. Keep changes modular — no logic in `DevDepot.ps1` that belongs in a module.
3. Every mutating function supports `-WhatIf` and records a manifest entry.
4. Add or update tests for behavioural changes.
5. Run the suite and lint before opening a PR.

## Workflow

```powershell
# 1. Create a branch
git switch -c provider/cargo

# 2. Make your change (e.g. add providers/cargo.provider.ps1)

# 3. Validate
pwsh -File .\tests\Invoke-Tests.ps1

# 4. Confirm it registers and behaves
pwsh -File .\DevDepot.ps1 list
pwsh -File .\DevDepot.ps1 install -Provider cargo -WhatIf
```

## Adding a provider (checklist)

- [ ] `providers/<id>.provider.ps1` returns a valid descriptor (`Id`, `Name`,
      `Category` required).
- [ ] Detection hints cover the common install locations.
- [ ] Redirects caches/artifacts, not credentials or source.
- [ ] Uses the official env var when one exists.
- [ ] Appears in `docs/Providers.md`.
- [ ] Custom `Hooks` (if any) have a test.

## Commit / PR

- Conventional, imperative commit subjects (`add cargo provider`).
- Describe the *why* and any compatibility caveats (e.g. "requires Docker
  restart").
- CI must be green: Pester tests pass, PSScriptAnalyzer clean.

## Reporting issues

Include: Windows version, `pwsh --version`, the command run, and the relevant
`logs/` excerpt and `reports/` JSON. Never paste secrets or full environment
dumps.
