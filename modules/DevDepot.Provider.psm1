#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Provider model and the declarative migration engine.
.DESCRIPTION
    A provider is a plain descriptor (hashtable) declaring what to migrate. The
    engine implements the seven provider actions (Detect, Analyze, Migrate,
    Configure, Repair, Rollback, Validate) generically from the descriptor, so
    most providers are pure data. Providers may override any action with a
    scriptblock in the Hooks table for special cases (Docker, WSL, ...).

    All actions receive a context object (dependency injection) carrying config,
    logger, manifest, privilege info and resolved root — providers never reach
    for global state.
#>

$script:RequiredKeys = @('Id', 'Name', 'Category')
$script:ValidActions = @('Detect', 'Analyze', 'Migrate', 'Configure', 'Repair', 'Rollback', 'Validate')

function Test-DevDepotProviderDescriptor {
    <#
    .SYNOPSIS
        Validates a provider descriptor, returning a list of problems (empty = OK).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][object] $Descriptor)

    $problems = [System.Collections.Generic.List[string]]::new()
    if ($Descriptor -isnot [hashtable]) {
        $problems.Add('Descriptor is not a hashtable.')
        return , $problems.ToArray()
    }
    foreach ($key in $script:RequiredKeys) {
        if (-not $Descriptor.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$Descriptor[$key])) {
            $problems.Add("Missing required key '$key'.")
        }
    }
    if ($Descriptor.ContainsKey('Mappings')) {
        foreach ($m in @($Descriptor['Mappings'])) {
            if (-not $m.ContainsKey('Source'))        { $problems.Add("Mapping missing 'Source'.") }
            if (-not $m.ContainsKey('TargetSubPath')) { $problems.Add("Mapping missing 'TargetSubPath'.") }
        }
    }
    if ($Descriptor.ContainsKey('Hooks')) {
        foreach ($h in $Descriptor['Hooks'].Keys) {
            if ($h -notin $script:ValidActions) { $problems.Add("Unknown hook '$h'.") }
        }
    }
    # Leading comma preserves an (even empty) array through the pipeline so
    # callers can safely read .Count without hitting an unwrapped $null.
    return , $problems.ToArray()
}

function Get-DevDepotProviderMetadata {
    <#
    .SYNOPSIS
        Returns a provider's metadata merged over defaults.
    .DESCRIPTION
        Old-style descriptors (no Metadata/Version) still work: every field has a
        sensible default, so metadata is additive and non-breaking to author.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][hashtable] $Provider)

    $defaults = @{
        Dependencies      = @()
        Conflicts         = @()
        Priority          = 100
        RequiresAdmin     = $false
        MinimumPowerShell = '7.0'
        MinimumWindows    = '10.0.0'
        SupportsRollback  = $true
        SupportsAnalyze   = $true
        SupportsMigrate   = $true
    }
    $meta = if ($Provider.ContainsKey('Metadata') -and $Provider['Metadata'] -is [hashtable]) { $Provider['Metadata'] } else { @{} }
    foreach ($k in $meta.Keys) { $defaults[$k] = $meta[$k] }

    $defaults['Version'] = if ($Provider.ContainsKey('Version')) { [string]$Provider['Version'] } else { '0.0.0' }
    return [pscustomobject]$defaults
}

function Test-DevDepotProviderCapable {
    <#
    .SYNOPSIS
        Checks a provider against the current environment (PS/Windows/admin).
    .OUTPUTS
        [pscustomobject] Capable + Reasons. Version comparisons come from the
        context so tests can inject values.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][hashtable] $Provider,
        [Parameter(Mandatory)][pscustomobject] $Context
    )
    $meta    = Get-DevDepotProviderMetadata -Provider $Provider
    $reasons = [System.Collections.Generic.List[string]]::new()

    try {
        if ([version]$meta.MinimumPowerShell -gt [version]$Context.PowerShellVersion) {
            $reasons.Add("Requires PowerShell $($meta.MinimumPowerShell) (have $($Context.PowerShellVersion)).")
        }
    } catch { }
    try {
        if ($Context.WindowsVersion -and ([version]$meta.MinimumWindows -gt [version]$Context.WindowsVersion)) {
            $reasons.Add("Requires Windows $($meta.MinimumWindows) (have $($Context.WindowsVersion)).")
        }
    } catch { }
    if ($meta.RequiresAdmin -and -not $Context.Privilege.IsElevated) {
        $reasons.Add('Requires administrator rights.')
    }

    [pscustomobject]@{
        Capable = ($reasons.Count -eq 0)
        Reasons = $reasons.ToArray()
    }
}

