#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Reverses migrations recorded in the state database.
.DESCRIPTION
    Operations are undone in reverse order (junction removed before its move is
    reversed). Relies on the exported helpers from the Environment, Junction,
    FileMigration and State modules being imported into the session.
#>

function Get-DevDepotRecordField {
    # Reads a field from an operation record that may be a hashtable (in-memory)
    # or a PSCustomObject (loaded from state.json).
    param([object] $Record, [string] $Name)
    if ($Record -is [hashtable]) {
        if ($Record.ContainsKey($Name)) { return $Record[$Name] }
        return $null
    }
    $prop = $Record.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Invoke-DevDepotStateRollback {
    <#
    .SYNOPSIS
        Rolls back migrations using the state database (not by scanning Windows).
    .PARAMETER State
        State object from Import-DevDepotState.
    .PARAMETER Logger
        Optional DevDepot logger.
    .PARAMETER ProviderId
        Restrict rollback to a single provider; default rolls back all.
    .OUTPUTS
        [pscustomobject[]] one result per reversed operation.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][pscustomobject] $State,
        [object] $Logger,
        [string] $ProviderId
    )
    function Write-Log([string]$level, [string]$msg) { if ($Logger) { $Logger.$level($msg) } }

    $results = [System.Collections.Generic.List[object]]::new()
    $ids     = if ($ProviderId) { @($ProviderId) } else { @($State.Providers.Keys) }

    foreach ($id in $ids) {
        $ps = Get-DevDepotProviderState -State $State -ProviderId $id
        if (-not $ps) { continue }

        # Reverse operation order within the provider.
        $ops = @($ps.operations)
        [array]::Reverse($ops)
        foreach ($op in $ops) {
            $type    = Get-DevDepotRecordField -Record $op -Name 'type'
            $status  = 'Success'
            $message = ''
            try {
                switch ($type) {
                    'Junction' {
                        $path = Get-DevDepotRecordField -Record $op -Name 'path'
                        if (Test-DevDepotReparsePoint -Path $path) { Remove-DevDepotJunction -Path $path; $message = "Removed junction '$path'." }
                        else { $status = 'Skipped'; $message = "No junction at '$path'." }
                    }
                    'Move' {
                        $src = Get-DevDepotRecordField -Record $op -Name 'source'
                        $tgt = Get-DevDepotRecordField -Record $op -Name 'target'
                        if (Test-DevDepotReparsePoint -Path $src) { Remove-DevDepotJunction -Path $src }
                        if (Test-Path -LiteralPath $tgt) {
                            Move-DevDepotDirectory -Source $tgt -Target $src -Logger $Logger | Out-Null
                            $message = "Restored '$src'."
                        } else { $status = 'Skipped'; $message = "Target '$tgt' missing." }
                    }
                    'EnvVar' {
                        $name  = Get-DevDepotRecordField -Record $op -Name 'name'
                        $scope = Get-DevDepotRecordField -Record $op -Name 'scope'
                        if (-not $scope) { $scope = 'User' }
                        Restore-DevDepotEnvVar -Name $name -PreviousValue (Get-DevDepotRecordField -Record $op -Name 'previousValue') -Scope $scope
                        $message = "Restored env var '$name'."
                    }
                    default { $status = 'Skipped'; $message = "Unknown operation '$type'." }
                }
            } catch {
                $status = 'Failed'; $message = $_.Exception.Message
                Write-Log 'Error' "[$id] rollback of $type failed: $message"
            }
            Write-Log 'Info' "[$id] ${type}: $message"
            $results.Add([pscustomobject]@{ Provider = $id; Type = $type; Status = $status; Message = $message })
        }

        Remove-DevDepotProviderState -State $State -ProviderId $id
    }

    return , $results.ToArray()
}

Export-ModuleMember -Function Invoke-DevDepotStateRollback
