#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Migration verification: directory statistics, content hashing and comparison.
.DESCRIPTION
    Verification runs at one of three levels (config 'verification'):
      None  - trust the copy tool.
      Stats - compare file count, directory count and total bytes (default).
      Hash  - additionally compare an order-independent SHA-256 content hash.
    Hashing is O(bytes) and can be slow for large caches, hence it is opt-in.
#>

function Get-DevDepotDirectoryStats {
    <#
    .SYNOPSIS
        Returns Exists/FileCount/DirCount/TotalBytes for a directory.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Path)

    $stats = [pscustomobject]@{
        PSTypeName = 'DevDepot.DirStats'
        Path       = $Path
        Exists     = $false
        FileCount  = 0
        DirCount   = 0
        TotalBytes = [long]0
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $stats }
    $stats.Exists = $true

    $files = [long]0; $dirs = 0; $bytes = [long]0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) { $dirs++ } else { $files++; $bytes += $_.Length }
    }
    $stats.FileCount  = $files
    $stats.DirCount   = $dirs
    $stats.TotalBytes = $bytes
    return $stats
}

function Get-DevDepotContentHash {
    <#
    .SYNOPSIS
        Computes an order-independent SHA-256 hash of a directory's contents.
    .DESCRIPTION
        Hashes the sorted set of "relativePath:length:fileSha256" lines so the
        result is stable regardless of enumeration order. Reparse points are not
        traversed to avoid loops.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $root = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd('\')

    $lines = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 } |
        ForEach-Object {
            $rel  = $_.FullName.Substring($root.Length).TrimStart('\').ToLowerInvariant()
            $fh   = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            $lines.Add(('{0}:{1}:{2}' -f $rel, $_.Length, $fh))
        }

    $sorted = $lines.ToArray() | Sort-Object
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes(($sorted -join "`n"))
    $sha    = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '')
    } finally {
        $sha.Dispose()
    }
}

function Compare-DevDepotStats {
    <#
    .SYNOPSIS
        Compares two directory-stats objects, returning Ok plus any reasons.
    .PARAMETER Expected
        Baseline stats (e.g. captured from the source before a move).
    .PARAMETER Actual
        Stats to check (e.g. the destination after a move).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Expected,
        [Parameter(Mandatory)][pscustomobject] $Actual
    )
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($Expected.FileCount -ne $Actual.FileCount) {
        $reasons.Add("File count differs (expected $($Expected.FileCount), got $($Actual.FileCount)).")
    }
    if ($Expected.TotalBytes -ne $Actual.TotalBytes) {
        $reasons.Add("Total bytes differ (expected $($Expected.TotalBytes), got $($Actual.TotalBytes)).")
    }
    [pscustomobject]@{
        Ok      = ($reasons.Count -eq 0)
        Reasons = $reasons.ToArray()
    }
}

Export-ModuleMember -Function Get-DevDepotDirectoryStats, Get-DevDepotContentHash, Compare-DevDepotStats
