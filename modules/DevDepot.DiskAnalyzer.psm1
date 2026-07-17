#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Disk and folder size analysis.
#>

function Get-DevDepotFolderSize {
    <#
    .SYNOPSIS
        Computes the total size (bytes) and file count of a directory.
    .PARAMETER Path
        Directory to measure. Missing paths return zero rather than throwing.
    .OUTPUTS
        [pscustomobject] with Path, Exists, SizeBytes, FileCount.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Path)

    $result = [pscustomobject]@{
        PSTypeName = 'DevDepot.FolderSize'
        Path       = $Path
        Exists     = $false
        SizeBytes  = [long]0
        FileCount  = 0
    }

    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $result.Exists = $true

    $sum   = [long]0
    $count = 0
    # -Force to include hidden/system files; errors (e.g. reparse loops) are skipped.
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $sum += $_.Length
            $count++
        }

    $result.SizeBytes = $sum
    $result.FileCount = $count
    return $result
}

function Get-DevDepotDriveInfo {
    <#
    .SYNOPSIS
        Returns free/total space for the drive that hosts a path.
    .PARAMETER Path
        Any path; the drive root is derived from it.
    .OUTPUTS
        [pscustomobject] with Drive, FreeBytes, TotalBytes, or $null if unknown.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Path)

    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if ([string]::IsNullOrWhiteSpace($root)) { return $null }
        $di = [System.IO.DriveInfo]::new($root)
        [pscustomobject]@{
            PSTypeName = 'DevDepot.DriveInfo'
            Drive      = $di.Name
            FreeBytes  = $di.AvailableFreeSpace
            TotalBytes = $di.TotalSize
            IsReady    = $di.IsReady
        }
    } catch {
        return $null
    }
}

Export-ModuleMember -Function Get-DevDepotFolderSize, Get-DevDepotDriveInfo
