#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Authoritative state database for DevDepot.
.DESCRIPTION
    The state database (.state/state.json) is the single source of truth for what
    DevDepot has changed: migrated directories, environment variables, registry
    values, junctions, timestamps and provider/tool versions. Rollback reads this
    state rather than scanning Windows. Each mutating save archives the previous
    state under .state/history/ for auditability and recovery.
#>

$script:StateSchemaVersion = 2

function Get-DevDepotStateDirectory {
    <#
    .SYNOPSIS
        Returns (creating if needed) the .state directory under a base path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $BasePath)
    $dir = Join-Path $BasePath '.state'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'history') -Force | Out-Null
    }
    return $dir
}

function Import-DevDepotState {
    <#
    .SYNOPSIS
        Loads the state database, or returns a fresh empty state.
    .PARAMETER BasePath
        Directory that contains (or will contain) the .state folder.
    .PARAMETER Root
        The DevDepot migration root recorded in fresh state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $BasePath,
        [string] $Root = ''
    )
    $dir  = Get-DevDepotStateDirectory -BasePath $BasePath
    $file = Join-Path $dir 'state.json'

    $providers = @{}
    $createdAt = (Get-Date).ToString('o')
    if (Test-Path -LiteralPath $file) {
        $raw = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($raw.PSObject.Properties.Name -contains 'createdAt') { $createdAt = $raw.createdAt }
        if ($raw.PSObject.Properties.Name -contains 'root' -and -not $Root) { $Root = $raw.root }
        if ($raw.PSObject.Properties.Name -contains 'providers' -and $raw.providers) {
            foreach ($p in $raw.providers.PSObject.Properties) { $providers[$p.Name] = $p.Value }
        }
    }

    [pscustomobject]@{
        PSTypeName    = 'DevDepot.State'
        SchemaVersion = $script:StateSchemaVersion
        Root          = $Root
        Directory     = $dir
        File          = $file
        CreatedAt     = $createdAt
        UpdatedAt     = (Get-Date).ToString('o')
        Providers     = $providers   # hashtable: id -> provider state object
    }
}

function Set-DevDepotProviderState {
    <#
    .SYNOPSIS
        Records (or replaces) a provider's migration state.
    .PARAMETER State
        State object from Import-DevDepotState.
    .PARAMETER ProviderId
        Provider id.
    .PARAMETER Operations
        Array of committed operation records.
    .PARAMETER ProviderVersion
        Provider descriptor version.
    .PARAMETER ToolVersion
        Detected tool version (optional).
    .PARAMETER Status
        migrated | rolledback | repaired.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $State,
        [Parameter(Mandatory)][string] $ProviderId,
        [object[]] $Operations = @(),
        [string] $ProviderVersion = '0.0.0',
        [string] $ToolVersion = $null,
        [ValidateSet('migrated', 'rolledback', 'repaired')][string] $Status = 'migrated'
    )
    $State.Providers[$ProviderId] = [pscustomobject]@{
        providerVersion = $ProviderVersion
        toolVersion     = $ToolVersion
        status          = $Status
        updatedAt       = (Get-Date).ToString('o')
        operations      = @($Operations)
    }
}

function Get-DevDepotProviderState {
    <#
    .SYNOPSIS
        Returns a provider's recorded state, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $State,
        [Parameter(Mandatory)][string] $ProviderId
    )
    if ($State.Providers.ContainsKey($ProviderId)) { return $State.Providers[$ProviderId] }
    return $null
}

function Remove-DevDepotProviderState {
    <#
    .SYNOPSIS
        Removes a provider entry from state (e.g. after a full rollback).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $State,
        [Parameter(Mandatory)][string] $ProviderId
    )
    if ($State.Providers.ContainsKey($ProviderId)) { [void]$State.Providers.Remove($ProviderId) }
}

function Get-DevDepotStateField {
    # Reads a field from a record that may be a hashtable or a PSCustomObject.
    param([object] $Record, [string] $Name)
    if ($Record -is [hashtable]) {
        if ($Record.ContainsKey($Name)) { return $Record[$Name] }
        return $null
    }
    $p = $Record.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-DevDepotOperationKey {
    <#
    .SYNOPSIS
        Stable identity for an operation record, used to merge/dedupe state.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object] $Operation)
    $type = Get-DevDepotStateField -Record $Operation -Name 'type'
    switch ($type) {
        'Move'     { return "Move|$((Get-DevDepotStateField -Record $Operation -Name 'source'))" }
        'Junction' { return "Junction|$((Get-DevDepotStateField -Record $Operation -Name 'path'))" }
        'EnvVar'   { return "EnvVar|$((Get-DevDepotStateField -Record $Operation -Name 'scope'))|$((Get-DevDepotStateField -Record $Operation -Name 'name'))" }
        default    { return "$type|$([guid]::NewGuid())" }
    }
}

function Merge-DevDepotOperations {
    <#
    .SYNOPSIS
        Merges new operation records into existing ones, keeping the ORIGINAL on
        key collision so the pre-migration baseline (e.g. previousValue) survives
        idempotent re-runs. Genuinely new operations are appended.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowEmptyCollection()][object[]] $Existing = @(),
        [AllowEmptyCollection()][object[]] $New = @()
    )
    $seen = @{}
    $out  = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $Existing) { $out.Add($e); $seen[(Get-DevDepotOperationKey -Operation $e)] = $true }
    foreach ($n in $New) {
        $k = Get-DevDepotOperationKey -Operation $n
        if (-not $seen.ContainsKey($k)) { $out.Add($n); $seen[$k] = $true }
    }
    return , $out.ToArray()
}

function Save-DevDepotState {
    <#
    .SYNOPSIS
        Persists the state database, archiving the prior version under history/.
    .OUTPUTS
        [string] path written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject] $State)

    if (-not $PSCmdlet.ShouldProcess($State.File, 'Write state database')) { return $State.File }

    # Archive the current on-disk state before overwriting.
    if (Test-Path -LiteralPath $State.File) {
        $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $archive = Join-Path (Join-Path $State.Directory 'history') ("state-{0}.json" -f $stamp)
        Copy-Item -LiteralPath $State.File -Destination $archive -Force -ErrorAction SilentlyContinue
    }

    $State.UpdatedAt = (Get-Date).ToString('o')
    $payload = [ordered]@{
        schemaVersion = $State.SchemaVersion
        root          = $State.Root
        createdAt     = $State.CreatedAt
        updatedAt     = $State.UpdatedAt
        providers     = $State.Providers
    }
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $State.File -Encoding utf8
    return $State.File
}

Export-ModuleMember -Function Get-DevDepotStateDirectory, Import-DevDepotState, Set-DevDepotProviderState,
    Get-DevDepotProviderState, Remove-DevDepotProviderState, Save-DevDepotState,
    Get-DevDepotOperationKey, Merge-DevDepotOperations