function Resolve-DevDepotProviderOrder {
    <#
    .SYNOPSIS
        Orders providers by dependency then priority, and reports conflicts/cycles.
    .DESCRIPTION
        Performs a stable topological sort: dependencies run before dependents;
        within the same dependency level, lower Priority runs first. Missing
        dependencies and dependency cycles are reported, not silently dropped.
    .OUTPUTS
        [pscustomobject] Ordered (hashtable[]), Conflicts (string[]),
        MissingDependencies (string[]), Cycles (string[]).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][hashtable[]] $Providers)

    $byId = @{}
    foreach ($p in $Providers) { $byId[$p.Id] = $p }

    $conflicts = [System.Collections.Generic.List[string]]::new()
    $missing   = [System.Collections.Generic.List[string]]::new()
    $cycles    = [System.Collections.Generic.List[string]]::new()

    # Conflict detection (symmetric): both present and one lists the other.
    foreach ($p in $Providers) {
        $meta = Get-DevDepotProviderMetadata -Provider $p
        foreach ($c in @($meta.Conflicts)) {
            if ($byId.ContainsKey($c)) { $conflicts.Add("$($p.Id) conflicts with $c") }
        }
        foreach ($d in @($meta.Dependencies)) {
            if (-not $byId.ContainsKey($d)) { $missing.Add("$($p.Id) depends on missing '$d'") }
        }
    }

    # Depth-first topological sort with cycle guard.
    $ordered  = [System.Collections.Generic.List[hashtable]]::new()
    $visited  = @{}   # id -> 'temp' | 'done'
    $sorted   = $Providers | Sort-Object @{ E = { (Get-DevDepotProviderMetadata -Provider $_).Priority } }, @{ E = { $_.Id } }

    $visit = {
        param($node)
        $id = $node.Id
        if ($visited[$id] -eq 'done') { return }
        if ($visited[$id] -eq 'temp') { $cycles.Add($id); return }
        $visited[$id] = 'temp'
        $meta = Get-DevDepotProviderMetadata -Provider $node
        foreach ($dep in @($meta.Dependencies)) {
            if ($byId.ContainsKey($dep)) { & $visit $byId[$dep] }
        }
        $visited[$id] = 'done'
        $ordered.Add($node)
    }
    foreach ($p in $sorted) { & $visit $p }

    [pscustomobject]@{
        Ordered             = @($ordered.ToArray())
        Conflicts           = $conflicts.ToArray()
        MissingDependencies = $missing.ToArray()
        Cycles              = $cycles.ToArray()
    }
}

function Import-DevDepotProviders {
    <#
    .SYNOPSIS
        Loads and validates all provider descriptors from a directory.
    .PARAMETER Path
        Directory containing *.provider.ps1 files.
    .PARAMETER Logger
        Optional logger for load diagnostics.
    .OUTPUTS
        [hashtable[]] valid provider descriptors sorted by Category then Name.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [object] $Logger
    )

    $providers = [System.Collections.Generic.List[hashtable]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return , @() }

    foreach ($providerFile in (Get-ChildItem -LiteralPath $Path -Filter '*.provider.ps1' -File | Sort-Object Name)) {
        # Capture the file name up front; inside catch, $_ is the ErrorRecord.
        $fileName = $providerFile.Name
        try {
            $descriptor = & $providerFile.FullName
            $problems   = Test-DevDepotProviderDescriptor -Descriptor $descriptor
            if ($problems.Count -gt 0) {
                if ($Logger) { $Logger.Warn("Skipping provider '$fileName': $($problems -join '; ')") }
                continue
            }
            $providers.Add([hashtable]$descriptor)
        } catch {
            if ($Logger) { $Logger.Error("Failed to load provider '$fileName': $($_.Exception.Message)") }
        }
    }

    return , @($providers | Sort-Object @{ E = { $_.Category } }, @{ E = { $_.Name } })
}

