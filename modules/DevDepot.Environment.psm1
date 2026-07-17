#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    User/Machine environment variable management with rollback support.
.DESCRIPTION
    All writes capture the previous value so callers can record it in a rollback
    manifest. Setting a variable also updates the current process so subsequent
    steps in the same run observe the new value.
#>

function Get-DevDepotEnvVar {
    <#
    .SYNOPSIS
        Reads an environment variable at the given scope.
    .PARAMETER Name
        Variable name.
    .PARAMETER Scope
        User (default), Machine or Process.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [ValidateSet('User', 'Machine', 'Process')][string] $Scope = 'User'
    )
    return [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Set-DevDepotEnvVar {
    <#
    .SYNOPSIS
        Sets an environment variable, returning its previous value for rollback.
    .PARAMETER Name
        Variable name.
    .PARAMETER Value
        New value.
    .PARAMETER Scope
        User (default) or Machine. Machine scope requires elevation.
    .OUTPUTS
        [pscustomobject] with Name, PreviousValue, NewValue, Changed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Value,
        [ValidateSet('User', 'Machine')][string] $Scope = 'User'
    )

    $previous = [Environment]::GetEnvironmentVariable($Name, $Scope)
    $changed  = $false

    if ($previous -ne $Value) {
        if ($PSCmdlet.ShouldProcess("$Scope env var $Name", "Set to '$Value'")) {
            [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
            # Reflect in the current process too.
            [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
            $changed = $true
        }
    }

    [pscustomobject]@{
        PSTypeName    = 'DevDepot.EnvChange'
        Name          = $Name
        Scope         = $Scope
        PreviousValue = $previous
        NewValue      = $Value
        Changed       = $changed
    }
}

function Restore-DevDepotEnvVar {
    <#
    .SYNOPSIS
        Restores an environment variable to a previous value (rollback).
    .DESCRIPTION
        A $null previous value removes the variable.
    .PARAMETER Name
        Variable name.
    .PARAMETER PreviousValue
        Value to restore. $null removes the variable.
    .PARAMETER Scope
        User (default) or Machine.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Name,
        [AllowNull()][AllowEmptyString()][string] $PreviousValue = $null,
        [ValidateSet('User', 'Machine')][string] $Scope = 'User'
    )
    if ($PSCmdlet.ShouldProcess("$Scope env var $Name", 'Restore previous value')) {
        # Empty string previous value is treated as "remove" to keep env clean.
        $restore = if ([string]::IsNullOrEmpty($PreviousValue)) { $null } else { $PreviousValue }
        [Environment]::SetEnvironmentVariable($Name, $restore, $Scope)
        [Environment]::SetEnvironmentVariable($Name, $restore, 'Process')
    }
}

Export-ModuleMember -Function Get-DevDepotEnvVar, Set-DevDepotEnvVar, Restore-DevDepotEnvVar
