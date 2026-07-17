#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Migration manifest (backup metadata) creation and persistence.
.DESCRIPTION
    A manifest is the single source of truth for rollback. Every reversible
    action (move, env var change, junction, registry change) appends an entry.
    Manifests are immutable once written and stored per-run under the backup dir.
#>

function New-DevDepotManifest {
    <#
    .SYNOPSIS
        Creates a new in-memory manifest object.
    .PARAMETER Root
        The DevDepot root the run targeted.
    .PARAMETER BackupDirectory
        Directory where the manifest will be saved.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $BackupDirectory
    )

    if (-not (Test-Path -LiteralPath $BackupDirectory)) {
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    [pscustomobject]@{
        PSTypeName    = 'DevDepot.Manifest'
        SchemaVersion = 1
        RunId         = $stamp
        CreatedAt     = (Get-Date).ToString('o')
        Root          = $Root
        Path          = (Join-Path $BackupDirectory ("manifest-{0}.json" -f $stamp))
        Entries       = [System.Collections.Generic.List[object]]::new()
    }
}

function Add-DevDepotManifestEntry {
    <#
    .SYNOPSIS
        Appends a reversible-action entry to a manifest.
    .PARAMETER Manifest
        Manifest created by New-DevDepotManifest.
    .PARAMETER Provider
        Provider id responsible for the action.
    .PARAMETER Type
        Action type: Move, EnvVar, Junction, Registry.
    .PARAMETER Data
        Hashtable of type-specific fields needed to reverse the action.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Manifest,
        [Parameter(Mandatory)][string] $Provider,
        [Parameter(Mandatory)][ValidateSet('Move', 'EnvVar', 'Junction', 'Registry')][string] $Type,
        [Parameter(Mandatory)][hashtable] $Data
    )
    $entry = [ordered]@{
        Provider  = $Provider
        Type      = $Type
        Timestamp = (Get-Date).ToString('o')
    }
    foreach ($k in $Data.Keys) { $entry[$k] = $Data[$k] }
    $Manifest.Entries.Add([pscustomobject]$entry)
}

function Save-DevDepotManifest {
    <#
    .SYNOPSIS
        Persists a manifest to disk as JSON.
    .OUTPUTS
        [string] the path the manifest was written to.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject] $Manifest)

    if ($PSCmdlet.ShouldProcess($Manifest.Path, 'Write migration manifest')) {
        $payload = $Manifest | Select-Object SchemaVersion, RunId, CreatedAt, Root, Path,
            @{ Name = 'Entries'; Expression = { $_.Entries.ToArray() } }
        $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Manifest.Path -Encoding utf8
    }
    return $Manifest.Path
}

function Import-DevDepotManifest {
    <#
    .SYNOPSIS
        Loads a manifest from disk. If Path is a directory, the newest manifest wins.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Path)

    $file = $Path
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $file = Get-ChildItem -LiteralPath $Path -Filter 'manifest-*.json' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) {
        throw "No manifest found at '$Path'."
    }
    return Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
}

Export-ModuleMember -Function New-DevDepotManifest, Add-DevDepotManifestEntry, Save-DevDepotManifest, Import-DevDepotManifest