function New-DevDepotContext {
    <#
    .SYNOPSIS
        Builds the context object passed to every provider action.
    .PARAMETER Config
        Configuration object.
    .PARAMETER Logger
        Logger instance.
    .PARAMETER State
        State database (may be $null for read-only actions).
    .PARAMETER Simulate
        When set, actions run in WhatIf mode (no changes).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Config,
        [Parameter(Mandatory)][object] $Logger,
        [object] $State = $null,
        [string] $PowerShellVersion = $null,
        [string] $WindowsVersion = $null,
        [switch] $Simulate
    )
    if (-not $PowerShellVersion) { $PowerShellVersion = $PSVersionTable.PSVersion.ToString() }
    if (-not $WindowsVersion) {
        $plat = Get-DevDepotPlatform
        $WindowsVersion = $plat.Version
    }
    [pscustomobject]@{
        PSTypeName        = 'DevDepot.Context'
        Config            = $Config
        Logger            = $Logger
        State             = $State
        Root              = (Expand-DevDepotPath $Config.root)
        Privilege         = (Get-DevDepotPrivilege)
        PowerShellVersion = $PowerShellVersion
        WindowsVersion    = $WindowsVersion
        Simulate          = [bool]$Simulate
    }
}

function Resolve-DevDepotStrategy {
    <#
    .SYNOPSIS
        Resolves a mapping's effective link strategy.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([hashtable] $Mapping, [pscustomobject] $Config)
    $strategy = if ($Mapping.ContainsKey('Strategy')) { [string]$Mapping['Strategy'] } else { 'Auto' }
    if ($strategy -eq 'Auto' -or [string]::IsNullOrWhiteSpace($strategy)) { $strategy = $Config.linkStrategy }
    return $strategy
}

function Get-DevDepotMappingPlan {
    <#
    .SYNOPSIS
        Expands a provider's mappings into concrete, resolved plan items.
    .OUTPUTS
        [pscustomobject[]] each with Source, Target, EnvVar, Strategy, SourceExists,
        AlreadyLinked, SizeBytes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][hashtable] $Provider,
        [Parameter(Mandatory)][pscustomobject] $Context
    )

    $plan = [System.Collections.Generic.List[object]]::new()
    if (-not $Provider.ContainsKey('Mappings')) { return , @() }

    foreach ($m in @($Provider['Mappings'])) {
        $source   = Expand-DevDepotPath ([string]$m['Source'])
        $target   = Join-Path $Context.Root ([string]$m['TargetSubPath'])
        $strategy = Resolve-DevDepotStrategy -Mapping $m -Config $Context.Config
        $envVar   = if ($m.ContainsKey('EnvVar')) { [string]$m['EnvVar'] } else { $null }

        $safety  = if ($m.ContainsKey('SafetyLevel')) { [string]$m['SafetyLevel'] } else { 'Safe' }
        $exists  = Test-Path -LiteralPath $source
        $linked  = Test-DevDepotReparsePoint -Path $source
        $size    = if ($exists -and -not $linked) { (Get-DevDepotFolderSize -Path $source).SizeBytes } else { [long]0 }

        $plan.Add([pscustomobject]@{
            Source        = $source
            Target        = $target
            EnvVar        = $envVar
            Strategy      = $strategy
            SafetyLevel   = $safety
            SourceExists  = $exists
            AlreadyLinked = $linked
            SizeBytes     = $size
        })
    }
    return , $plan.ToArray()
}

