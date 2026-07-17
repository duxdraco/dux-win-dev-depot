#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Reverses actions recorded in a migration manifest.
.DESCRIPTION
    Entries are undone in reverse order (junction removed before its move is
    reversed). Relies on the exported helpers from the Environment, Registry,
    Junction and FileMigration modules being imported into the session.
#>

function Invoke-DevDepotRollback {
    <#
    .SYNOPSIS
        Rolls back a run using its manifest.
    .PARAMETER Manifest
        Manifest object (from Import-DevDepotManifest).
    .PARAMETER Logger
        Optional DevDepot logger.
    .OUTPUTS
        [pscustomobject[]] one result per reversed entry.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Manifest,
        [object] $Logger
    )

    function Write-Log([string]$level, [string]$msg) { if ($Logger) { $Logger.$level($msg) } }

    $results = [System.Collections.Generic.List[object]]::new()
    $entries = @($Manifest.Entries)
    [array]::Reverse($entries)

    foreach ($entry in $entries) {
        $status  = 'Success'
        $message = ''
        try {
            switch ($entry.Type) {
                'Junction' {
                    if (Test-DevDepotReparsePoint -Path $entry.Path) {
                        Remove-DevDepotJunction -Path $entry.Path
                        $message = "Removed junction '$($entry.Path)'."
                    } else {
                        $status  = 'Skipped'
                        $message = "No junction at '$($entry.Path)'."
                    }
                }
                'Move' {
                    # Reverse the move: bring contents back from Target to Source.
                    if (Test-DevDepotReparsePoint -Path $entry.Source) {
                        Remove-DevDepotJunction -Path $entry.Source
                    }
                    if (Test-Path -LiteralPath $entry.Target) {
                        $r = Move-DevDepotDirectory -Source $entry.Target -Target $entry.Source -Logger $Logger
                        $message = "Restored '$($entry.Source)' ($($r.Status))."
                    } else {
                        $status  = 'Skipped'
                        $message = "Target '$($entry.Target)' missing; nothing to restore."
                    }
                }
                'EnvVar' {
                    $scope = if ($entry.PSObject.Properties.Name -contains 'Scope') { $entry.Scope } else { 'User' }
                    Restore-DevDepotEnvVar -Name $entry.Name -PreviousValue $entry.PreviousValue -Scope $scope
                    $message = "Restored env var '$($entry.Name)'."
                }
                'Registry' {
                    if ($null -ne $entry.PreviousValue) {
                        Set-DevDepotRegistryValue -Path $entry.Path -Name $entry.Name -Value $entry.PreviousValue | Out-Null
                        $message = "Restored registry '$($entry.Path)\$($entry.Name)'."
                    } else {
                        $status  = 'Skipped'
                        $message = "No previous registry value recorded for '$($entry.Name)'."
                    }
                }
                default {
                    $status  = 'Skipped'
                    $message = "Unknown entry type '$($entry.Type)'."
                }
            }
        } catch {
            $status  = 'Failed'
            $message = $_.Exception.Message
            Write-Log 'Error' "Rollback of $($entry.Type) failed: $message"
        }

        Write-Log 'Info' "[$($entry.Provider)] $($entry.Type): $message"
        $results.Add([pscustomobject]@{
            Provider = $entry.Provider
            Type     = $entry.Type
            Status   = $status
            Message  = $message
        })
    }

    return , $results.ToArray()
}

Export-ModuleMember -Function Invoke-DevDepotRollback
