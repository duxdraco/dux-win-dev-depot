# Developer guide

## Prerequisites

- PowerShell 7.0+ (`pwsh`)
- [Pester](https://pester.dev) 5.0+ — `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0.0 -Force`
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) (optional lint) — `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`

## Layout recap

- `modules/DevDepot.psm1` — bootstrap; imports every core module in dependency
  order. Import this one module to get everything.
- `modules/DevDepot.<Area>.psm1` — one concern each. All public functions carry
  comment-based help and use approved verbs.
- `providers/*.provider.ps1` — declarative descriptors.
- `DevDepot.ps1` — CLI dispatcher and orchestration.

## Running

```powershell
Import-Module .\modules\DevDepot.psm1 -Force
$cfg = Import-DevDepotConfig -Path .\config\default.config.json
$log = New-DevDepotLogger -LogDirectory .\logs
$ctx = New-DevDepotContext -Config $cfg -Logger $log -Simulate
$providers = Import-DevDepotProviders -Path .\providers -Logger $log
Invoke-DevDepotProviderAction -Provider ($providers | ? Id -eq 'npm') -Action 'Analyze' -Context $ctx
```

## Tests

```powershell
pwsh -File .\tests\Invoke-Tests.ps1
```

- `tests/Unit.Tests.ps1` — pure-function unit tests (fast, no side effects).
- `tests/Integration.Tests.ps1` — real migrate/idempotency/rollback against temp
  directories; cleans up the `DEVDEPOT_TEST_CACHE` env var after each test.

Write tests against temp directories only; never touch real user caches in a
test. Use `New-Sandbox` in the integration file as a template.

## Coding standards

- `#Requires -Version 7.0` and `Set-StrictMode -Version Latest` at the top of
  every module and script.
- Approved verbs (`Get-`, `Set-`, `New-`, `Test-`, `Invoke-`, `Import-`,
  `Export-`, `Restore-`).
- Comment-based help on every exported function.
- `[CmdletBinding(SupportsShouldProcess)]` on anything that mutates state; honour
  `-WhatIf` (the engine passes `$ctx.Simulate` through as `-WhatIf`).
- No global mutable state — thread the logger/context explicitly.
- Keep provider files declarative; push shared behaviour into the engine.

## Debugging

- Raise verbosity: `-LogLevel Debug` (or `Trace`).
- Dry run everything: `-WhatIf`.
- Inspect a run: `logs/<command>-*.log`, `reports/report-*.json`,
  `backups/manifest-*.json`.
