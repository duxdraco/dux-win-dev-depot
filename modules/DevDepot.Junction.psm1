#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Directory junction and symbolic link management.
.DESCRIPTION
    Junctions are preferred because they do not require elevation and work for
    local directories. Symbolic links are supported for callers that need them
    but require administrator rights or Developer Mode.
#>

function Test-DevDepotReparsePoint {
    <#
    .SYNOPSIS
        Returns $true when the path exists and is a reparse point (junction/symlink).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    } catch {
        return $false
    }
}

function Get-DevDepotLinkTarget {
    <#
    .SYNOPSIS
        Returns the target of a junction or symbolic link, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-DevDepotReparsePoint -Path $Path)) { return $null }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        # PowerShell 7 exposes the resolved target via .Target / .ResolvedTarget.
        if ($item.PSObject.Properties.Name -contains 'Target' -and $item.Target) {
            return @($item.Target)[0]
        }
        return $item.LinkTarget
    } catch {
        return $null
    }
}

function New-DevDepotJunction {
    <#
    .SYNOPSIS
        Creates a directory junction (or symlink) from Path to Target, idempotently.
    .DESCRIPTION
        If Path already links to Target the call is a no-op and reports AlreadyLinked.
        If Path exists as a real directory the call fails (the caller is expected to
        move/rename it first) unless it is an empty directory, which is removed.
    .PARAMETER Path
        The link location to create (e.g. C:\Users\me\.gradle).
    .PARAMETER Target
        The real directory the link points to (e.g. D:\DevDepot\java\gradle).
    .PARAMETER LinkType
        Junction (default) or SymbolicLink.
    .OUTPUTS
        [pscustomobject] with Created, AlreadyLinked, Path, Target.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Target,
        [ValidateSet('Junction', 'SymbolicLink')][string] $LinkType = 'Junction'
    )

    $created       = $false
    $alreadyLinked = $false

    if (Test-DevDepotReparsePoint -Path $Path) {
        $current = Get-DevDepotLinkTarget -Path $Path
        if ($current -and ($current.TrimEnd('\') -ieq $Target.TrimEnd('\'))) {
            $alreadyLinked = $true
        } else {
            if ($PSCmdlet.ShouldProcess($Path, 'Remove stale reparse point')) {
                # Removing a reparse point does not touch the target's contents.
                [System.IO.Directory]::Delete($Path)
            }
        }
    } elseif (Test-Path -LiteralPath $Path) {
        $hasChildren = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count -gt 0
        if ($hasChildren) {
            throw "Cannot create link at '$Path': a non-empty directory already exists there."
        }
        if ($PSCmdlet.ShouldProcess($Path, 'Remove empty directory before linking')) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
    }

    if (-not $alreadyLinked) {
        if ($PSCmdlet.ShouldProcess($Path, "Create $LinkType -> $Target")) {
            $parent = Split-Path -Parent $Path
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            New-Item -ItemType $LinkType -Path $Path -Target $Target -ErrorAction Stop | Out-Null
            $created = $true
        }
    }

    [pscustomobject]@{
        PSTypeName    = 'DevDepot.Junction'
        Path          = $Path
        Target        = $Target
        LinkType      = $LinkType
        Created       = $created
        AlreadyLinked = $alreadyLinked
    }
}

function Remove-DevDepotJunction {
    <#
    .SYNOPSIS
        Removes a junction/symlink without deleting the target contents.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-DevDepotReparsePoint -Path $Path)) { return }
    if ($PSCmdlet.ShouldProcess($Path, 'Remove reparse point')) {
        [System.IO.Directory]::Delete($Path)
    }
}

Export-ModuleMember -Function Test-DevDepotReparsePoint, Get-DevDepotLinkTarget, New-DevDepotJunction, Remove-DevDepotJunction
