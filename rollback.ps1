#Requires -Version 7.0
<#
.SYNOPSIS
    Convenience wrapper: runs 'DevDepot.ps1 rollback' and forwards all parameters.
.DESCRIPTION
    Rollback uses the state database under .state/. Restrict to one provider with
    -Provider <id>.
.EXAMPLE
    .\rollback.ps1
    .\rollback.ps1 -Provider gradle
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] $Rest)
& (Join-Path $PSScriptRoot 'DevDepot.ps1') rollback @Rest
