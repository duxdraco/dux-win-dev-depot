#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
<#
.SYNOPSIS
    DevDepot - migrate developer caches, SDKs and package repositories off the
    Windows system drive.
.DESCRIPTION
    Single entry point/dispatcher. Loads the core modules, configuration and
    providers, then runs the requested command. All commands are idempotent and
    every mutating command records a rollback manifest.
.PARAMETER Command
    analyze | install | doctor | repair | rollback | status | version | list
.PARAMETER ConfigPath
    Path to config.json. Defaults to .\config\config.json (falls back to the
    bundled default.config.json, then built-in defaults).
.PARAMETER Root
    Override the migration root (e.g. E:\DevDepot). Overrides config.
.PARAMETER Provider
    One or more provider ids to restrict the run to. Default: all enabled.
.PARAMETER ManifestPath
    For 'rollback': path to a manifest file or the backups directory.
.PARAMETER Format
    Report formats to emit (Json, Markdown, Html). Default: all.
.PARAMETER LogLevel
    Trace | Debug | Info | Warn | Error. Overrides config.
.PARAMETER Quiet
    Suppress console log output.
.EXAMPLE
    .\DevDepot.ps1 analyze
.EXAMPLE
    .\DevDepot.ps1 install -WhatIf
.EXAMPLE
    .\DevDepot.ps1 install -Provider gradle,npm
.EXAMPLE
    .\DevDepot.ps1 rollback -ManifestPath .\backups
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('analyze', 'install', 'doctor', 'repair', 'rollback', 'status', 'version', 'list')]
    [string] $Command = 'status',

    [string]   $ConfigPath,
    [string]   $Root,
    [string[]] $Provider,
    [string]   $ManifestPath,
    [ValidateSet('Json', 'Markdown', 'Html')][string[]] $Format = @('Json', 'Markdown', 'Html'),
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error')][string] $LogLevel,
    [switch]   $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Paths = @{
    Root      = $PSScriptRoot
    Modules   = Join-Path $PSScriptRoot 'modules'
    Providers = Join-Path $PSScriptRoot 'providers'
    Config    = Join-Path $PSScriptRoot 'config'
    Reports   = Join-Path $PSScriptRoot 'reports'
    Logs      = Join-Path $PSScriptRoot 'logs'
    Backups   = Join-Path $PSScriptRoot 'backups'
}

# --- Load core -----------------------------------------------------------
Import-Module (Join-Path $script:Paths.Modules 'DevDepot.psm1') -Force -DisableNameChecking

Assert-DevDepotWindows

# --- Resolve configuration ----------------------------------------------
if (-not $ConfigPath) {
    $candidate = Join-Path $script:Paths.Config 'config.json'
    $ConfigPath = if (Test-Path -LiteralPath $candidate) {
        $candidate
    } else {
        Join-Path $script:Paths.Config 'default.config.json'
    }
}
$config = Import-DevDepotConfig -Path $ConfigPath
if ($Root)     { $config.root = $Root }
if ($LogLevel) { $config.logLevel = $LogLevel }

