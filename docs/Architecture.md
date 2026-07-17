# Architecture

DevDepot is a modular PowerShell 7 application. It is deliberately *not* a single
script: orchestration, reusable capabilities and per-technology knowledge are
separated so the project stays maintainable as providers grow into the dozens.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│ CLI dispatcher            DevDepot.ps1  (+ thin wrappers)     │
│  parses args, loads config/logger/providers, orchestrates    │
├─────────────────────────────────────────────────────────────┤
│ Provider engine           modules/DevDepot.Provider.psm1     │
│  executes the 7 actions generically from declarative data     │
├─────────────────────────────────────────────────────────────┤
│ Providers                 providers/*.provider.ps1           │
│  pure data describing what each tool stores and where         │
├─────────────────────────────────────────────────────────────┤
│ Core modules              modules/DevDepot.*.psm1            │
│  logging, config, env, registry, junctions, migration,        │
│  backup, rollback, detection, disk, report, safety, platform  │
└─────────────────────────────────────────────────────────────┘
```

## Design principles

- **Declarative providers.** Most providers are data, not code. A provider
  declares *mappings* (source path → target subpath, optional env var, strategy)
  and the engine implements all behaviour. This eliminates duplicated logic and
  makes a new provider a ~10-line file.
- **Dependency injection.** Every provider action receives a *context* object
  (`New-DevDepotContext`) carrying config, logger, state and privilege info.
  There is no global mutable state.
- **Idempotency.** Actions detect the already-migrated state (source is a
  reparse point, env var already set) and no-op. Running `install` twice is
  safe.
- **Everything reversible.** Mutating actions are recorded in the state database;
  `rollback` replays them in reverse.
- **Fail safe, skip gracefully.** Unsupported or absent tools are skipped;
  unsafe paths are refused with a logged reason rather than an abort.

## The provider contract

Each provider is a hashtable with these keys:

| Key           | Required | Purpose                                                        |
|---------------|----------|----------------------------------------------------------------|
| `Id`          | yes      | Stable unique id (used in config and CLI `-Provider`).         |
| `Name`        | yes      | Human-readable name.                                           |
| `Category`    | yes      | Grouping (Java, Node, Python, …).                              |
| `Description` | no       | One-line description.                                          |
| `Detect`      | no       | `@{ Commands=@(); Paths=@() }` — detection hints.              |
| `Mappings`    | no       | Array of migration mappings (see below).                       |
| `Hooks`       | no       | `@{ <Action> = { param($provider,$ctx) … } }` overrides.       |

A **mapping**:

| Field           | Required | Purpose                                                       |
|-----------------|----------|---------------------------------------------------------------|
| `Source`        | yes      | Original path; may contain `%VAR%` tokens.                    |
| `TargetSubPath` | yes      | Path under `root` to relocate into.                           |
| `EnvVar`        | no       | Environment variable to point at the target.                  |
| `Strategy`      | no       | `Auto` (default → config), `EnvVar`, `Junction`, or `Both`.   |

### The seven actions

The engine implements all seven; a provider may override any via `Hooks`:

- **Detect** — is the tool present? (commands on PATH or paths exist)
- **Analyze** — measure cache sizes and build a migration plan (read-only).
- **Migrate** — move data, set env var, create junction (per strategy).
- **Configure** — set env vars only, without moving data.
- **Repair** — re-apply configuration/junctions to fix drift.
- **Rollback** — no-op at provider level; handled from the state database.
- **Validate** — confirm junctions and env vars match expectations.

## Link strategies

| Strategy   | Moves data | Sets env var | Creates junction | Notes                              |
|------------|:----------:|:------------:|:----------------:|------------------------------------|
| `EnvVar`   | yes        | yes          | no               | Cleanest; tool must honour the var |
| `Junction` | yes        | no           | yes              | For tools with no cache env var    |
| `Both`     | yes        | yes          | yes              | **Default** — maximum compatibility|

With `Both`, the original location becomes an invisible junction pointing to the
new root, *and* the tool's env var points there too — so both env-aware and
path-hardcoded tooling keep working.

## Migration flow (per mapping)

1. **Safety gate** — `Test-DevDepotSafeSource` / `Test-DevDepotSafeTarget`.
2. **Move** — `robocopy /MOVE /E` from source to target (skipped if the source
   is already a junction or absent). Bytes measured beforehand.
3. **Ensure target** exists.
4. **Env var** — set at the configured scope (previous value captured).
5. **Junction** — created at the source path pointing to the target.

Each step is an **operation** run inside a transaction (below).

## Transactional core (Phase 2.5)

Migration is transactional. Every unit of work is an **operation** with three
script blocks — `Do`, `Verify`, `Undo` — built by
`New-DevDepot{Move,EnvVar,Junction}Operation`. `Invoke-DevDepotTransaction`:

1. **Safety-gates** each op: runs only if its `SafetyLevel` ≤ `config.safetyLevel`.
2. **Applies** the op (`Do`), then **verifies** it (`Verify`).
3. On any failure, **undoes** the failing op and every previously-committed op in
   reverse order — so a run never leaves a partially-migrated state.
4. Returns committed operation **records** for persistence.

**Verification** (`config.verification`): `None`, `Stats` (file/dir count + bytes,
default) or `Hash` (order-independent SHA-256 of contents; opt-in, O(bytes)). A
`Move` captures source stats/hash before moving and checks the destination after;
a mismatch fails the op and rolls the transaction back. Junction targets and env
values are verified by their own operations.

**State database** (`.state/state.json` + `.state/history/`) is the authoritative
record of what changed — per provider: operations (with original `previousValue`),
provider version, tool version, timestamps, status. **Rollback reads state**, not
Windows. Re-running `install` merges operations, preserving the original baseline
(`Merge-DevDepotOperations`) so idempotent re-runs never corrupt rollback data.

**Provider metadata** drives `install`: `Test-DevDepotProviderCapable` gates on
`MinimumPowerShell`/`MinimumWindows`/`RequiresAdmin`; `Resolve-DevDepotProviderOrder`
topologically orders by `Dependencies` then `Priority`, and reports conflicts,
missing dependencies and cycles.

## Safety

- Sources equal to / inside `%SystemRoot%`, `%ProgramFiles%`, `%ProgramFiles(x86)%`
  or a bare drive root are refused.
- Targets on a non-existent drive, identical to the source, or nested inside the
  source are refused.
- `robocopy` is used for resilient, resumable, verifiable moves; exit codes ≥ 8
  are treated as failures and stop that mapping.
- Nothing is hard-deleted. Removing a junction never touches target contents.

## Configuration

Precedence (low → high): built-in defaults → `config.json` → CLI overrides
(`-Root`, `-LogLevel`).

| Key                 | Default        | Meaning                                              |
|---------------------|----------------|------------------------------------------------------|
| `root`              | `D:\DevDepot`  | Destination root.                                    |
| `linkStrategy`      | `Both`         | Default strategy for `Auto` mappings.                |
| `envVarScope`       | `User`         | `User` or `Machine` (Machine needs elevation).       |
| `logLevel`          | `Info`         | Trace/Debug/Info/Warn/Error.                         |
| `verification`      | `Stats`        | `None` / `Stats` / `Hash` migration verification.    |
| `safetyLevel`       | `Safe`         | Ceiling: `Safe`<`Conservative`<`Aggressive`<`Experimental`. |
| `createJunctions`   | `true`         | Master switch for junction creation.                 |
| `defaultProviderOn` | `true`         | Whether unlisted providers are enabled.              |
| `providers`         | `{}`           | Per-provider `true`/`false` overrides.               |
| `exclude`           | `[]`           | Provider ids to always skip.                         |

Configuration is **layered** (lowest→highest precedence): built-in defaults →
machine config → user config → environment variables (`DEVDEPOT_ROOT`,
`DEVDEPOT_LINKSTRATEGY`, `DEVDEPOT_ENVVARSCOPE`, `DEVDEPOT_LOGLEVEL`,
`DEVDEPOT_VERIFICATION`, `DEVDEPOT_SAFETYLEVEL`) → CLI overrides. The resolved
config carries a `configSources` audit trail (shown by `status`).

## Logging & reports

- Logs: `logs/<command>-<timestamp>.log` (human) **and** `.jsonl` (structured,
  one JSON record per line via `logger.Event`).
- Reports: `reports/report-<command>-<runId>.{json,md,html}` — before/after
  sizes, moved bytes, warnings, errors, recommendations.
- State: `.state/state.json` (authoritative) + `.state/history/` (archived
  snapshots). Rollback consumes state.