function Invoke-DevDepotProviderAction {
    <#
    .SYNOPSIS
        Executes one action for a provider, dispatching to a hook or the engine.
    .PARAMETER Provider
        Provider descriptor.
    .PARAMETER Action
        One of Detect, Analyze, Migrate, Configure, Repair, Rollback, Validate.
    .PARAMETER Context
        Context from New-DevDepotContext.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Provider,
        [Parameter(Mandatory)][ValidateSet('Detect', 'Analyze', 'Migrate', 'Configure', 'Repair', 'Rollback', 'Validate')]
        [string] $Action,
        [Parameter(Mandatory)][pscustomobject] $Context
    )

    # A provider hook fully overrides the generic engine for that action.
    if ($Provider.ContainsKey('Hooks') -and $Provider['Hooks'].ContainsKey($Action)) {
        return & $Provider['Hooks'][$Action] $Provider $Context
    }

    switch ($Action) {
        'Detect'    { return Invoke-EngineDetect    -Provider $Provider -Context $Context }
        'Analyze'   { return Invoke-EngineAnalyze   -Provider $Provider -Context $Context }
        'Migrate'   { return Invoke-EngineMigrate   -Provider $Provider -Context $Context }
        'Configure' { return Invoke-EngineConfigure -Provider $Provider -Context $Context }
        'Repair'    { return Invoke-EngineRepair    -Provider $Provider -Context $Context }
        'Validate'  { return Invoke-EngineValidate  -Provider $Provider -Context $Context }
        'Rollback'  {
            # Rollback is manifest-driven at the orchestrator level; provider-level
            # rollback is a no-op unless a hook is supplied.
            return New-DevDepotResult -Provider $Provider.Id -Action 'Rollback' -Status 'Skipped' `
                -Message 'Rollback is handled from the migration manifest.'
        }
    }
}

function Invoke-EngineDetect {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)
    $commands = @(); $paths = @()
    if ($Provider.ContainsKey('Detect')) {
        $d = $Provider['Detect']
        if ($d.ContainsKey('Commands')) { $commands = @($d['Commands']) }
        if ($d.ContainsKey('Paths'))    { $paths = @($d['Paths']) }
    }
    # Fall back to mapping sources as detection paths.
    if ($paths.Count -eq 0 -and $Provider.ContainsKey('Mappings')) {
        $paths = @($Provider['Mappings'] | ForEach-Object { $_['Source'] })
    }
    $hit = Test-DevDepotDetectionHints -Commands $commands -Paths $paths
    $status = if ($hit.Detected) { 'Success' } else { 'Skipped' }
    New-DevDepotResult -Provider $Provider.Id -Action 'Detect' -Status $status `
        -Message ("Detected: {0}" -f $hit.Detected) -Details $hit
}

function Invoke-EngineAnalyze {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)
    $plan  = Get-DevDepotMappingPlan -Provider $Provider -Context $Context
    $total = ($plan | Measure-Object -Property SizeBytes -Sum).Sum
    if ($null -eq $total) { $total = 0 }

    # Classify against a robust "installed" signal: a command on PATH, or a
    # reparse point we (or the user) already put in place. A bare directory that
    # happens to exist does not count as installed (avoids false positives).
    $cmds = if ($Provider.ContainsKey('Detect') -and $Provider['Detect'].ContainsKey('Commands')) { @($Provider['Detect']['Commands']) } else { @() }
    $hasCommand    = (Test-DevDepotDetectionHints -Commands $cmds).Detected
    $hasRealCache  = [bool](@($plan | Where-Object { $_.SourceExists -and -not $_.AlreadyLinked }).Count)
    $isMigrated    = [bool](@($plan | Where-Object { $_.AlreadyLinked }).Count)
    $classification =
        if ($hasRealCache)               { 'ReadyToMigrate' }
        elseif ($hasCommand -or $isMigrated) { 'AlreadyOptimized' }
        else                             { 'NotInstalled' }
    $detected = ($hasCommand -or $isMigrated -or $hasRealCache)

    New-DevDepotResult -Provider $Provider.Id -Action 'Analyze' -Status 'Success' `
        -Message ("{0}: {1}" -f $Provider.Name, (Format-DevDepotSize $total)) `
        -Details ([pscustomobject]@{
            Detected       = $detected
            Classification = $classification
            Items          = $plan
            TotalBytes     = [long]$total
            Reclaimable    = [long]$total
        })
}

