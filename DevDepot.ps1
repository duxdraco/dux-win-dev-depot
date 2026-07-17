#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
<#
.SYNOPSIS
    DevDepot - migrate developer caches, SDKs and package repositories off the
    Windows system drive.
.DESCRIPTION
    Single entry point/dispatcher. Loads core modules, layered configuration and
    providers, then runs the requested command. Mutating commands are idempotent
    and transactional, and record an authoritative state database used for rollback.
.PARAMETER Command
    analyze | install | doctor | repair | rollback | status | report | provider | version
.PARAMETER Arg1
    Sub-verb for 'provider' (list | enable | disable | info).
.PARAMETER Arg2
    Provider id for 'provider enable|disable|info'.
.PARAMETER ConfigPath
    Explicit user config.json. Defaults to .\config\config.json.
.PARAMETER MachineConfig
    Machine-wide config.json (lower precedence than user config).
.PARAMETER Root
    Override the migration root (CLI precedence).
.PARAMETER Provider
    Restrict the run to these provider ids.
.PARAMETER SafetyLevel
    Safe | Conservative | Aggressive | Experimental (CLI precedence).
.PARAMETER Verification
    None | Stats | Hash (CLI precedence).
.PARAMETER Format
    Report formats: Json, Markdown, Html.
.PARAMETER LogLevel
    Trace | Debug | Info | Warn | Error.
.PARAMETER Quiet
    Suppress console log output.
.EXAMPLE
    .\DevDepot.ps1 analyze
.EXAMPLE
    .\DevDepot.ps1 install -WhatIf
.EXAMPLE
    .\DevDepot.ps1 provider disable docker
.EXAMPLE
    .\DevDepot.ps1 provider info npm
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('analyze', 'install', 'doctor', 'repair', 'rollback', 'status', 'report', 'provider', 'list', 'version')]
    [string] $Command = 'status',

    [Parameter(Position = 1)][string] $Arg1,
    [Parameter(Position = 2)][string] $Arg2,

    [string]   $ConfigPath,
    [string]   $MachineConfig,
    [string]   $Root,
    [string[]] $Provider,
    [ValidateSet('Safe', 'Conservative', 'Aggressive', 'Experimental')][string] $SafetyLevel,
    [ValidateSet('None', 'Stats', 'Hash')][string] $Verification,
    [ValidateSet('Json', 'Markdown', 'Html')][string[]] $Format = @('Json', 'Markdown', 'Html'),
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error')][string] $LogLevel,
    [switch]   $Quiet,
    [Parameter(ValueFromRemainingArguments = $true)][string[]] $Rest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Accept GNU-style flags (--provider <id>, --provider=<id>, --quiet) alongside the
# native -Provider / -Quiet. Tokens land in Arg1/Arg2 or -Rest depending on order.
$flagTokens = @(@($Arg1, $Arg2) + @($Rest) | Where-Object { $_ })
for ($fi = 0; $fi -lt $flagTokens.Count; $fi++) {
    $tok = $flagTokens[$fi]
    if ($tok -eq '--provider' -and ($fi + 1) -lt $flagTokens.Count) { $Provider = @($flagTokens[$fi + 1]); $fi++ }
    elseif ($tok -like '--provider=*') { $Provider = @($tok.Split('=', 2)[1]) }
    elseif ($tok -eq '--quiet') { $Quiet = [switch]$true }
}

$script:Paths = @{
    Root      = $PSScriptRoot
    Modules   = Join-Path $PSScriptRoot 'modules'
    Providers = Join-Path $PSScriptRoot 'providers'
    Config    = Join-Path $PSScriptRoot 'config'
    Reports   = Join-Path $PSScriptRoot 'reports'
    Logs      = Join-Path $PSScriptRoot 'logs'
    State     = $PSScriptRoot
}

Import-Module (Join-Path $script:Paths.Modules 'DevDepot.psm1') -Force -DisableNameChecking
Assert-DevDepotWindows

