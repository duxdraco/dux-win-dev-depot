# FAQ

**Is my data safe? Will anything be deleted?**
DevDepot never hard-deletes user data. It *moves* caches with `robocopy` and
leaves a junction behind. Removing a junction (on rollback) does not touch the
data it points to. Every change is recorded in the state database for rollback.

**Do I need administrator rights?**
No, for the default setup (directory junctions + user-scope environment
variables). You only need elevation for machine-scope environment variables.

**What's the difference between EnvVar, Junction and Both?**
See [Architecture → Link strategies](Architecture.md#link-strategies). Short
version: `Both` (default) is the most compatible — it sets the tool's env var
*and* leaves a junction at the old path.

**Will this break my tools?**
No — that's the point of `Both`. The tool finds its cache whether it reads the
env var or the old path. If you hit a case that breaks, `rollback` restores it
and please open an issue.

**Can I run it repeatedly?**
Yes. Every command is idempotent. Re-running `install` migrates only what's new
and no-ops on what's already relocated.

**What happens to caches created after migration?**
New cache activity writes straight to the new root (via the env var and/or
junction). Nothing accumulates back on `C:`.

**Can I choose a different destination drive?**
Yes: set `root` in `config.json`, or pass `-Root E:\DevDepot` on the CLI.

**How do I exclude a tool?**
`"providers": { "docker": false }` or add its id to `"exclude"`. Unlisted
providers are enabled by default.

**Does it move my source code or projects?**
No. DevDepot only targets regenerable caches, package repositories and SDK
download areas declared by providers — never your working directories.

**How do I add support for a tool it doesn't know about?**
Drop a ~10-line file in `providers/`. See
[Providers → Adding a provider](Providers.md#adding-a-provider).

**Is macOS/Linux supported?**
No. DevDepot is Windows-only by design (junctions, Windows env-var scopes,
registry).

**Where can I see how much space I'd save before committing?**
`pwsh -File .\DevDepot.ps1 analyze` — read-only, writes a report with per-tool
sizes and total reclaimable space.
