# Contributing to DevDepot

Thanks for your interest in improving **DevDepot**! Contributions of all kinds are
welcome — bug reports, documentation, and especially new providers, which are small and
low-risk. This project is developed and maintained by **Dux Draco** with the community.

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** or **request a feature/provider** via
  [Issues](https://github.com/duxdraco/dux-win-dev-depot/issues/new/choose).
- **Ask a question** or share ideas in
  [Discussions](https://github.com/duxdraco/dux-win-dev-depot/discussions).
- **Improve documentation** — typos and clarifications are genuinely appreciated.
- **Add a provider** — see [Adding a provider](#adding-a-provider) below.

Looking for a place to start? Browse issues labelled
[`good first issue`](https://github.com/duxdraco/dux-win-dev-depot/labels/good%20first%20issue).

## Prerequisites

- **PowerShell 7.0+** (`pwsh`)
- [Pester](https://pester.dev) 5.0+ — `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0.0 -Force`
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) — `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`

See [docs/DeveloperGuide.md](docs/DeveloperGuide.md) for a deeper walkthrough of the code.

## Development workflow

```powershell
# 1. Fork, then clone your fork and create a branch
git switch -c provider/cargo

# 2. Make your change

# 3. Validate locally (tests + lint)
pwsh -File .\tests\Invoke-Tests.ps1

# 4. Confirm behaviour without touching real caches
pwsh -File .\DevDepot.ps1 list
pwsh -File .\DevDepot.ps1 install -Provider <id> -WhatIf
```

Open a pull request against `main`. CI (build, lint, test) must pass before review.

## Ground rules

1. Target **PowerShell 7+**. Do not add Windows PowerShell 5.1 workarounds.
2. Keep changes modular — no logic in `DevDepot.ps1` that belongs in a module.
3. Every mutating function supports `-WhatIf`; migrations are recorded in the state database.
4. Add or update tests for behavioural changes.
5. Run the test suite and PSScriptAnalyzer before opening a PR.
6. Write tests against temporary directories only — never touch real user caches in a test.

## Adding a provider

A provider lives in `providers/<id>.provider.ps1` and is pure data. Minimal example:

```powershell
# Cargo - Rust package/registry cache and toolchains under ~/.cargo.
@{
    Id          = 'cargo'
    Name        = 'Cargo'
    Category    = 'Rust'
    Description = 'Rust Cargo home: registry cache, git sources, installed binaries.'
    Detect      = @{ Commands = @('cargo', 'rustup'); Paths = @('%USERPROFILE%\.cargo') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.cargo'; TargetSubPath = 'rust\cargo'; EnvVar = 'CARGO_HOME'; Strategy = 'Auto' }
    )
}
```

Checklist:

- [ ] `providers/<id>.provider.ps1` returns a valid descriptor (`Id`, `Name`, `Category` required).
- [ ] Detection hints cover the common install locations.
- [ ] Redirects caches/artifacts, not credentials or source.
- [ ] Uses the official cache environment variable when one exists.
- [ ] Listed in [SUPPORTED_PROVIDERS.md](SUPPORTED_PROVIDERS.md).
- [ ] Custom `Hooks` (if any) have a test.

The full authoring guide, including imperative `Hooks` for tools like Docker/WSL, is in
[docs/Providers.md](docs/Providers.md).

## Commit and PR conventions

- Use clear, imperative commit subjects (e.g. `add cargo provider`).
- Explain the *why* and any compatibility caveats in the PR description.
- Keep PRs focused; one logical change per PR is easiest to review.

## Reporting security issues

Please do **not** open a public issue for vulnerabilities. See [SECURITY.md](SECURITY.md).

---

Developed and maintained by **Dux Draco**.