$configProblems = Test-DevDepotConfig -Config $config
if ($configProblems.Count -gt 0) {
    throw "Invalid configuration:`n - $($configProblems -join "`n - ")"
}

# --- Logger --------------------------------------------------------------
$logger = New-DevDepotLogger -LogDirectory $script:Paths.Logs -MinimumLevel $config.logLevel -Quiet:$Quiet -Name $Command
$logger.Info("DevDepot '$Command' starting. Root='$($config.root)', Strategy='$($config.linkStrategy)'.")

# The dispatcher passes -WhatIf through to a Simulate flag on the context.
$simulate = [bool]$WhatIfPreference

# --- Load providers ------------------------------------------------------
$allProviders = Import-DevDepotProviders -Path $script:Paths.Providers -Logger $logger
if ($Provider) {
    $allProviders = @($allProviders | Where-Object { $_.Id -in $Provider })
}
$enabledProviders = @($allProviders | Where-Object { Test-DevDepotProviderEnabled -Config $config -ProviderId $_.Id })
$logger.Info("Loaded $($allProviders.Count) provider(s); $($enabledProviders.Count) enabled.")

# ------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------
function New-ReportSkeleton {
    param([string] $CommandName)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    [pscustomobject]@{
        Command         = $CommandName
        RunId           = $stamp
        GeneratedAt     = (Get-Date).ToString('o')
        Root            = (Expand-DevDepotPath $config.root)
        Platform        = (Get-DevDepotPlatform)
        Providers       = @()
        Totals          = [pscustomobject]@{
            DetectedCount    = 0
            ReclaimableBytes = [long]0
            ReclaimableHuman = '0 B'
            MovedBytes       = [long]0
            MovedHuman       = '0 B'
        }
        Warnings        = @()
        Errors          = @()
        Recommendations = @()
    }
}

function Write-Reports {
    param([pscustomobject] $Report)
    $Report.Totals.ReclaimableHuman = Format-DevDepotSize $Report.Totals.ReclaimableBytes
    $Report.Totals.MovedHuman       = Format-DevDepotSize $Report.Totals.MovedBytes
    $written = Export-DevDepotReport -Report $Report -Directory $script:Paths.Reports -Formats $Format
    foreach ($p in $written.PSObject.Properties) { $logger.Info("Report ($($p.Name)): $($p.Value)") }
    return $written
}

# ------------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------------
function Invoke-AnalyzeCommand {
    $report  = New-ReportSkeleton -CommandName 'analyze'
    $context = New-DevDepotContext -Config $config -Logger $logger -Simulate
    $rows = foreach ($p in $enabledProviders) {
        $a = Invoke-DevDepotProviderAction -Provider $p -Action 'Analyze' -Context $context
        $detected = $a.Details.Detected
        if ($detected) { $report.Totals.DetectedCount++ }
        $report.Totals.ReclaimableBytes += [long]$a.Details.Reclaimable
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category
            Detected = $detected; SizeBytes = [long]$a.Details.TotalBytes
            SizeHuman = (Format-DevDepotSize $a.Details.TotalBytes); Status = 'analyzed'
            Items = $a.Details.Items
        }
    }
    $report.Providers = @($rows)
    $report.Recommendations = @(
        "Run '.\DevDepot.ps1 install -WhatIf' to preview the migration.",
        "Detected $($report.Totals.DetectedCount) tool(s); estimated reclaimable space on the system drive shown above."
    )
    $paths = Write-Reports -Report $report
    $logger.Info("Analyze complete. Reclaimable: $($report.Totals.ReclaimableHuman).")
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-InstallCommand {
    $report   = New-ReportSkeleton -CommandName 'install'
    $manifest = if ($simulate) { $null } else { New-DevDepotManifest -Root (Expand-DevDepotPath $config.root) -BackupDirectory $script:Paths.Backups }
    $context  = New-DevDepotContext -Config $config -Logger $logger -Manifest $manifest -Simulate:$simulate

    $rows = foreach ($p in $enabledProviders) {
        $det = Invoke-DevDepotProviderAction -Provider $p -Action 'Detect' -Context $context
        if ($det.Details.Detected) { $report.Totals.DetectedCount++ }

        $m = Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $context
        if ($m.Status -eq 'Failed')  { $report.Errors   += "[$($p.Id)] $($m.Message)" }
        if ($m.Status -eq 'Warning') { $report.Warnings += "[$($p.Id)] $($m.Message)" }
        $report.Totals.MovedBytes += [long]$m.Details.MovedBytes
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category
            Detected = $det.Details.Detected; SizeBytes = [long]$m.Details.MovedBytes
            SizeHuman = (Format-DevDepotSize $m.Details.MovedBytes); Status = $m.Status
        }
    }
    $report.Providers = @($rows)

    if ($manifest) {
        $manifestPath = Save-DevDepotManifest -Manifest $manifest
        $logger.Info("Manifest written: $manifestPath")
        $report.Recommendations += "Rollback with: .\DevDepot.ps1 rollback -ManifestPath `"$manifestPath`""
    } else {
        $report.Recommendations += 'Simulation only (-WhatIf); no changes were made and no manifest was written.'
    }

    $paths = Write-Reports -Report $report
    $logger.Info("Install complete. Moved: $($report.Totals.MovedHuman). Errors: $($report.Errors.Count), Warnings: $($report.Warnings.Count).")
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-DoctorCommand {
    $report  = New-ReportSkeleton -CommandName 'doctor'
    $context = New-DevDepotContext -Config $config -Logger $logger -Simulate
    $rows = foreach ($p in $enabledProviders) {
        $v = Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $context
        foreach ($issue in @($v.Details.Issues)) {
            $report.Warnings += "[$($p.Id)] $issue"
        }
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category
            Detected = $true; SizeBytes = [long]0; SizeHuman = '-'
            Status = $v.Status; Issues = @($v.Details.Issues)
        }
    }
    $report.Providers = @($rows)
    if ($report.Warnings.Count -gt 0) {
        $report.Recommendations += "Run '.\DevDepot.ps1 repair' to fix the issues above."
    } else {
        $report.Recommendations += 'No issues detected. Configuration is healthy.'
    }
    $paths = Write-Reports -Report $report
    $logger.Info("Doctor complete. Issues: $($report.Warnings.Count).")
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-RepairCommand {
    $report   = New-ReportSkeleton -CommandName 'repair'
    $manifest = if ($simulate) { $null } else { New-DevDepotManifest -Root (Expand-DevDepotPath $config.root) -BackupDirectory $script:Paths.Backups }
    $context  = New-DevDepotContext -Config $config -Logger $logger -Manifest $manifest -Simulate:$simulate
    $rows = foreach ($p in $enabledProviders) {
        $r = Invoke-DevDepotProviderAction -Provider $p -Action 'Repair' -Context $context
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category
            Detected = $true; SizeBytes = [long]0; SizeHuman = '-'; Status = $r.Status
        }
    }
    $report.Providers = @($rows)
    if ($manifest) { Save-DevDepotManifest -Manifest $manifest | Out-Null }
    $paths = Write-Reports -Report $report
    $logger.Info('Repair complete.')
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-RollbackCommand {
    $source = if ($ManifestPath) { $ManifestPath } else { $script:Paths.Backups }
    $manifest = Import-DevDepotManifest -Path $source
    $logger.Info("Rolling back manifest '$($manifest.RunId)' with $(@($manifest.Entries).Count) entrie(s).")
    $results = Invoke-DevDepotRollback -Manifest $manifest -Logger $logger -WhatIf:$simulate
    $failed  = @($results | Where-Object { $_.Status -eq 'Failed' })
    $logger.Info("Rollback complete. Reversed $($results.Count) entrie(s); $($failed.Count) failure(s).")
    $results | Format-Table Provider, Type, Status, Message -AutoSize | Out-String | Write-Host
    [pscustomobject]@{ Results = $results }
}

