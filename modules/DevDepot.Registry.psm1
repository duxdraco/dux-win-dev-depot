#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Safe registry read/write helpers with previous-value capture for rollback.
#>

function Get-DevDepotRegistryValue {
    <#
    .SYNOPSIS
        Reads a registry value, returning $null when the key or value is absent.
    .PARAMETER Path
        Registry path (e.g. 'HKCU:\Environment').
    .PARAMETER Name
        Value name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name
    )
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Set-DevDepotRegistryValue {
    <#
    .SYNOPSIS
        Sets a registry value, returning the previous value for rollback.
    .PARAMETER Path
        Registry path. Created if missing.
    .PARAMETER Name
        Value name.
    .PARAMETER Value
        New value.
    .PARAMETER Type
        Registry value kind (String, ExpandString, DWord, etc.).
    .OUTPUTS
        [pscustomobject] with Path, Name, PreviousValue, NewValue, Changed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][object] $Value,
        [Microsoft.Win32.RegistryValueKind] $Type = [Microsoft.Win32.RegistryValueKind]::String
    )

    $previous = Get-DevDepotRegistryValue -Path $Path -Name $Name
    $changed  = $false

    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to '$Value'")) {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        $changed = $true
    }

    [pscustomobject]@{
        PSTypeName    = 'DevDepot.RegistryChange'
        Path          = $Path
        Name          = $Name
        PreviousValue = $previous
        NewValue      = $Value
        Changed       = $changed
    }
}

Export-ModuleMember -Function Get-DevDepotRegistryValue, Set-DevDepotRegistryValue