# --- Layered configuration ----------------------------------------------
if (-not $ConfigPath) {
    $candidate = Join-Path $script:Paths.Config 'config.json'
    $ConfigPath = if (Test-Path -LiteralPath $candidate) { $candidate } else { Join-Path $script:Paths.Config 'default.config.json' }
}
$cliOverrides = @{}
if ($Root)         { $cliOverrides['root'] = $Root }
if ($LogLevel)     { $cliOverrides['logLevel'] = $LogLevel }
if ($SafetyLevel)  { $cliOverrides['safetyLevel'] = $SafetyLevel }
if ($Verification) { $cliOverrides['verification'] = $Verification }

$config = Import-DevDepotLayeredConfig -MachinePath $MachineConfig -UserPath $ConfigPath -CliOverrides $cliOverrides
$configProblems = Test-DevDepotConfig -Config $config
if ($configProblems.Count -gt 0) {
    throw "Invalid configuration:`n - $($configProblems -join "`n - ")"
}

# --- Logger --------------------------------------------------------------
$logger = New-DevDepotLogger -LogDirectory $script:Paths.Logs -MinimumLevel $config.logLevel -Quiet:$Quiet -Name $Command
$logger.Event('Info', "DevDepot '$Command' starting.", @{
    root = $config.root; strategy = $config.linkStrategy; safety = $config.safetyLevel
    verification = $config.verification; sources = @($config.configSources)
})

$simulate = [bool]$WhatIfPreference

# --- Load providers ------------------------------------------------------
$allProviders = Import-DevDepotProviders -Path $script:Paths.Providers -Logger $logger
if ($Provider) { $allProviders = @($allProviders | Where-Object { $_.Id -in $Provider }) }
$enabledProviders = @($allProviders | Where-Object { Test-DevDepotProviderEnabled -Config $config -ProviderId $_.Id })
$logger.Info("Loaded $($allProviders.Count) provider(s); $($enabledProviders.Count) enabled.")

# ------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------
function New-ReportSkeleton {
    param([string] $CommandName)
    [pscustomobject]@{
        Command     = $CommandName
        RunId       = (Get-Date -Format 'yyyyMMdd-HHmmss')
        GeneratedAt = (Get-Date).ToString('o')
        Root        = (Expand-DevDepotPath $config.root)
        Platform    = (Get-DevDepotPlatform)
        Providers   = @()
        Totals      = [pscustomobject]@{
            DetectedCount = 0; ReclaimableBytes = [long]0; ReclaimableHuman = '0 B'
            MovedBytes = [long]0; MovedHuman = '0 B'
        }
        Warnings = @(); Errors = @(); Recommendations = @()
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

function Get-ReadContext { New-DevDepotContext -Config $config -Logger $logger -Simulate }

function Resolve-InstallOrder {
    # Capability-gate then dependency/priority order the enabled providers.
    param([pscustomobject] $Context)
    $capable = foreach ($p in $enabledProviders) {
        $cap = Test-DevDepotProviderCapable -Provider $p -Context $Context
        if ($cap.Capable) { $p } else { $logger.Warn("[$($p.Id)] not runnable: $($cap.Reasons -join '; ')") }
    }
    $capable = @($capable)
    $res = Resolve-DevDepotProviderOrder -Providers $capable
    foreach ($c in @($res.Conflicts))           { $logger.Warn("Conflict: $c") }
    foreach ($m in @($res.MissingDependencies)) { $logger.Warn("Dependency: $m") }
    foreach ($cy in @($res.Cycles))             { $logger.Error("Dependency cycle involving: $cy") }
    return $res
}

# ------------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------------
function Invoke-AnalyzeCommand {
    $report   = New-ReportSkeleton -CommandName 'analyze'
    $context  = Get-ReadContext
    $ready    = [System.Collections.Generic.List[object]]::new()
    $optimized = [System.Collections.Generic.List[object]]::new()
    $absent   = [System.Collections.Generic.List[string]]::new()

    $rows = foreach ($p in $enabledProviders) {
        $a     = Invoke-DevDepotProviderAction -Provider $p -Action 'Analyze' -Context $context
        $class = $a.Details.Classification
        if ($a.Details.Detected) { $report.Totals.DetectedCount++ }

        switch ($class) {
            'ReadyToMigrate' {
                $report.Totals.ReclaimableBytes += [long]$a.Details.Reclaimable
                $ready.Add([pscustomobject]@{ Name = $p.Name; Bytes = [long]$a.Details.TotalBytes; Items = $a.Details.Items })
            }
            'AlreadyOptimized' { $optimized.Add($p.Name) }
            'NotInstalled'     { $absent.Add($p.Name) }
        }
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category; Detected = $a.Details.Detected
            SizeBytes = [long]$a.Details.TotalBytes; SizeHuman = (Format-DevDepotSize $a.Details.TotalBytes)
            Status = $class; Items = $a.Details.Items
        }
    }
    $report.Providers = @($rows)

    # Grouped, human-friendly console output.
    Write-Host ''
    Write-Host 'DevDepot analyze' -ForegroundColor Cyan
    Write-Host ("  Root: {0}" -f (Expand-DevDepotPath $config.root))
    Write-Host ''
    Write-Host 'READY TO MIGRATE' -ForegroundColor Green
    if ($ready.Count -eq 0) {
        Write-Host '  (nothing to migrate)'
    } else {
        foreach ($r in ($ready | Sort-Object Bytes -Descending)) {
            $src = @($r.Items | ForEach-Object { $_.Source }) -join ', '
            Write-Host ('  {0,-12} {1,10}   {2}' -f $r.Name, (Format-DevDepotSize $r.Bytes), $src)
        }
    }
    Write-Host ''
    Write-Host 'ALREADY OPTIMIZED' -ForegroundColor DarkGray
    Write-Host ('  {0}' -f $(if ($optimized.Count) { ($optimized -join ', ') } else { '(none)' }))
    Write-Host ''
    Write-Host 'NOT INSTALLED' -ForegroundColor DarkGray
    Write-Host ('  {0}' -f $(if ($absent.Count) { ($absent -join ', ') } else { '(none)' }))
    Write-Host ''
    Write-Host ("Reclaimable from system drive: {0}" -f (Format-DevDepotSize $report.Totals.ReclaimableBytes)) -ForegroundColor Cyan
    Write-Host ''

    $report.Recommendations = @(
        "Run 'DevDepot install -WhatIf' to preview, then 'DevDepot install' to migrate.",
        "$($ready.Count) provider(s) ready, $($optimized.Count) already optimized, $($absent.Count) not installed."
    )
    $paths = Write-Reports -Report $report
    $logger.Info("Analyze complete. Reclaimable: $($report.Totals.ReclaimableHuman).")
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-InstallCommand {
    $report = New-ReportSkeleton -CommandName 'install'
    $state  = if ($simulate) { $null } else { Import-DevDepotState -BasePath $script:Paths.State -Root (Expand-DevDepotPath $config.root) }
    $context = New-DevDepotContext -Config $config -Logger $logger -State $state -Simulate:$simulate

    $res = Resolve-InstallOrder -Context $context
    foreach ($cy in @($res.Cycles)) { $report.Errors += "Dependency cycle: $cy" }

    $rows = foreach ($p in @($res.Ordered)) {
        if (-not (Test-DevDepotProviderEnabled -Config $config -ProviderId $p.Id)) { continue }
        $plan = Get-DevDepotMappingPlan -Provider $p -Context $context

        # Gracefully skip tools that are not installed: no command on PATH and no
        # real (non-junction) cache directory to migrate. This avoids creating
        # junctions for software the user does not have.
        $cmds = if ($p.ContainsKey('Detect') -and $p['Detect'].ContainsKey('Commands')) { @($p['Detect']['Commands']) } else { @() }
        $hasCommand   = (Test-DevDepotDetectionHints -Commands $cmds).Detected
        $hasRealCache = [bool](@($plan | Where-Object { $_.SourceExists -and -not $_.AlreadyLinked }).Count)
        if (-not ($hasCommand -or $hasRealCache)) {
            $logger.Info("[$($p.Id)] skipped: not installed.")
            [pscustomobject]@{ Id = $p.Id; Name = $p.Name; Category = $p.Category; Detected = $false
                SizeBytes = [long]0; SizeHuman = '-'; Status = 'Skipped' }
            continue
        }

        $det  = Invoke-DevDepotProviderAction -Provider $p -Action 'Detect' -Context $context
        if ($det.Details.Detected) { $report.Totals.DetectedCount++ }
        $m = Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $context
        if ($m.Status -eq 'Failed')  { $report.Errors   += "[$($p.Id)] $($m.Message)" }
        if ($m.Status -eq 'Warning') { $report.Warnings += "[$($p.Id)] $($m.Message)" }
        $report.Totals.MovedBytes += [long]$m.Details.MovedBytes

        # Per-provider verification summary (requested output).
        if ($det.Details.Detected -or $m.Details.MovedBytes -gt 0 -or $m.Status -eq 'Failed') {
            $verify = switch ($m.Status) { 'Success' { 'PASS' } 'Warning' { 'PASS' } 'Failed' { 'FAIL' } default { 'SKIP' } }
            Write-Host (Format-DevDepotProviderSummary -Name $p.Name `
                -Sources @($plan | ForEach-Object { $_.Source }) -Targets @($plan | ForEach-Object { $_.Target }) `
                -Status $m.Status -MovedBytes ([long]$m.Details.MovedBytes) -Verification $verify)
        }

        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category; Detected = $det.Details.Detected
            SizeBytes = [long]$m.Details.MovedBytes; SizeHuman = (Format-DevDepotSize $m.Details.MovedBytes); Status = $m.Status
        }
    }
    $report.Providers = @($rows)

    if ($state) {
        $statePath = Save-DevDepotState -State $state
        $logger.Info("State saved: $statePath")
        $report.Recommendations += 'Rollback with: .\DevDepot.ps1 rollback'
    } else {
        $report.Recommendations += 'Simulation only (-WhatIf); no changes were made.'
    }
    $paths = Write-Reports -Report $report
    $logger.Info("Install complete. Moved: $($report.Totals.MovedHuman). Errors: $($report.Errors.Count), Warnings: $($report.Warnings.Count).")
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-DoctorCommand {
    $report  = New-ReportSkeleton -CommandName 'doctor'
    $context = Get-ReadContext
    $rows = foreach ($p in $enabledProviders) {
        $v = Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $context
        foreach ($issue in @($v.Details.Issues)) { $report.Warnings += "[$($p.Id)] $issue" }
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category; Detected = $true
            SizeBytes = [long]0; SizeHuman = '-'; Status = $v.Status; Issues = @($v.Details.Issues)
        }
    }
    $report.Providers = @($rows)
    $report.Recommendations += if ($report.Warnings.Count -gt 0) { "Run '.\DevDepot.ps1 repair' to fix the issues above." } else { 'No issues detected.' }
    $paths = Write-Reports -Report $report
    $logger.Info("Doctor complete. Issues: $($report.Warnings.Count).")
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-RepairCommand {
    $report  = New-ReportSkeleton -CommandName 'repair'
    $context = New-DevDepotContext -Config $config -Logger $logger -Simulate:$simulate
    $rows = foreach ($p in $enabledProviders) {
        $r = Invoke-DevDepotProviderAction -Provider $p -Action 'Repair' -Context $context
        [pscustomobject]@{ Id = $p.Id; Name = $p.Name; Category = $p.Category; Detected = $true; SizeBytes = [long]0; SizeHuman = '-'; Status = $r.Status }
    }
    $report.Providers = @($rows)
    $paths = Write-Reports -Report $report
    $logger.Info('Repair complete.')
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-RollbackCommand {
    $state = Import-DevDepotState -BasePath $script:Paths.State
    if (@($state.Providers.Keys).Count -eq 0) {
        $logger.Warn('No recorded state to roll back.')
        return
    }
    $onlyProvider = if ($Provider) { $Provider[0] } else { $null }
    $results = Invoke-DevDepotStateRollback -State $state -Logger $logger -ProviderId $onlyProvider
    if (-not $simulate) { Save-DevDepotState -State $state | Out-Null }
    $failed = @($results | Where-Object { $_.Status -eq 'Failed' })
    $logger.Info("Rollback complete. Reversed $(@($results).Count) operation(s); $($failed.Count) failure(s).")
    $results | Format-Table Provider, Type, Status, Message -AutoSize | Out-String | Write-Host
    [pscustomobject]@{ Results = $results }
}

function Invoke-ReportCommand {
    # Report on current recorded state plus live validation.
    $report  = New-ReportSkeleton -CommandName 'report'
    $state   = Import-DevDepotState -BasePath $script:Paths.State
    $context = Get-ReadContext
    $rows = foreach ($p in $enabledProviders) {
        $ps = Get-DevDepotProviderState -State $state -ProviderId $p.Id
        $v  = Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $context
        foreach ($issue in @($v.Details.Issues)) { $report.Warnings += "[$($p.Id)] $issue" }
        [pscustomobject]@{
            Id = $p.Id; Name = $p.Name; Category = $p.Category
            Detected = [bool]$ps; SizeBytes = [long]0
            SizeHuman = if ($ps) { "$(@($ps.operations).Count) op(s)" } else { '-' }
            Status = if ($ps) { $ps.status } else { 'not-migrated' }
        }
    }
    $report.Providers = @($rows)
    $report.Recommendations += "State file: $($state.File)"
    $paths = Write-Reports -Report $report
    $logger.Info('Report generated.')
    [pscustomobject]@{ Report = $report; Files = $paths }
}

function Invoke-StatusCommand {
    $context = Get-ReadContext
    Write-Host ''
    Write-Host 'DevDepot status' -ForegroundColor Cyan
    Write-Host ('  Root         : {0}' -f (Expand-DevDepotPath $config.root))
    Write-Host ('  Strategy     : {0}   Safety: {1}   Verify: {2}' -f $config.linkStrategy, $config.safetyLevel, $config.verification)
    Write-Host ('  Config layers: {0}' -f (@($config.configSources) -join ' -> '))
    $priv = Get-DevDepotPrivilege
    Write-Host ('  Elevated     : {0}   DeveloperMode: {1}' -f $priv.IsElevated, $priv.DeveloperMode)
    Write-Host ''
    Write-Host 'Providers:' -ForegroundColor Cyan
    foreach ($p in $enabledProviders) {
        $v   = Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $context
        $det = Invoke-DevDepotProviderAction -Provider $p -Action 'Detect' -Context $context
        $mark = if (-not $det.Details.Detected) { ' . ' } elseif ($v.Status -eq 'Success') { ' OK' } else { ' !!' }
        Write-Host ('  [{0}] {1,-14} {2}' -f $mark, $p.Id, $p.Name)
    }
    Write-Host ''
}

function Invoke-ProviderCommand {
    switch ($Arg1) {
        'list' {
            $allProviders |
                Select-Object @{ N = 'Enabled'; E = { Test-DevDepotProviderEnabled -Config $config -ProviderId $_.Id } },
                    Id, Category, Name, @{ N = 'Priority'; E = { (Get-DevDepotProviderMetadata -Provider $_).Priority } } |
                Sort-Object Category, Name | Format-Table -AutoSize | Out-String | Write-Host
        }
        { $_ -in @('enable', 'disable') } {
            if (-not $Arg2) { throw "Usage: DevDepot provider $Arg1 <providerId>" }
            $enable = ($Arg1 -eq 'enable')
            Set-ProviderEnabled -ProviderId $Arg2 -Enabled $enable
            Write-Host "Provider '$Arg2' $(if($enable){'enabled'}else{'disabled'}) in $($script:Paths.Config)\config.json" -ForegroundColor Green
        }
        'info' {
            if (-not $Arg2) { throw 'Usage: DevDepot provider info <providerId>' }
            $p = $allProviders | Where-Object Id -eq $Arg2 | Select-Object -First 1
            if (-not $p) { throw "Unknown provider '$Arg2'." }
            $meta = Get-DevDepotProviderMetadata -Provider $p
            Write-Host ''
            Write-Host "$($p.Name) ($($p.Id))" -ForegroundColor Cyan
            Write-Host "  Category      : $($p.Category)"
            Write-Host "  Version       : $($meta.Version)"
            Write-Host "  Enabled       : $(Test-DevDepotProviderEnabled -Config $config -ProviderId $p.Id)"
            Write-Host "  Priority      : $($meta.Priority)   RequiresAdmin: $($meta.RequiresAdmin)"
            Write-Host "  Requires      : PowerShell $($meta.MinimumPowerShell), Windows $($meta.MinimumWindows)"
            Write-Host "  Dependencies  : $((@($meta.Dependencies) -join ', '))"
            Write-Host "  Conflicts     : $((@($meta.Conflicts) -join ', '))"
            if ($p.ContainsKey('Mappings')) {
                Write-Host '  Mappings:'
                foreach ($m in @($p['Mappings'])) {
                    $ev = if ($m.ContainsKey('EnvVar')) { " env=$($m['EnvVar'])" } else { '' }
                    Write-Host "    - $($m['Source'])  ->  <root>\$($m['TargetSubPath'])$ev"
                }
            }
            Write-Host ''
        }
        default { throw "Usage: DevDepot provider <list|enable|disable|info> [providerId]" }
    }
}

function Set-ProviderEnabled {
    param([string] $ProviderId, [bool] $Enabled)
    $userConfig = Join-Path $script:Paths.Config 'config.json'
    if (Test-Path -LiteralPath $userConfig) {
        $obj = Get-Content -LiteralPath $userConfig -Raw | ConvertFrom-Json
    } else {
        $obj = Get-Content -LiteralPath (Join-Path $script:Paths.Config 'default.config.json') -Raw | ConvertFrom-Json
    }
    if (-not ($obj.PSObject.Properties.Name -contains 'providers') -or -not $obj.providers) {
        $obj | Add-Member -NotePropertyName providers -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $obj.providers | Add-Member -NotePropertyName $ProviderId -NotePropertyValue $Enabled -Force
    if ($PSCmdlet.ShouldProcess($userConfig, "Set provider '$ProviderId' enabled=$Enabled")) {
        $obj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $userConfig -Encoding utf8
    }
}

# ------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------
try {
    # Command functions return result objects for programmatic use; discard them
    # here so the CLI shows only human-friendly (Write-Host) output.
    $null = switch ($Command) {
        'analyze'  { Invoke-AnalyzeCommand }
        'install'  { Invoke-InstallCommand }
        'doctor'   { Invoke-DoctorCommand }
        'repair'   { Invoke-RepairCommand }
        'rollback' { Invoke-RollbackCommand }
        'report'   { Invoke-ReportCommand }
        'status'   { Invoke-StatusCommand }
        'provider' { Invoke-ProviderCommand }
        'list'     { $Arg1 = 'list'; Invoke-ProviderCommand }
        'version'  {
            $manifest = Import-PowerShellDataFile (Join-Path $script:Paths.Root 'DevDepot.psd1') -ErrorAction SilentlyContinue
            Write-Host "DevDepot $(if ($manifest) { $manifest.ModuleVersion } else { '0.1.0' })"
        }
    }
} catch {
    $logger.Error("Command '$Command' failed: $($_.Exception.Message)")
    throw
}