function Invoke-StatusCommand {
    $context = New-DevDepotContext -Config $config -Logger $logger -Simulate
    Write-Host ''
    Write-Host 'DevDepot status' -ForegroundColor Cyan
    Write-Host ('  Root         : {0}' -f (Expand-DevDepotPath $config.root))
    Write-Host ('  Strategy     : {0}' -f $config.linkStrategy)
    Write-Host ('  EnvVar scope : {0}' -f $config.envVarScope)
    $priv = Get-DevDepotPrivilege
    Write-Host ('  Elevated     : {0}  DeveloperMode: {1}' -f $priv.IsElevated, $priv.DeveloperMode)
    Write-Host ''
    Write-Host 'Providers:' -ForegroundColor Cyan
    foreach ($p in $enabledProviders) {
        $v   = Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $context
        $det = Invoke-DevDepotProviderAction -Provider $p -Action 'Detect' -Context $context
        $mark = if (-not $det.Details.Detected) { '·' } elseif ($v.Status -eq 'Success') { 'OK' } else { '!!' }
        Write-Host ('  [{0}] {1,-14} {2}' -f $mark, $p.Id, $p.Name)
    }
    Write-Host ''
}

function Invoke-ListCommand {
    Write-Host ''
    Write-Host 'Registered providers:' -ForegroundColor Cyan
    $allProviders |
        Select-Object @{ N = 'Enabled'; E = { Test-DevDepotProviderEnabled -Config $config -ProviderId $_.Id } }, Id, Category, Name |
        Sort-Object Category, Name | Format-Table -AutoSize | Out-String | Write-Host
}

# ------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------
try {
    switch ($Command) {
        'analyze'  { Invoke-AnalyzeCommand }
        'install'  { Invoke-InstallCommand }
        'doctor'   { Invoke-DoctorCommand }
        'repair'   { Invoke-RepairCommand }
        'rollback' { Invoke-RollbackCommand }
        'status'   { Invoke-StatusCommand }
        'list'     { Invoke-ListCommand }
        'version'  {
            $manifest = Import-PowerShellDataFile (Join-Path $script:Paths.Root 'DevDepot.psd1') -ErrorAction SilentlyContinue
            $ver = if ($manifest) { $manifest.ModuleVersion } else { '0.1.0' }
            Write-Host "DevDepot $ver"
        }
    }
} catch {
    $logger.Error("Command '$Command' failed: $($_.Exception.Message)")
    throw
}
