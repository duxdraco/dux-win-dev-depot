# Frequently asked questions

**What is DevDepot?**
A Windows command-line tool that moves developer caches, SDKs and package repositories off
your system drive (usually `C:`) to a consolidated location on another drive, while keeping
every tool working.

**Is my data safe? Will anything be deleted?**
DevDepot never hard-deletes user data. It *copies* caches with `robocopy`, verifies the
copy, then leaves a junction behind. Removing a junction (during rollback) does not touch
the data it points to. Every change is recorded in a state database for rollback.

**Do I need administrator rights?**
No, for the default setup (directory junctions + user-scope environment variables). You
only need elevation for machine-scope environment variables.

**Will this break my tools?**
That's exactly what the default `Both` strategy prevents: DevDepot sets the tool's cache
environment variable *and* leaves a junction at the old path, so the tool finds its cache
either way. If something does break, `rollback` restores it — please open an issue.

**Can I run it repeatedly?**
Yes. Every command is idempotent. Re-running `install` migrates only what's new and no-ops
on what's already relocated.

**What's the difference between EnvVar, Junction and Both?**
`EnvVar` redirects via the tool's cache environment variable. `Junction` leaves a directory
junction at the original path. `Both` (default) does both — the most compatible option.

**What happens to caches created after migration?**
New cache activity writes straight to the new root (via the environment variable and/or
junction). Nothing accumulates back on `C:`.

**Can I choose a different destination drive?**
Yes. Set `root` in `config.json`, or pass `-Root E:\DevDepot` on the CLI, or set
`DEVDEPOT_ROOT`.

**How do I exclude a tool?**
`"providers": { "conda": false }`, or add its id to `"exclude"`, or run
`DevDepot provider disable <id>`. Unlisted providers are enabled by default.

**Why does a tool show as "Already optimized"?**
Its cache is already off the system drive — either DevDepot migrated it, or the tool keeps
its cache elsewhere via its own configuration (for example a custom Maven `localRepository`,
or pnpm's drive-local store). Nothing needs to move.

**Why is a tool listed as "Not installed"?**
DevDepot couldn't find its command on `PATH` or a real cache directory, so `install` skips
it — no junction is created for software you don't have.

**Does it move my source code or projects?**
No. DevDepot only targets regenerable caches, package repositories and SDK download areas
declared by providers — never your working directories.

**How do I add support for a tool it doesn't know about?**
A provider is a small declarative file. See the authoring guide in
[the provider authoring guide](https://github.com/duxdraco/dux-win-dev-depot/blob/main/docs/Providers.md), or open a
[provider request](https://github.com/duxdraco/dux-win-dev-depot/issues/new/choose).

**Is macOS or Linux supported?**
No. DevDepot is Windows-only by design (junctions, Windows environment-variable scopes,
the registry).

**Where can I see how much space I'd save before committing?**
Run `DevDepot analyze` — it's read-only and reports per-tool sizes and total reclaimable
space.

---

More help: [Troubleshooting](https://github.com/duxdraco/dux-win-dev-depot/blob/main/docs/Troubleshooting.md) ·
[Discussions](https://github.com/duxdraco/dux-win-dev-depot/discussions).

Developed and maintained by **Dux Draco**.