function Invoke-EngineMigrate {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)

    $log  = $Context.Logger
    $plan = Get-DevDepotMappingPlan -Provider $Provider -Context $Context
    $ops  = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $plan) {
        # --- Safety gate: refuse dangerous sources/targets outright ------
        $safeSrc = Test-DevDepotSafeSource -Path $item.Source
        $safeTgt = Test-DevDepotSafeTarget -Target $item.Target -Source $item.Source
        if (-not $safeSrc.IsSafe) {
            $log.Warn("[$($Provider.Id)] Skipping unsafe source '$($item.Source)': $($safeSrc.Reason)")
            $warnings.Add("unsafe-source:$($item.Source)")
            continue
        }
        if (-not $safeTgt.IsSafe) {
            $log.Warn("[$($Provider.Id)] Skipping unsafe target '$($item.Target)': $($safeTgt.Reason)")
            $warnings.Add("unsafe-target:$($item.Target)")
            continue
        }

        $useEnv      = ($item.EnvVar -and $item.Strategy -in @('EnvVar', 'Both'))
        $useJunction = ($item.Strategy -in @('Junction', 'Both') -and $Context.Config.createJunctions)
        $willMove    = ($item.SourceExists -and -not $item.AlreadyLinked)

        # Ensure the target exists when nothing will be moved into it.
        if (-not $willMove -and -not $Context.Simulate -and ($useEnv -or $useJunction) -and
            -not (Test-Path -LiteralPath $item.Target)) {
            New-Item -ItemType Directory -Path $item.Target -Force | Out-Null
        }

        # Build the operation list in dependency order: move, then env, then junction.
        if ($willMove) {
            $op = New-DevDepotMoveOperation -Source $item.Source -Target $item.Target -EstimatedBytes $item.SizeBytes
            $op.SafetyLevel = $item.SafetyLevel
            $ops.Add($op)
        }
        if ($useEnv) {
            $ops.Add((New-DevDepotEnvVarOperation -Name $item.EnvVar -Value $item.Target -Scope $Context.Config.envVarScope))
        }
        if ($useJunction) {
            $ops.Add((New-DevDepotJunctionOperation -Path $item.Source -Target $item.Target))
        }
    }

    $tx = Invoke-DevDepotTransaction -Context $Context -ProviderId $Provider.Id -Operations $ops.ToArray()

    # Persist committed operations to the state database (authoritative record).
    # Merge with any prior state so the original pre-migration baseline (e.g. the
    # first Move and original env previousValue) survives idempotent re-runs.
    if ($tx.Status -eq 'Success' -and $Context.State -and @($tx.Committed).Count -gt 0) {
        $meta     = Get-DevDepotProviderMetadata -Provider $Provider
        $tool     = Get-DevDepotProviderToolVersion -Provider $Provider
        $existing = Get-DevDepotProviderState -State $Context.State -ProviderId $Provider.Id
        $ops      = if ($existing) {
            Merge-DevDepotOperations -Existing @($existing.operations) -New @($tx.Committed)
        } else { @($tx.Committed) }
        Set-DevDepotProviderState -State $Context.State -ProviderId $Provider.Id `
            -Operations @($ops) -ProviderVersion $meta.Version -ToolVersion $tool -Status 'migrated'
    }

    $status = switch ($tx.Status) {
        'Failed'    { 'Failed' }
        'Simulated' { 'Simulated' }
        default     { if ($warnings.Count -gt 0) { 'Warning' } else { 'Success' } }
    }
    $msg = if ($tx.Status -eq 'Failed') {
        "Transaction failed at '$($tx.FailedOperation)' and was rolled back: $($tx.Error)"
    } else {
        "Moved {0}; {1} operation(s) committed." -f (Format-DevDepotSize $tx.Bytes), @($tx.Committed).Count
    }

    New-DevDepotResult -Provider $Provider.Id -Action 'Migrate' -Status $status -Message $msg `
        -Details ([pscustomobject]@{
            MovedBytes = $tx.Bytes
            Committed  = @($tx.Committed)
            RolledBack = $tx.RolledBack
            Skipped    = @($tx.Skipped)
            Warnings   = $warnings.ToArray()
        })
}

function Get-DevDepotProviderToolVersion {
    <#
    .SYNOPSIS
        Best-effort tool version for state records. Providers may declare a
        VersionCommand (@{ Exe='node'; Args=@('--version') }); otherwise $null.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Provider)
    if (-not $Provider.ContainsKey('VersionCommand')) { return $null }
    $vc = $Provider['VersionCommand']
    if (-not (Test-DevDepotCommand -Name $vc.Exe)) { return $null }
    try {
        $r = Invoke-DevDepotCommand -FilePath $vc.Exe -Arguments @($vc.Args)
        return ($r.StdOut + $r.StdErr).Trim().Split("`n")[0].Trim()
    } catch {
        return $null
    }
}

