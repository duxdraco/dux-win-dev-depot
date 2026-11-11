#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Reclaims system-drive space that relocation cannot: stale temp files,
    browser caches, superseded MSIX app versions and the hibernation file.
.DESCRIPTION
    A cleanup task is a hashtable with Id, Name, RequiresAdmin,
    BlockingProcesses, Measure and Run. Both scriptblocks receive the context
    and the task itself. Measure returns Bytes (reclaimable) and Note; Run frees
    the space and returns the bytes actually freed. Tasks only
    delete regenerable data (temp files, caches, package versions Windows no
    longer uses) or turn off a feature (hibernation, undone by
    `powercfg /hibernate on`). Nothing is recorded for rollback.
#>

$script:TempMaxAgeDays = 7

# Chromium cache folders inside each profile, and directly under User Data.
$script:ChromiumProfileCacheDirs = @(
    'Cache', 'Code Cache', 'GPUCache', 'DawnGraphiteCache', 'DawnWebGPUCache',
    'Service Worker\CacheStorage', 'Service Worker\ScriptCache'
)
$script:ChromiumRootCacheDirs = @('GrShaderCache', 'GraphiteDawnCache', 'ShaderCache')

# Appx queries run in Windows PowerShell: the Appx module does not load in
# PowerShell 7 on Windows 10 ("Operation is not supported on this platform").
# A package version is superseded when a newer version of the same package is
# installed and no user has this one installed; frameworks are left alone
# because several versions are legitimately shared between apps.
$script:AppxListScript = @'
$ErrorActionPreference = 'Stop'
$all = @(Get-AppxPackage -AllUsers | Where-Object { -not $_.IsFramework })
$old = foreach ($g in ($all | Group-Object Name, Architecture)) {
    $installed = @($g.Group | Where-Object { @($_.PackageUserInformation | Where-Object { "$($_.InstallState)" -eq 'Installed' }).Count -gt 0 })
    if ($installed.Count -eq 0) { continue }
    $current = [version](($installed | ForEach-Object { [version]$_.Version } | Sort-Object -Descending)[0])
    foreach ($p in $g.Group) {
        if ([version]$p.Version -ge $current) { continue }
        if (@($p.PackageUserInformation | Where-Object { "$($_.InstallState)" -eq 'Installed' }).Count -gt 0) { continue }
        [pscustomobject]@{ PackageFullName = $p.PackageFullName; InstallLocation = $p.InstallLocation }
    }
}
ConvertTo-Json -InputObject @($old) -Compress
'@

function Invoke-DevDepotWindowsPowerShell {
    <#
    .SYNOPSIS
        Runs a script in Windows PowerShell 5.1 and returns its stdout.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Script)

    # Progress and error records would otherwise come back serialized as CLIXML.
    $Script  = "`$ProgressPreference = 'SilentlyContinue'`ntry {`n$Script`n} catch { [Console]::Error.WriteLine(`$_.Exception.Message); exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $r = Invoke-DevDepotCommand -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
    if ($r.ExitCode -ne 0) { throw "Windows PowerShell exited $($r.ExitCode): $($r.StdErr.Trim())" }
    return $r.StdOut
}

function Remove-DevDepotFileList {
    <#
    .SYNOPSIS
        Deletes files one by one, skipping any that are locked; returns bytes freed.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param([System.IO.FileInfo[]] $Files = @())

    $freed = [long]0
    foreach ($f in $Files) {
        try {
            $len = $f.Length
            if ($f.IsReadOnly) { $f.IsReadOnly = $false }
            $f.Delete()
            $freed += $len
        } catch {
            # In use or access denied: leave it for the next run.
        }
    }
    return $freed
}

function Get-DevDepotStaleTempFiles {
    <#
    .SYNOPSIS
        Files under the user temp folder not written for TempMaxAgeDays.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param([string] $Path = $env:TEMP, [int] $MaxAgeDays = $script:TempMaxAgeDays)

    if (-not (Test-Path -LiteralPath $Path)) { return , @() }
    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    return , @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff })
}

