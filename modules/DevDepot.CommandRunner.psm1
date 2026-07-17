#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Safe execution and discovery of external commands.
#>

function Test-DevDepotCommand {
    <#
    .SYNOPSIS
        Returns $true when a command/executable is resolvable on PATH.
    .PARAMETER Name
        Command name (e.g. 'node', 'gradle').
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-DevDepotCommand {
    <#
    .SYNOPSIS
        Runs an external command capturing stdout, stderr and exit code.
    .DESCRIPTION
        Honours -WhatIf: in simulation mode the command is not executed and a
        result with ExitCode 0 and Simulated = $true is returned.
    .PARAMETER FilePath
        Executable to run.
    .PARAMETER Arguments
        Argument array.
    .PARAMETER Logger
        Optional DevDepot logger for trace output.
    .OUTPUTS
        [pscustomobject] with ExitCode, StdOut, StdErr, Simulated.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string[]] $Arguments = @(),
        [object] $Logger
    )

    $display = ('{0} {1}' -f $FilePath, ($Arguments -join ' ')).Trim()
    if ($Logger) { $Logger.Trace("Run: $display") }

    if (-not $PSCmdlet.ShouldProcess($display, 'Execute command')) {
        return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = ''; Simulated = $true }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $FilePath
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    [pscustomobject]@{
        ExitCode  = $proc.ExitCode
        StdOut    = $stdout
        StdErr    = $stderr
        Simulated = $false
    }
}

Export-ModuleMember -Function Test-DevDepotCommand, Invoke-DevDepotCommand
