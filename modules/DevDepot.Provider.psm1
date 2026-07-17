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
    .PARAMETER Manifest
        Migration manifest (may be $null for read-only actions).
    .PARAMETER Simulate
        When set, actions run in WhatIf mode (no changes).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Config,
        [Parameter(Mandatory)][object] $Logger,
        [object] $Manifest = $null,
        [switch] $Simulate
    )
    [pscustomobject]@{
        PSTypeName = 'DevDepot.Context'
        Config     = $Config
        Logger     = $Logger
        Manifest   = $Manifest
        Root       = (Expand-DevDepotPath $Config.root)
        Privilege  = (Get-DevDepotPrivilege)
        Simulate   = [bool]$Simulate
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

        $exists  = Test-Path -LiteralPath $source
        $linked  = Test-DevDepotReparsePoint -Path $source
        $size    = if ($exists -and -not $linked) { (Get-DevDepotFolderSize -Path $source).SizeBytes } else { [long]0 }

        $plan.Add([pscustomobject]@{
            Source        = $source
            Target        = $target
            EnvVar        = $envVar
            Strategy      = $strategy
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
    $detected = (Invoke-EngineDetect -Provider $Provider -Context $Context).Details.Detected
    New-DevDepotResult -Provider $Provider.Id -Action 'Analyze' -Status 'Success' `
        -Message ("{0}: {1}" -f $Provider.Name, (Format-DevDepotSize $total)) `
        -Details ([pscustomobject]@{
            Detected     = $detected
            Items        = $plan
            TotalBytes   = [long]$total
            Reclaimable  = [long]$total
        })
}

function Invoke-EngineMigrate {
    [CmdletBinding()]
    param([hashtable] $Provider, [pscustomobject] $Context)

    $log     = $Context.Logger
    $plan    = Get-DevDepotMappingPlan -Provider $Provider -Context $Context
    $moved   = [long]0
    $actions = [System.Collections.Generic.List[string]]::new()
    $status  = 'Success'

    foreach ($item in $plan) {
        # --- Safety gate -------------------------------------------------
        $safeSrc = Test-DevDepotSafeSource -Path $item.Source
        $safeTgt = Test-DevDepotSafeTarget -Target $item.Target -Source $item.Source
        if (-not $safeSrc.IsSafe) {
            $log.Warn("[$($Provider.Id)] Skipping unsafe source '$($item.Source)': $($safeSrc.Reason)")
            $actions.Add("skip-unsafe-source:$($item.Source)")
            continue
        }
        if (-not $safeTgt.IsSafe) {
            $log.Warn("[$($Provider.Id)] Skipping unsafe target '$($item.Target)': $($safeTgt.Reason)")
            $actions.Add("skip-unsafe-target:$($item.Target)")
            $status = 'Warning'
            continue
        }

        $useEnv      = ($item.EnvVar -and $item.Strategy -in @('EnvVar', 'Both'))
        $useJunction = ($item.Strategy -in @('Junction', 'Both') -and $Context.Config.createJunctions)

        # --- Physical move (idempotent) ---------------------------------
        if ($item.SourceExists -and -not $item.AlreadyLinked) {
            $mv = Move-DevDepotDirectory -Source $item.Source -Target $item.Target -Logger $log -WhatIf:$Context.Simulate
            if ($mv.Status -eq 'Failed') {
                $status = 'Failed'
                $actions.Add("move-failed:$($item.Source)")
                continue
            }
            if ($mv.Status -in @('Success', 'Simulated')) {
                $moved += $mv.BytesMoved
                $actions.Add("move:$($item.Source)->$($item.Target)")
                if ($Context.Manifest -and $mv.Status -eq 'Success') {
                    Add-DevDepotManifestEntry -Manifest $Context.Manifest -Provider $Provider.Id -Type 'Move' `
                        -Data @{ Source = $item.Source; Target = $item.Target }
                }
            }
        }

        # Ensure the target exists so tools can write to it.
        if (-not $Context.Simulate -and -not (Test-Path -LiteralPath $item.Target)) {
            New-Item -ItemType Directory -Path $item.Target -Force | Out-Null
        }

        # --- Environment variable ---------------------------------------
        if ($useEnv) {
            $change = Set-DevDepotEnvVar -Name $item.EnvVar -Value $item.Target `
                -Scope $Context.Config.envVarScope -WhatIf:$Context.Simulate
            $actions.Add("env:$($item.EnvVar)=$($item.Target)")
            if ($Context.Manifest -and $change.Changed) {
                Add-DevDepotManifestEntry -Manifest $Context.Manifest -Provider $Provider.Id -Type 'EnvVar' `
                    -Data @{ Name = $item.EnvVar; Scope = $Context.Config.envVarScope; PreviousValue = $change.PreviousValue }
            }
        }

        # --- Junction ----------------------------------------------------
        if ($useJunction) {
            try {
                $j = New-DevDepotJunction -Path $item.Source -Target $item.Target -WhatIf:$Context.Simulate
                $actions.Add("junction:$($item.Source)->$($item.Target)")
                if ($Context.Manifest -and $j.Created) {
                    Add-DevDepotManifestEntry -Manifest $Context.Manifest -Provider $Provider.Id -Type 'Junction' `
                        -Data @{ Path = $item.Source; Target = $item.Target }
                }
            } catch {
                $log.Warn("[$($Provider.Id)] Junction creation failed for '$($item.Source)': $($_.Exception.Message)")
                $status = 'Warning'
            }
        }
    }

    if ($Context.Simulate -and $status -eq 'Success') { $status = 'Simulated' }
    New-DevDepotResult -Provider $Provider.Id -Action 'Migrate' -Status $status `
        -Message ("Moved {0}; {1} action(s)." -f (Format-DevDepotSize $moved), $actions.Count) `
        -Details ([pscustomobject]@{ MovedBytes = $moved; Actions = $actions.ToArray() })
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
    Get-DevDepotMappingPlan, Invoke-DevDepotProviderAction, Resolve-DevDepotStrategy