function Get-DevDepotChromiumCacheFiles {
    <#
    .SYNOPSIS
        Every file inside the cache folders of a Chromium User Data directory.
    .PARAMETER UserData
        The browser's User Data folder (a junction to the DevDepot root is followed).
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param([Parameter(Mandatory)][string] $UserData)

    if (-not (Test-Path -LiteralPath $UserData)) { return , @() }
    $dirs = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $script:ChromiumRootCacheDirs) { $dirs.Add((Join-Path $UserData $d)) }
    $profiles = Get-ChildItem -LiteralPath $UserData -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' }
    foreach ($p in $profiles) {
        foreach ($d in $script:ChromiumProfileCacheDirs) { $dirs.Add((Join-Path $p.FullName $d)) }
    }
    return , @($dirs | Where-Object { Test-Path -LiteralPath $_ } |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Force -ErrorAction SilentlyContinue })
}

function Get-DevDepotSupersededAppx {
    <#
    .SYNOPSIS
        MSIX package versions superseded by a newer installed version (admin only).
    .OUTPUTS
        [pscustomobject[]] with PackageFullName, InstallLocation, SizeBytes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $json = Invoke-DevDepotWindowsPowerShell -Script $script:AppxListScript
    $list = @($json | ConvertFrom-Json)
    return , @($list | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            PackageFullName = $_.PackageFullName
            InstallLocation = $_.InstallLocation
            SizeBytes       = if ($_.InstallLocation) { (Get-DevDepotFolderSize -Path $_.InstallLocation).SizeBytes } else { [long]0 }
        }
    })
}

function New-ChromiumCacheTask ([string] $Id, [string] $Name, [string] $UserData, [string] $Process) {
    @{
        Id                = $Id
        Name              = $Name
        UserData          = $UserData
        RequiresAdmin     = $false
        BlockingProcesses = @($Process)
        Measure           = {
            param($ctx, $task)
            $files = Get-DevDepotChromiumCacheFiles -UserData (Expand-DevDepotPath $task.UserData)
            [pscustomobject]@{ Bytes = [long](($files | Measure-Object Length -Sum).Sum ?? 0); Note = "$($files.Count) file" }
        }
        Run               = {
            param($ctx, $task)
            Remove-DevDepotFileList -Files (Get-DevDepotChromiumCacheFiles -UserData (Expand-DevDepotPath $task.UserData))
        }
    }
}

function Get-DevDepotCleanupTasks {
    <#
    .SYNOPSIS
        Returns the built-in cleanup tasks in run order.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    return , @(
        @{
            Id                = 'temp'
            Name              = "User temp (> $($script:TempMaxAgeDays) ngay)"
            RequiresAdmin     = $false
            BlockingProcesses = @()
            Measure           = {
                $files = Get-DevDepotStaleTempFiles
                [pscustomobject]@{ Bytes = [long](($files | Measure-Object Length -Sum).Sum ?? 0); Note = "$($files.Count) file" }
            }
            Run               = { Remove-DevDepotFileList -Files (Get-DevDepotStaleTempFiles) }
        }
        (New-ChromiumCacheTask -Id 'chrome-cache' -Name 'Chrome cache' -UserData '%LOCALAPPDATA%\Google\Chrome\User Data' -Process 'chrome')
        (New-ChromiumCacheTask -Id 'edge-cache' -Name 'Edge cache' -UserData '%LOCALAPPDATA%\Microsoft\Edge\User Data' -Process 'msedge')
        @{
            Id                = 'appx-old-versions'
            Name              = 'MSIX app versions cu'
            RequiresAdmin     = $true
            BlockingProcesses = @()
            Measure           = {
                param($ctx)
                if (-not $ctx.Privilege.IsElevated) {
                    return [pscustomobject]@{ Bytes = [long]0; Note = 'can quyen Administrator de liet ke' }
                }
                $pkgs = Get-DevDepotSupersededAppx
                [pscustomobject]@{ Bytes = [long](($pkgs | Measure-Object SizeBytes -Sum).Sum ?? 0); Note = "$($pkgs.Count) package" }
            }
            Run               = {
                param($ctx)
                $pkgs  = Get-DevDepotSupersededAppx
                $freed = [long]0
                foreach ($p in $pkgs) {
                    $name = $p.PackageFullName -replace "'", "''"
                    try {
                        Invoke-DevDepotWindowsPowerShell -Script "Remove-AppxPackage -Package '$name' -AllUsers -ErrorAction Stop" | Out-Null
                        $freed += $p.SizeBytes
                        $ctx.Logger.Info("[appx-old-versions] Removed $($p.PackageFullName)")
                    } catch {
                        $ctx.Logger.Warn("[appx-old-versions] $($p.PackageFullName): $($_.Exception.Message)")
                    }
                }
                return $freed
            }
        }
        @{
            Id                = 'hibernate'
            Name              = 'Hibernation file (hiberfil.sys)'
            RequiresAdmin     = $true
            BlockingProcesses = @()
            Measure           = {
                $file = Join-Path $env:SystemDrive 'hiberfil.sys'
                $item = Get-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                [pscustomobject]@{ Bytes = [long]$(if ($item) { $item.Length } else { 0 }); Note = 'tat Hibernate va Fast Startup' }
            }
            Run               = {
                param($ctx)
                $file   = Join-Path $env:SystemDrive 'hiberfil.sys'
                $before = (Get-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue)?.Length ?? 0
                $r = Invoke-DevDepotCommand -FilePath 'powercfg.exe' -Arguments @('/hibernate', 'off') -Logger $ctx.Logger
                if ($r.ExitCode -ne 0) { throw "powercfg exited $($r.ExitCode): $(($r.StdOut + $r.StdErr).Trim())" }
                $ctx.Logger.Info('[hibernate] Hibernation off. Bat lai bang: powercfg /hibernate on')
                return [long]$before
            }
        }
    )
}

