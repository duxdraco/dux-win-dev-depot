#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Transactional migration engine: operations with Do/Undo/Verify semantics.
.DESCRIPTION
    A MigrationTransaction executes an ordered list of operations. Each operation
    is applied then verified; if any operation fails to apply or verify, all
    previously-committed operations in the transaction are undone in reverse order
    so nothing is left partially migrated. Committed operation records are returned
    for persistence in the state database.

    Safety levels (Safe < Conservative < Aggressive < Experimental) gate which
    operations run: an operation is executed only if its level is at or below the
    configured ceiling.
#>

$script:SafetyOrder = @{ Safe = 0; Conservative = 1; Aggressive = 2; Experimental = 3 }

function Test-DevDepotSafetyAllowed {
    <#
    .SYNOPSIS
        Returns $true when OperationLevel is permitted under Ceiling.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $OperationLevel,
        [Parameter(Mandatory)][string] $Ceiling
    )
    $o = if ($script:SafetyOrder.ContainsKey($OperationLevel)) { $script:SafetyOrder[$OperationLevel] } else { 0 }
    $c = if ($script:SafetyOrder.ContainsKey($Ceiling)) { $script:SafetyOrder[$Ceiling] } else { 0 }
    return $o -le $c
}

function New-DevDepotOperation {
    <#
    .SYNOPSIS
        Builds an operation with Do/Undo/Verify script blocks.
    .DESCRIPTION
        Do    : { param($ctx) ... }        -> returns a serializable record hashtable
        Verify: { param($ctx,$record) ...} -> returns @{ Ok=[bool]; Reasons=@() }
        Undo  : { param($ctx,$record) ...} -> reverses the operation
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Type,
        [Parameter(Mandatory)][string] $Description,
        [Parameter(Mandatory)][scriptblock] $Do,
        [Parameter(Mandatory)][scriptblock] $Verify,
        [Parameter(Mandatory)][scriptblock] $Undo,
        [string] $SafetyLevel = 'Safe',
        [long] $EstimatedBytes = 0
    )
    [pscustomobject]@{
        PSTypeName     = 'DevDepot.Operation'
        Type           = $Type
        Description    = $Description
        SafetyLevel    = $SafetyLevel
        EstimatedBytes = $EstimatedBytes
        Do             = $Do
        Verify         = $Verify
        Undo           = $Undo
        Record         = $null
        State          = 'Pending'
    }
}

function New-DevDepotMoveOperation {
    <#
    .SYNOPSIS
        Operation that moves a directory's contents and verifies the copy.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Target,
        [long] $EstimatedBytes = 0
    )
    New-DevDepotOperation -Type 'Move' -Description "Move $Source -> $Target" -EstimatedBytes $EstimatedBytes -Do ({
        param($ctx)
        $before = Get-DevDepotDirectoryStats -Path $Source
        $hash   = if ($ctx.Config.verification -eq 'Hash') { Get-DevDepotContentHash -Path $Source } else { '' }
        $mv     = Move-DevDepotDirectory -Source $Source -Target $Target -Logger $ctx.Logger
        if ($mv.Status -eq 'Failed') { throw "Move failed: $($mv.Message)" }
        @{
            type = 'Move'; source = $Source; target = $Target
            fileCount = $before.FileCount; dirCount = $before.DirCount; bytes = $before.TotalBytes
            sourceHash = $hash; movedStatus = $mv.Status
        }
    }).GetNewClosure() -Verify {
        param($ctx, $rec)
        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($ctx.Config.verification -ne 'None') {
            $after = Get-DevDepotDirectoryStats -Path $rec.target
            if (-not $after.Exists) { $reasons.Add('Target directory missing after move.') }
            if ($after.FileCount -ne $rec.fileCount) { $reasons.Add("File count mismatch (src $($rec.fileCount) / dst $($after.FileCount)).") }
            if ($after.TotalBytes -ne $rec.bytes)    { $reasons.Add("Byte count mismatch (src $($rec.bytes) / dst $($after.TotalBytes)).") }
            if ($ctx.Config.verification -eq 'Hash' -and $rec.sourceHash) {
                $dstHash = Get-DevDepotContentHash -Path $rec.target
                if ($dstHash -ne $rec.sourceHash) { $reasons.Add('Content hash mismatch after move.') }
            }
        }
        @{ Ok = ($reasons.Count -eq 0); Reasons = $reasons.ToArray() }
    } -Undo {
        param($ctx, $rec)
        if (Test-DevDepotReparsePoint -Path $rec.source) { Remove-DevDepotJunction -Path $rec.source }
        if (Test-Path -LiteralPath $rec.target) {
            Move-DevDepotDirectory -Source $rec.target -Target $rec.source -Logger $ctx.Logger | Out-Null
        }
    }
}

function New-DevDepotEnvVarOperation {
    <#
    .SYNOPSIS
        Operation that sets an environment variable and verifies it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Value,
        [ValidateSet('User', 'Machine')][string] $Scope = 'User'
    )
    New-DevDepotOperation -Type 'EnvVar' -Description "Set $Scope env $Name=$Value" -Do ({
        param($ctx)
        $change = Set-DevDepotEnvVar -Name $Name -Value $Value -Scope $Scope
        @{ type = 'EnvVar'; name = $Name; scope = $Scope; previousValue = $change.PreviousValue; newValue = $Value }
    }).GetNewClosure() -Verify {
        param($ctx, $rec)
        $cur = Get-DevDepotEnvVar -Name $rec.name -Scope $rec.scope
        $ok  = ($cur -eq $rec.newValue)
        @{ Ok = $ok; Reasons = @(if (-not $ok) { "Env '$($rec.name)' is '$cur', expected '$($rec.newValue)'." }) }
    } -Undo {
        param($ctx, $rec)
        Restore-DevDepotEnvVar -Name $rec.name -PreviousValue $rec.previousValue -Scope $rec.scope
    }
}

