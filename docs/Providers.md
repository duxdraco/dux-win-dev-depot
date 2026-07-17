# Providers

A provider teaches DevDepot about one technology: what it caches, where, and how
to redirect it. Providers live in `providers/<id>.provider.ps1` and are pure
data — the [engine](Architecture.md#the-provider-contract) does the work.

## Implemented (Phase 2)

| Id        | Name           | Category | Redirects                                   | Env var             | Strategy |
|-----------|----------------|----------|---------------------------------------------|---------------------|----------|
| `gradle`  | Gradle         | Java     | `~/.gradle`                                 | `GRADLE_USER_HOME`  | Auto     |
| `maven`   | Maven          | Java     | `~/.m2`                                      | –                   | Junction |
| `sbt`     | sbt / Coursier | Java     | `~/.sbt`, `~/.ivy2`, Coursier cache         | `COURSIER_CACHE`    | mixed    |
| `npm`     | npm            | Node     | `%LOCALAPPDATA%\npm-cache`                   | `npm_config_cache`  | Auto     |
| `pnpm`    | pnpm           | Node     | `%LOCALAPPDATA%\pnpm`                        | –                   | Junction |
| `yarn`    | Yarn           | Node     | `%LOCALAPPDATA%\Yarn\Cache`                  | `YARN_CACHE_FOLDER` | Auto     |
| `bun`     | Bun            | Node     | `~/.bun`                                     | `BUN_INSTALL`       | Auto     |
| `deno`    | Deno           | Node     | `%LOCALAPPDATA%\deno`                        | `DENO_DIR`          | Auto     |
| `nuget`   | NuGet          | DotNet   | `~/.nuget/packages`                          | `NUGET_PACKAGES`    | Auto     |
| `pip`     | pip            | Python   | `%LOCALAPPDATA%\pip\Cache`                   | `PIP_CACHE_DIR`     | Auto     |
| `uv`      | uv             | Python   | `%LOCALAPPDATA%\uv\cache`                    | `UV_CACHE_DIR`      | Auto     |
| `poetry`  | Poetry         | Python   | `%LOCALAPPDATA%\pypoetry\Cache`              | `POETRY_CACHE_DIR`  | Auto     |
| `conda`   | Conda          | Python   | `~/.conda`                                   | –                   | Junction |

"Auto" resolves to `config.linkStrategy` (default `Both`).

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
            # $ctx.Logger, $ctx.Config, $ctx.Manifest, $ctx.Simulate available here.
            # ... stop Docker, relocate the data-root, restart ...
            New-DevDepotResult -Provider $provider.Id -Action 'Migrate' -Status 'Success' -Message '...'
        }
    }
}
```

A hook fully replaces the engine for that action; you can still call any core
module function (they are all imported).

## Provider guidelines

- Prefer the official cache **environment variable** where one exists; add a
  junction (`Both`) for belt-and-braces compatibility.
- Redirect **caches and downloaded artifacts**, not source, credentials, or
  small config — those belong on the fast/backed-up system drive.
- Keep `TargetSubPath` grouped by category (`java\…`, `node\…`).
- Add detection hints so absent tools are skipped cleanly.
- Add a test case to `tests/` for anything with a custom hook.
