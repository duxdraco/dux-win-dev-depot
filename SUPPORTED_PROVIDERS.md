# Supported providers

DevDepot ships with the providers below. Each one teaches DevDepot where a tool keeps its
cache and how to redirect it. Sizes vary per machine; run `DevDepot analyze` to see yours.

**Strategy** is how the location is redirected:

- **EnvVar** — set the tool's official cache environment variable.
- **Junction** — place a directory junction at the original path.
- **Both** (default) — do both, for maximum compatibility.

`Auto` resolves to your configured `linkStrategy` (default `Both`).

## Java

| Provider | Source (on C:) | Environment variable | Strategy | Target under root |
|----------|----------------|----------------------|----------|-------------------|
| **Gradle** | `~\.gradle` | `GRADLE_USER_HOME` | Auto | `java\gradle` |
| **Maven** | `~\.m2` | – | Junction | `java\maven` |
| **sbt / Coursier** | `~\.sbt`, `~\.ivy2`, `%LOCALAPPDATA%\Coursier\cache` | `COURSIER_CACHE` | mixed | `java\sbt`, `java\ivy2`, `java\coursier` |

## Node.js

| Provider | Source (on C:) | Environment variable | Strategy | Target under root |
|----------|----------------|----------------------|----------|-------------------|
| **npm** | `%LOCALAPPDATA%\npm-cache` | `npm_config_cache` | Auto | `node\npm-cache` |
| **pnpm** | `%LOCALAPPDATA%\pnpm` | – | Junction | `node\pnpm` |
| **Yarn** | `%LOCALAPPDATA%\Yarn\Cache` | `YARN_CACHE_FOLDER` | Auto | `node\yarn-cache` |
| **Bun** | `~\.bun` | `BUN_INSTALL` | Auto | `node\bun` |
| **Deno** | `%LOCALAPPDATA%\deno` | `DENO_DIR` | Auto | `node\deno` |

## .NET

| Provider | Source (on C:) | Environment variable | Strategy | Target under root |
|----------|----------------|----------------------|----------|-------------------|
| **NuGet** | `~\.nuget\packages` | `NUGET_PACKAGES` | Auto | `dotnet\nuget-packages` |

## Python

| Provider | Source (on C:) | Environment variable | Strategy | Target under root |
|----------|----------------|----------------------|----------|-------------------|
| **pip** | `%LOCALAPPDATA%\pip\Cache` | `PIP_CACHE_DIR` | Auto | `python\pip-cache` |
| **uv** | `%LOCALAPPDATA%\uv\cache` | `UV_CACHE_DIR` | Auto | `python\uv-cache` |
| **Poetry** | `%LOCALAPPDATA%\pypoetry\Cache` | `POETRY_CACHE_DIR` | Auto | `python\poetry-cache` |
| **Conda** | `~\.conda` | – | Junction | `python\conda` |

## IDEs & tools

These have no official cache environment variable, so they are relocated with
junctions. **Close the application before migrating.**

| Provider | Source (on C:) | Strategy | Target under root |
|----------|----------------|----------|-------------------|
| **jetbrains** | `%APPDATA%\JetBrains` (config, plugins)<br>`%LOCALAPPDATA%\JetBrains` (caches, indexes) | Junction | `ide\jetbrains-config`<br>`ide\jetbrains-cache` |
| **postman** | `%LOCALAPPDATA%\Postman` | Junction | `tools\postman` |
| **tabnine** | `%APPDATA%\TabNine` | Junction | `ai\tabnine` |
| **eclipse** | `~\.p2` (bundle pool, p2 metadata) | Junction | `java\eclipse-p2` |
| **jdks** | `~\.jdks` (IDE-downloaded JDKs) | Junction | `java\jdks` |
| **user-local** | `~\.local` (pip --user, pipx tools) | Junction | `shared\user-local` |

## Platform (report-only)

These providers **detect and report** but never migrate automatically, because
relocating them requires stopping services and would disrupt running work.
`install` reports their location and leaves them untouched.

| Provider | Reports | How to relocate |
|----------|---------|-----------------|
| **wsl** | Location and size of each WSL2 distribution's `ext4.vhdx`, and whether it sits on the system drive | Manual procedure — see [Troubleshooting](docs/Troubleshooting.md#moving-a-wsl-distribution) |
| **docker** | Location of the Docker Desktop WSL2 data distributions | Docker Desktop → Settings → Resources → Advanced → *Disk image location* |

## Notes

- **Already off C:?** Some tools let you relocate their cache via their own configuration
  (for example, a custom Maven `localRepository` in `settings.xml`, or pnpm's drive-local
  content-addressable store). DevDepot detects these and reports the provider as
  **Already optimized** rather than moving anything.
- **Not installed?** `DevDepot install` skips providers whose tool is not present, so no
  junctions are created for software you don't use.

## Requesting a new provider

Want DevDepot to support another tool? Open a
[provider request](https://github.com/duxdraco/dux-win-dev-depot/issues/new/choose), or
contribute one — a provider is a small declarative file. See the authoring guide in
[the provider authoring guide](https://github.com/duxdraco/dux-win-dev-depot/blob/main/docs/Providers.md).

---

Developed and maintained by **Dux Draco**.