function New-DevDepotJunctionOperation {
    <#
    .SYNOPSIS
        Operation that creates a junction and verifies its target.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Target
    )
    New-DevDepotOperation -Type 'Junction' -Description "Junction $Path -> $Target" -Do ({
        param($ctx)
        $j = New-DevDepotJunction -Path $Path -Target $Target
        @{ type = 'Junction'; path = $Path; target = $Target; created = [bool]$j.Created }
    }).GetNewClosure() -Verify {
        param($ctx, $rec)
        $reasons = [System.Collections.Generic.List[string]]::new()
        if (-not (Test-DevDepotReparsePoint -Path $rec.path)) {
            $reasons.Add("No junction at '$($rec.path)'.")
        } else {
            $t = Get-DevDepotLinkTarget -Path $rec.path
            if (-not $t -or ($t.TrimEnd('\') -ine $rec.target.TrimEnd('\'))) {
                $reasons.Add("Junction points to '$t', expected '$($rec.target)'.")
            }
        }
        @{ Ok = ($reasons.Count -eq 0); Reasons = $reasons.ToArray() }
    } -Undo {
        param($ctx, $rec)
        Remove-DevDepotJunction -Path $rec.path
    }
}

function Invoke-DevDepotTransaction {
    <#
    .SYNOPSIS
        Executes operations atomically: apply+verify each, rolling back all on failure.
    .PARAMETER Context
        DevDepot context (carries Logger, Config, Simulate).
    .PARAMETER ProviderId
        Owning provider id (for logging/state).
    .PARAMETER Operations
        Ordered operation objects (from New-DevDepot*Operation).
    .OUTPUTS
        [pscustomobject] Status, Committed (records), RolledBack, FailedOperation,
        Error, Bytes, Skipped.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][string] $ProviderId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Operations
    )

    $log       = $Context.Logger
    $ceiling   = if ($Context.Config.PSObject.Properties.Name -contains 'safetyLevel') { $Context.Config.safetyLevel } else { 'Safe' }
    $completed = [System.Collections.Generic.List[object]]::new()
    $bytes     = [long]0
    $skipped   = [System.Collections.Generic.List[string]]::new()

    foreach ($op in $Operations) {
        if (-not (Test-DevDepotSafetyAllowed -OperationLevel $op.SafetyLevel -Ceiling $ceiling)) {
            $op.State = 'Skipped'
            $skipped.Add("$($op.Type):$($op.SafetyLevel)")
            $log.Debug("[$ProviderId] Skipping '$($op.Description)' (safety $($op.SafetyLevel) > ceiling $ceiling).")
            continue
        }

        if ($Context.Simulate) {
            $op.State = 'Simulated'
            $bytes += $op.EstimatedBytes
            $log.Info("[$ProviderId] (simulate) $($op.Description)")
            continue
        }

        try {
            $log.Debug("[$ProviderId] apply: $($op.Description)")
            $record   = & $op.Do $Context
            $op.Record = $record
            $op.State  = 'Applied'

            $v = & $op.Verify $Context $record
            if (-not $v.Ok) { throw ("verification failed: {0}" -f (@($v.Reasons) -join '; ')) }
            $op.State = 'Verified'

            if ($record -is [hashtable] -and $record.ContainsKey('bytes')) { $bytes += [long]$record['bytes'] }
            $completed.Add($op)
        } catch {
            $failMsg = $_.Exception.Message
            $log.Error("[$ProviderId] operation '$($op.Type)' failed: $failMsg. Rolling back transaction.")

            # Undo the failing op if it partially applied, then all completed ops in reverse.
            if ($op.State -in @('Applied', 'Verified') -and $op.Record) {
                try { & $op.Undo $Context $op.Record } catch { $log.Warn("[$ProviderId] undo of failing op failed: $($_.Exception.Message)") }
            }
            for ($i = $completed.Count - 1; $i -ge 0; $i--) {
                $c = $completed[$i]
                try { & $c.Undo $Context $c.Record; $log.Debug("[$ProviderId] undid $($c.Type).") }
                catch { $log.Warn("[$ProviderId] undo of '$($c.Type)' failed: $($_.Exception.Message)") }
            }

            return [pscustomobject]@{
                Status          = 'Failed'
                Committed       = @()
                RolledBack      = $true
                FailedOperation = $op.Type
                Error           = $failMsg
                Bytes           = [long]0
                Skipped         = $skipped.ToArray()
            }
        }
    }

    $status = if ($Context.Simulate) { 'Simulated' } else { 'Success' }
    [pscustomobject]@{
        Status          = $status
        Committed       = @($completed | ForEach-Object { $_.Record })
        RolledBack      = $false
        FailedOperation = $null
        Error           = $null
        Bytes           = $bytes
        Skipped         = $skipped.ToArray()
    }
}

Export-ModuleMember -Function Test-DevDepotSafetyAllowed, New-DevDepotOperation, New-DevDepotMoveOperation,
    New-DevDepotEnvVarOperation, New-DevDepotJunctionOperation, Invoke-DevDepotTransaction
