#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Detection helpers used by providers to decide whether a tool is present.
#>

function Test-DevDepotDetectionHints {
    <#
    .SYNOPSIS
        Evaluates detection hints (commands and/or paths).
    .DESCRIPTION
        A provider is considered "detected" when ANY listed command resolves on
        PATH OR ANY listed path exists. Path hints may contain %VAR% tokens.
    .PARAMETER Commands
        Command names to probe.
    .PARAMETER Paths
        File-system paths to probe (env tokens expanded).
    .OUTPUTS
        [pscustomobject] with Detected, MatchedCommands, MatchedPaths.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Commands = @(),
        [string[]] $Paths = @()
    )

    $matchedCommands = foreach ($c in $Commands) {
        if (Get-Command -Name $c -ErrorAction SilentlyContinue) { $c }
    }
    $matchedPaths = foreach ($p in $Paths) {
        $expanded = [Environment]::ExpandEnvironmentVariables($p)
        if (Test-Path -LiteralPath $expanded) { $expanded }
    }

    $matchedCommands = @($matchedCommands)
    $matchedPaths    = @($matchedPaths)

    [pscustomobject]@{
        Detected        = (($matchedCommands.Count + $matchedPaths.Count) -gt 0)
        MatchedCommands = $matchedCommands
        MatchedPaths    = $matchedPaths
    }
}

Export-ModuleMember -Function Test-DevDepotDetectionHints
