#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Guard rails that prevent destructive or nonsensical migrations.
#>

# Paths that must never be used as a migration source. Case-insensitive prefixes.
$script:ForbiddenSourcePrefixes = @(
    "$env:SystemRoot",
    "$env:ProgramFiles",
    "${env:ProgramFiles(x86)}",
    "$env:SystemDrive\"                       # bare drive root
) | Where-Object { $_ }

function Test-DevDepotSafeSource {
    <#
    .SYNOPSIS
        Validates that a path is safe to use as a migration source.
    .DESCRIPTION
        Rejects system/root/Program Files locations and drive roots. Returns an
        object with IsSafe and Reason so callers can log and skip gracefully.
    .PARAMETER Path
        Candidate source path (already expanded).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Path)

    $reason = $null
    $full   = $Path.TrimEnd('\')

    if ([string]::IsNullOrWhiteSpace($full)) {
        $reason = 'Path is empty.'
    } elseif ($full -match '^[A-Za-z]:$') {
        $reason = 'Path is a bare drive root.'
    } else {
        foreach ($prefix in $script:ForbiddenSourcePrefixes) {
            $p = $prefix.TrimEnd('\')
            if ($full -ieq $p) {
                $reason = "Path equals a protected system location ('$p')."
                break
            }
        }
        # Windows directory itself and its subtree are always protected.
        if (-not $reason -and $env:SystemRoot -and $full.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $reason = 'Path is inside the Windows directory.'
        }
    }

    [pscustomobject]@{
        Path   = $Path
        IsSafe = ($null -eq $reason)
        Reason = $reason
    }
}

function Test-DevDepotSafeTarget {
    <#
    .SYNOPSIS
        Validates a migration target: the drive must exist and not be the source path.
    .PARAMETER Target
        Candidate target path.
    .PARAMETER Source
        The source being migrated (target must differ).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Target,
        [string] $Source
    )

    $reason = $null
    $root   = [System.IO.Path]::GetPathRoot($Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        $reason = 'Target is empty.'
    } elseif ([string]::IsNullOrWhiteSpace($root)) {
        $reason = 'Target has no drive root.'
    } elseif (-not (Test-Path -LiteralPath $root)) {
        $reason = "Target drive '$root' does not exist."
    } elseif ($Source -and ($Target.TrimEnd('\') -ieq $Source.TrimEnd('\'))) {
        $reason = 'Target is identical to source.'
    } elseif ($Source -and $Target.TrimEnd('\').StartsWith($Source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $reason = 'Target is nested inside source.'
    }

    [pscustomobject]@{
        Target = $Target
        IsSafe = ($null -eq $reason)
        Reason = $reason
    }
}

Export-ModuleMember -Function Test-DevDepotSafeSource, Test-DevDepotSafeTarget
