#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Windows version and platform detection.
#>

function Get-DevDepotPlatform {
    <#
    .SYNOPSIS
        Returns information about the current operating system.
    .OUTPUTS
        [pscustomobject] with IsWindows, Caption, Version, Build, Is64Bit.
    .EXAMPLE
        (Get-DevDepotPlatform).IsWindows
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $caption = $null
    $build   = $null
    $version = [Environment]::OSVersion.Version.ToString()

    if ($IsWindows) {
        # CIM is preferred; fall back to the registry if the service is unavailable.
        try {
            $os      = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $caption = $os.Caption
            $version = $os.Version
            $build   = $os.BuildNumber
        } catch {
            try {
                $key     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
                $caption = (Get-ItemProperty -Path $key -ErrorAction Stop).ProductName
                $build   = (Get-ItemProperty -Path $key -ErrorAction Stop).CurrentBuildNumber
            } catch { }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'DevDepot.Platform'
        IsWindows  = [bool]$IsWindows
        Caption    = $caption
        Version    = $version
        Build      = $build
        Is64Bit    = [Environment]::Is64BitOperatingSystem
    }
}

function Assert-DevDepotWindows {
    <#
    .SYNOPSIS
        Throws a terminating error when not running on Windows.
    #>
    [CmdletBinding()]
    param()
    if (-not $IsWindows) {
        throw 'DevDepot only supports Windows. The current platform is not Windows.'
    }
}

Export-ModuleMember -Function Get-DevDepotPlatform, Assert-DevDepotWindows