function Invoke-DevDepotCleanupTask {
    <#
    .SYNOPSIS
        Measures and (unless simulating) runs one cleanup task.
    .OUTPUTS
        DevDepot result (Action 'Clean') with ReclaimableBytes, FreedBytes, Warnings.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][hashtable] $Task,
        [Parameter(Mandatory)][pscustomobject] $Context
    )

    $log = $Context.Logger
    $details = [pscustomobject]@{ ReclaimableBytes = [long]0; FreedBytes = [long]0; Note = ''; Warnings = @() }
    function Done([string] $status, [string] $message) {
        New-DevDepotResult -Provider $Task.Id -Action 'Clean' -Status $status -Message $message -Details $details
    }

    try {
        $m = & $Task.Measure $Context $Task
        $details.ReclaimableBytes = [long]$m.Bytes
        $details.Note = $m.Note
    } catch {
        return Done 'Failed' "Khong do duoc: $($_.Exception.Message)"
    }

    if ($Task.RequiresAdmin -and -not $Context.Privilege.IsElevated) {
        $details.Warnings = @('requires-admin')
        return Done 'Skipped' 'Can chay bang quyen Administrator.'
    }
    if ($details.ReclaimableBytes -eq 0) { return Done 'Skipped' 'Khong co gi de don.' }

    $running = Get-DevDepotRunningProcess -Name @($Task.BlockingProcesses)
    if ($running.Count -gt 0) {
        $details.Warnings = @($running | ForEach-Object { "blocked-by-process:$_" })
        $msg = "Dang chay: $($running -join ', '). Dong hoan toan roi chay lai clean."
        $log.Warn("[$($Task.Id)] $msg")
        return Done 'Skipped' $msg
    }
    if ($Context.Simulate) {
        return Done 'Simulated' ("Se giai phong {0}" -f (Format-DevDepotSize $details.ReclaimableBytes))
    }

    try {
        $details.FreedBytes = [long](& $Task.Run $Context $Task)
    } catch {
        return Done 'Failed' $_.Exception.Message
    }
    Done 'Success' ("Da giai phong {0}" -f (Format-DevDepotSize $details.FreedBytes))
}

Export-ModuleMember -Function Get-DevDepotCleanupTasks, Invoke-DevDepotCleanupTask, Get-DevDepotStaleTempFiles,
    Get-DevDepotChromiumCacheFiles, Get-DevDepotSupersededAppx, Remove-DevDepotFileList
