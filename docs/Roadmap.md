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

- No hard deletes; everything reversible via manifest.
- Compatibility-first (env var + junction).
- Providers stay declarative wherever possible; hooks only for genuinely
  imperative tools.
