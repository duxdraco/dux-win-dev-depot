# Roadmap

DevDepot is built in phases. Each phase ends with: tests pass, idempotency
verified, rollback verified, migration safety verified, docs updated. The next
phase does not start until the previous one passes all of these.

## Phase 1 — Core architecture ✅

- Modular structure, bootstrap loader, comment-based help, StrictMode.
- Core modules: Logger, Common, Platform, Privilege, CommandRunner, DiskAnalyzer,
  Environment, Registry, Junction, FileMigration, Backup, Rollback, Detection,
  Safety, Config, Report.
- Declarative provider engine + dependency-injected context.
- CLI dispatcher (`analyze`/`install`/`doctor`/`repair`/`rollback`/`status`/`list`)
  with `-WhatIf`.

## Phase 2 — Java / Node / .NET / Python ✅

- Providers: gradle, maven, sbt/coursier, npm, pnpm, yarn, bun, deno, nuget, pip,
  uv, poetry, conda.
- Unit + integration tests (migrate, idempotency, rollback).

## Phase 2.5 — Production hardening ✅

- Transactional migration engine (operations with Do/Verify/Undo; automatic
  rollback of the whole transaction on any failure).
- State database (`.state/state.json` + history); rollback consumes state.
- Provider metadata: dependencies, conflicts, priority, `RequiresAdmin`,
  `MinimumPowerShell`/`MinimumWindows`, `Supports*`; capability gating and
  dependency/conflict/cycle resolution.
- Migration verification (Stats default, Hash opt-in).
- Safety levels (Safe/Conservative/Aggressive/Experimental).
- Structured JSONL logging; layered configuration (defaults→machine→user→env→CLI).
- CLI subcommands incl. `report` and `provider list|enable|disable|info`.
- Review deliverables in `docs/review/`.

**Release gate before Phase 3:** CI on real PowerShell 7 + Pester 5, path
edge-case/fault-injection tests, concurrent-run lock (see
`docs/review/MigrationPlan.md`).

## Phase 3 — Platform & IDE tooling (planned)

- Go (`GOPATH`/`GOMODCACHE`), Rust (`CARGO_HOME`), Ruby (gems), PHP/Composer,
  Julia, Flutter/Android SDK, Unity, Unreal.
- **Docker Desktop** (relocate data-root; requires service orchestration — hook).
- **WSL2** (export/import or move distro VHDX — hook, elevation-aware).
- JetBrains IDEs, VS Code, Visual Studio caches.
- Git (LFS cache, credential-manager data left in place).

## Phase 4 — AI / Cloud / Game engines (planned)

- Ollama (`OLLAMA_MODELS`), HuggingFace (`HF_HOME`), LM Studio, Stable Diffusion /
  ComfyUI model dirs.
- AWS/Azure/gcloud CLI caches, Terraform plugin cache, kube/helm caches.

## Phase 5 — Hardening & release (ongoing)

- Expand test coverage, CI workflow, PSScriptAnalyzer gate.
- Signed release, module publishing, richer HTML report.
- Optional scheduled "keep-clean" run.

## Design constraints that will not change

- No hard deletes; everything reversible via the state database.
- Compatibility-first (env var + junction).
- Providers stay declarative wherever possible; hooks only for genuinely
  imperative tools.
