# Security Policy

## Supported versions

DevDepot is pre-1.0 and under active development. Security fixes are applied to the latest
released version and the `main` branch.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅ |
| < 0.1.0 | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions,
or pull requests.**

Instead, report privately using GitHub's
[private vulnerability reporting](https://github.com/duxdraco/dux-win-dev-depot/security/advisories/new).
If that is unavailable to you, contact the maintainer privately and we will provide a secure
channel.

Please include, where possible:

- A description of the vulnerability and its impact.
- Steps to reproduce (proof-of-concept, affected command, configuration).
- The DevDepot version (`DevDepot version`), Windows version, and `pwsh --version`.

## What to expect

- We aim to acknowledge reports within **5 business days**.
- We will keep you informed of progress toward a fix and coordinate disclosure timing.
- With your permission, we will credit you in the release notes once a fix ships.

## Scope and safety notes

DevDepot performs privileged-adjacent operations on a developer machine: it moves
directories, creates junctions, and sets environment variables. Reports are especially
welcome for issues such as:

- Path handling that could escape the configured root or affect protected system locations.
- Migration or rollback logic that could lose, corrupt, or expose data.
- Command execution or injection risks in provider handling.

DevDepot never hard-deletes user data and refuses system/Program Files/drive-root sources
by design; reports demonstrating a way around these guarantees are high priority.

Never include secrets, tokens, or full environment dumps in a report.

---

Developed and maintained by **Dux Draco**.
