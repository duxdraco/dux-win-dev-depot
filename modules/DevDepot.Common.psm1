#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Shared primitives used across DevDepot modules and providers.
.DESCRIPTION
    Small, dependency-free helpers: path expansion, result objects and human
    readable size formatting. Kept separate so every other module can depend on
    it without creating cycles.
#>

function Expand-DevDepotPath {
    <#
    .SYNOPSIS
        Expands Windows environment variable tokens (e.g. %USERPROFILE%) in a path.
    .PARAMETER Path
        A path that may contain %VAR% tokens or a leading ~ for the home folder.
    .OUTPUTS
        [string] the fully expanded path (not resolved against the file system).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    if ($Path.StartsWith('~')) {
        $Path = $Path -replace '^~', ([Environment]::GetFolderPath('UserProfile'))
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function New-DevDepotResult {
    <#
    .SYNOPSIS
        Builds a standard result object returned by provider actions.
    .PARAMETER Provider
        Provider id.
    .PARAMETER Action
        Action name (Detect, Analyze, Migrate, Configure, Repair, Rollback, Validate).
    .PARAMETER Status
        One of: Success, Skipped, Failed, Simulated, Warning.
    .PARAMETER Message
        Human readable summary.
    .PARAMETER Details
        Optional structured payload.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Provider,
        [Parameter(Mandatory)][string] $Action,
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Skipped', 'Failed', 'Simulated', 'Warning')]
        [string] $Status,
        [string] $Message = '',
        [object] $Details = $null
    )
    [pscustomobject]@{
        PSTypeName = 'DevDepot.Result'
        Provider   = $Provider
        Action     = $Action
        Status     = $Status
        Message    = $Message
        Details    = $Details
        Timestamp  = (Get-Date).ToString('o')
    }
}

function Format-DevDepotSize {
    <#
    .SYNOPSIS
        Formats a byte count as a human readable string (e.g. 1.4 GB).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][long] $Bytes)

    if ($Bytes -lt 0) { $Bytes = 0 }
    $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $value = [double]$Bytes
    $i = 0
    while ($value -ge 1024 -and $i -lt ($units.Count - 1)) {
        $value /= 1024
        $i++
    }
    if ($i -eq 0) { return '{0} {1}' -f [long]$value, $units[$i] }
    return '{0:N1} {1}' -f $value, $units[$i]
}

Export-ModuleMember -Function Expand-DevDepotPath, New-DevDepotResult, Format-DevDepotSize
