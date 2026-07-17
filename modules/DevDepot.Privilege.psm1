#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Privilege and Developer Mode detection.
.DESCRIPTION
    Symbolic links normally require administrative rights; Windows 10+ Developer
    Mode allows unprivileged symlink creation. Directory junctions never need
    elevation, so DevDepot prefers junctions where possible.
#>

function Test-DevDepotElevated {
    <#
    .SYNOPSIS
        Returns $true when the current process runs with administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-DevDepotDeveloperMode {
    <#
    .SYNOPSIS
        Returns $true when Windows Developer Mode is enabled.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $key  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $name = 'AllowDevelopmentWithoutDevLicense'
    try {
        $value = (Get-ItemProperty -Path $key -Name $name -ErrorAction Stop).$name
        return [int]$value -eq 1
    } catch {
        return $false
    }
}

function Get-DevDepotPrivilege {
    <#
    .SYNOPSIS
        Returns a summary of the current privilege context.
    .OUTPUTS
        [pscustomobject] with IsElevated, DeveloperMode, CanCreateSymlink.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $elevated = Test-DevDepotElevated
    $devMode  = Test-DevDepotDeveloperMode
    [pscustomobject]@{
        PSTypeName       = 'DevDepot.Privilege'
        IsElevated       = $elevated
        DeveloperMode    = $devMode
        CanCreateSymlink = ($elevated -or $devMode)
    }
}

Export-ModuleMember -Function Test-DevDepotElevated, Test-DevDepotDeveloperMode, Get-DevDepotPrivilege
