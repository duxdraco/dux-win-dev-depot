# Roadmap

DevDepot is built in phases. Each phase ends only when tests pass and idempotency,
rollback and migration safety are verified. This roadmap is a direction, not a promise —
priorities may shift based on real-world usage and community feedback.

## Released

### v0.1.0 — First usable release ✅

- Modular PowerShell 7 architecture with a declarative provider model.
- Transactional migration engine (apply → verify → auto-rollback on failure).
- State database with history; state-based rollback.
- Provider metadata, capability gating, dependency/conflict/cycle resolution.
- Migration verification (`Stats` default, `Hash` opt-in) and safety levels.
- Layered configuration; structured (JSONL) logging; JSON/Markdown/HTML reports.
- CLI: `analyze`, `install`, `doctor`, `repair`, `rollback`, `status`, `report`,
  `provider list|enable|disable|info`.
- **13 providers**: Java (Gradle, Maven, sbt/Coursier), Node.js (npm, pnpm, Yarn, Bun,
  Deno), .NET (NuGet), Python (pip, uv, Poetry, Conda).

## Planned

### v0.2.0 — Hardening & CI

- Continuous integration on real PowerShell 7 (build, lint, test workflows).
- Path edge-case coverage (long paths, Unicode) and fault-injection tests.
- Concurrent-run lock to prevent overlapping mutating runs.
- Analyzer detections: orphan caches and extremely old caches.

### v0.3.0 — Platform & IDE tooling

- Go (`GOPATH` / `GOMODCACHE`), Rust (`CARGO_HOME`), Ruby, PHP/Composer.
- Docker Desktop (relocate data-root), WSL2 (move distribution VHDX).
- JetBrains IDEs, Visual Studio Code, Visual Studio caches.

### v1.0.0 — Stable release

- Broad provider coverage across the ecosystems above.
- Documented, stable configuration and provider contract.
- Signed release and published module.
- Optional scheduled "keep-clean" run.

### Later — AI / Cloud / Game engines

- Ollama, Hugging Face, LM Studio, Stable Diffusion / ComfyUI model directories.
- AWS / Azure / gcloud CLI caches, Terraform plugin cache, Kubernetes/Helm caches.
- Unity, Unreal Engine.

## Design constraints that will not change

- No hard deletes; everything reversible via the state database.
- Compatibility first (environment variable + junction).
- Providers stay declarative wherever possible; imperative hooks only for tools that
  genuinely need them.

---

Developed and maintained by **Dux Draco**. Have a request? Open a
[Discussion](https://github.com/duxdraco/dux-win-dev-depot/discussions) or an
[Issue](https://github.com/duxdraco/dux-win-dev-depot/issues/new/choose).