function Invoke-EngineConfigure {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)
    # Configure = env vars only, no data movement.
    $plan  = Get-DevDepotMappingPlan -Provider $Provider -Context $Context
    $count = 0
    foreach ($item in $plan) {
        if ($item.EnvVar -and $item.Strategy -in @('EnvVar', 'Both')) {
            Set-DevDepotEnvVar -Name $item.EnvVar -Value $item.Target -Scope $Context.Config.envVarScope `
                -WhatIf:$Context.Simulate | Out-Null
            $count++
        }
    }
    New-DevDepotResult -Provider $Provider.Id -Action 'Configure' -Status 'Success' `
        -Message "Configured $count environment variable(s)."
}

function Invoke-EngineValidate {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)
    $plan   = Get-DevDepotMappingPlan -Provider $Provider -Context $Context
    $issues = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $plan) {
        if ($item.Strategy -in @('Junction', 'Both') -and $Context.Config.createJunctions) {
            if (Test-DevDepotReparsePoint -Path $item.Source) {
                $tgt = Get-DevDepotLinkTarget -Path $item.Source
                if (-not $tgt -or ($tgt.TrimEnd('\') -ine $item.Target.TrimEnd('\'))) {
                    $issues.Add("Junction '$($item.Source)' points to '$tgt', expected '$($item.Target)'.")
                }
            } elseif (Test-Path -LiteralPath $item.Source) {
                $issues.Add("Expected a junction at '$($item.Source)' but found a real directory.")
            }
        }
        if ($item.EnvVar -and $item.Strategy -in @('EnvVar', 'Both')) {
            $cur = Get-DevDepotEnvVar -Name $item.EnvVar -Scope $Context.Config.envVarScope
            if ($cur -and ($cur.TrimEnd('\') -ine $item.Target.TrimEnd('\'))) {
                $issues.Add("Env var '$($item.EnvVar)' is '$cur', expected '$($item.Target)'.")
            } elseif (-not $cur) {
                $issues.Add("Env var '$($item.EnvVar)' is not set.")
            }
        }
    }

    $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
    New-DevDepotResult -Provider $Provider.Id -Action 'Validate' -Status $status `
        -Message ("{0} issue(s)." -f $issues.Count) -Details ([pscustomobject]@{ Issues = $issues.ToArray() })
}

function Invoke-EngineRepair {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)
    # Repair re-applies configuration/junctions to fix drift found by Validate.
    $plan    = Get-DevDepotMappingPlan -Provider $Provider -Context $Context
    $fixed   = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $plan) {
        if (-not (Test-Path -LiteralPath $item.Target) -and -not $Context.Simulate) {
            New-Item -ItemType Directory -Path $item.Target -Force | Out-Null
        }
        if ($item.EnvVar -and $item.Strategy -in @('EnvVar', 'Both')) {
            $cur = Get-DevDepotEnvVar -Name $item.EnvVar -Scope $Context.Config.envVarScope
            if ($cur -ne $item.Target) {
                Set-DevDepotEnvVar -Name $item.EnvVar -Value $item.Target -Scope $Context.Config.envVarScope `
                    -WhatIf:$Context.Simulate | Out-Null
                $fixed.Add("env:$($item.EnvVar)")
            }
        }
        if ($item.Strategy -in @('Junction', 'Both') -and $Context.Config.createJunctions) {
            if (-not (Test-DevDepotReparsePoint -Path $item.Source) -and -not (Test-Path -LiteralPath $item.Source)) {
                try {
                    New-DevDepotJunction -Path $item.Source -Target $item.Target -WhatIf:$Context.Simulate | Out-Null
                    $fixed.Add("junction:$($item.Source)")
                } catch {
                    $Context.Logger.Warn("[$($Provider.Id)] Repair could not create junction: $($_.Exception.Message)")
                }
            }
        }
    }

    New-DevDepotResult -Provider $Provider.Id -Action 'Repair' -Status 'Success' `
        -Message ("Repaired {0} item(s)." -f $fixed.Count) -Details ([pscustomobject]@{ Fixed = $fixed.ToArray() })
}

Export-ModuleMember -Function Test-DevDepotProviderDescriptor, Import-DevDepotProviders, New-DevDepotContext,
    Get-DevDepotMappingPlan, Invoke-DevDepotProviderAction, Resolve-DevDepotStrategy,
    Get-DevDepotProviderMetadata, Test-DevDepotProviderCapable, Resolve-DevDepotProviderOrder,
    Get-DevDepotProviderToolVersion
