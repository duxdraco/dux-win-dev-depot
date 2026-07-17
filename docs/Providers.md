# Providers — authoring guide

A provider teaches DevDepot about one technology: what it caches, where, and how
to redirect it. Providers live in `providers/<id>.provider.ps1` and are pure
data — the [engine](Architecture.md#the-provider-contract) does the work.

> For the **catalog of shipped providers** (paths, environment variables, strategies),
> see [the supported providers list](https://github.com/duxdraco/dux-win-dev-depot/blob/main/SUPPORTED_PROVIDERS.md).
> This page is the guide to **writing** a provider.

## Adding a provider

Create `providers/<id>.provider.ps1` returning a descriptor. Minimal example:

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

That's the whole thing — it is detected, analyzed, migrated, validated, repaired
and rolled back automatically. Run `pwsh -File .\DevDepot.ps1 list` to confirm it
registered.

### When declarative data isn't enough

Some tools need imperative logic (stop a service, rewrite a JSON config, move a
VHDX). Provide a `Hooks` table overriding just the actions you need:

```powershell
@{
    Id = 'docker'; Name = 'Docker Desktop'; Category = 'Containers'
    Hooks = @{
        Migrate = {
            param($provider, $ctx)
            # $ctx.Logger, $ctx.Config, $ctx.State, $ctx.Simulate available here.
            # ... stop Docker, relocate the data-root, restart ...
            New-DevDepotResult -Provider $provider.Id -Action 'Migrate' -Status 'Success' -Message '...'
        }
    }
}
```

A hook fully replaces the engine for that action; you can still call any core
module function (they are all imported).

## Provider metadata (optional, recommended)

Declare `Version` and a `Metadata` block so the engine can gate and order
providers. All fields have safe defaults, so metadata is additive.

```powershell
@{
    Id = 'docker'; Name = 'Docker Desktop'; Category = 'Containers'
    Version = '1.0.0'
    Metadata = @{
        Dependencies      = @('wsl')          # run after these providers
        Conflicts         = @()               # cannot coexist with these
        Priority          = 200               # lower runs earlier (default 100)
        RequiresAdmin     = $true             # skipped if not elevated
        MinimumPowerShell = '7.4'
        MinimumWindows    = '10.0.19045'
        SupportsRollback  = $true
    }
    Mappings = @(
        @{ Source = '...'; TargetSubPath = 'containers\docker'; SafetyLevel = 'Conservative' }
    )
}
```

Per-mapping `SafetyLevel` (`Safe`|`Conservative`|`Aggressive`|`Experimental`,
default `Safe`) gates the operation against `config.safetyLevel`. Mark anything
destructive (e.g. pruning) at `Aggressive` or higher so it never runs by default.

Inspect resolved metadata with `DevDepot provider info <id>`.

## Provider guidelines

- Prefer the official cache **environment variable** where one exists; add a
  junction (`Both`) for belt-and-braces compatibility.
- Redirect **caches and downloaded artifacts**, not source, credentials, or
  small config — those belong on the fast/backed-up system drive.
- Keep `TargetSubPath` grouped by category (`java\…`, `node\…`).
- Add detection hints so absent tools are skipped cleanly.
- Add a test case to `tests/` for anything with a custom hook.
