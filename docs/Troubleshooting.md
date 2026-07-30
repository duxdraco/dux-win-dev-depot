# Troubleshooting

## "This script requires PowerShell 7"
DevDepot does not run on Windows PowerShell 5.1. Install PowerShell 7
(`winget install Microsoft.PowerShell`) and run with `pwsh`, not `powershell`.

## Execution policy blocks the script
Run scripts for the current process only:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## "Cannot create link … a non-empty directory already exists"
A real (non-junction) directory already exists at the source. This happens if a
tool recreated it after a partial run. Re-run `install` (it will move the new
contents), or move/rename the directory and re-run. DevDepot never deletes a
non-empty directory to make room.

## A tool doesn't see the new location
- Open a **new** terminal — environment variable changes apply to new processes.
- Confirm the variable: `pwsh -File .\DevDepot.ps1 doctor`.
- Some tools cache their config; restart the tool/IDE.
- If the tool has no env var, ensure `linkStrategy` includes `Junction` (default
  `Both`).

## Junction creation fails
Directory junctions do not need admin. If creation still fails, the target drive
may be removable/network (junctions require local NTFS volumes) or the source is
on a different filesystem. Check `logs/` for the exact error.

## Machine-scope env vars don't change
`envVarScope: "Machine"` requires an elevated (Administrator) session. Use `User`
scope (default) or run `pwsh` as administrator.

## robocopy not found
`robocopy.exe` ships with Windows. If it is missing/blocked, migration cannot
proceed; restore it or run on a standard Windows install.

## How do I undo everything?
```powershell
pwsh -File .\DevDepot.ps1 rollback                     # everything
pwsh -File .\DevDepot.ps1 rollback --provider npm      # one provider
```
Rollback reads the state database (`.state/state.json`) and reverses each recorded
operation. Prior states are archived under `.state/history/`.

## Moving a WSL distribution

The `wsl` provider is report-only: it tells you where each distribution lives but
never moves it, because relocating one requires `wsl --shutdown` (which stops every
running container and Linux workload). Do it manually:

```powershell
# 1. Find the distro's registry key and current location
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if ($p.DistributionName) { "$($p.DistributionName)  $($_.PSChildName)  $($p.BasePath)" }
}

# 2. Back up the current BasePath value so you can revert
#    (copy it somewhere before continuing)

# 3. Shut WSL down and CONFIRM the distro is Stopped before copying.
#    Copying a running distro produces an inconsistent disk image.
wsl --terminate <DistroName>
wsl --shutdown
wsl -l -v          # must show Stopped

# 4. COPY (do not move) the disk, so the original stays as a backup
robocopy "<OldBasePath>" "F:\WSL\<DistroName>" ext4.vhdx /R:1 /W:2

# 5. Point the registry at the new folder
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{GUID}' `
                 -Name BasePath -Value 'F:\WSL\<DistroName>'

# 6. Verify it boots and your data is intact
wsl -d <DistroName> -- whoami
wsl -d <DistroName> -- ls /home

# 7. Only after verifying, delete the old ext4.vhdx to reclaim the space.
#    If anything went wrong, restore the BasePath value from step 2 instead.
```

Restart Docker Desktop afterwards and restart any containers that were running.

## Where are the logs / reports / state?
- Logs: `logs/<command>-<timestamp>.log` (human) and `.jsonl` (structured)
- Reports: `reports/report-<command>-<runId>.{json,md,html}`
- State: `.state/state.json` (+ `.state/history/`)
