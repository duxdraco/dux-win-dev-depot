#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Robocopy-based directory migration with verification and idempotency.
.DESCRIPTION
    Uses robocopy /MOVE /E for resilient, resumable moves. Robocopy exit codes
    below 8 indicate success (files copied, extra files, etc.); 8 and above are
    genuine failures.
#>

function Test-DevDepotRobocopy {
    <#
    .SYNOPSIS
        Returns $true when robocopy.exe is available.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool](Get-Command -Name 'robocopy.exe' -ErrorAction SilentlyContinue)
}

function Move-DevDepotDirectory {
    <#
    .SYNOPSIS
        Moves the contents of a source directory to a target directory.
    .DESCRIPTION
        Idempotent: if the source is already a reparse point (previously migrated)
        or does not exist, the move is skipped. The source directory shell is
        removed after a successful move so a junction can be created in its place.
    .PARAMETER Source
        Directory to move from.
    .PARAMETER Target
        Directory to move into (created if missing).
    .PARAMETER Logger
        Optional DevDepot logger.
    .OUTPUTS
        [pscustomobject] with Status, BytesMoved, Source, Target.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Target,
        [object] $Logger
    )

    function Write-Log([string]$level, [string]$msg) {
        if ($Logger) { $Logger.$level($msg) }
    }

    $result = [pscustomobject]@{
        PSTypeName = 'DevDepot.MoveResult'
        Source     = $Source
        Target     = $Target
        Status     = 'Skipped'
        BytesMoved = [long]0
        Message    = ''
    }

    # Already migrated (source replaced by a link) -> nothing to do.
    $srcItem = if (Test-Path -LiteralPath $Source) { Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue } else { $null }
    if ($srcItem -and (($srcItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        $result.Message = 'Source is already a reparse point; migration skipped.'
        return $result
    }

    if (-not (Test-Path -LiteralPath $Source)) {
        $result.Message = 'Source directory does not exist; nothing to move.'
        return $result
    }

    if (-not (Test-DevDepotRobocopy)) {
        throw 'robocopy.exe is required for file migration but was not found.'
    }

    # Measure before moving so we can report bytes moved.
    $bytes = [long]0
    Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $bytes += $_.Length }

    if (-not $PSCmdlet.ShouldProcess("$Source -> $Target", 'Move directory contents')) {
        $result.Status     = 'Simulated'
        $result.BytesMoved = $bytes
        $result.Message    = "Would move $bytes bytes."
        return $result
    }

    if (-not (Test-Path -LiteralPath $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    Write-Log 'Info' "Moving '$Source' -> '$Target' ($bytes bytes)"
    $roboArgs = @($Source, $Target, '/MOVE', '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    & robocopy.exe @roboArgs | Out-Null
    $code = $LASTEXITCODE

    if ($code -ge 8) {
        $result.Status  = 'Failed'
        $result.Message = "robocopy failed with exit code $code."
        Write-Log 'Error' $result.Message
        return $result
    }

    # Robocopy /MOVE empties the source but may leave the top-level directory.
    if ((Test-Path -LiteralPath $Source) -and
        (@(Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -LiteralPath $Source -Force -Recurse -ErrorAction SilentlyContinue
    }

    $result.Status     = 'Success'
    $result.BytesMoved = $bytes
    $result.Message    = "Moved $bytes bytes (robocopy exit $code)."
    Write-Log 'Info' $result.Message
    return $result
}

Export-ModuleMember -Function Test-DevDepotRobocopy, Move-DevDepotDirectory
