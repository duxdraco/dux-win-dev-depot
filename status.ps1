#Requires -Version 7.0
<#
.SYNOPSIS
    Convenience wrapper: runs 'DevDepot.ps1 status' and forwards all parameters.
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] $Rest)
& (Join-Path $PSScriptRoot 'DevDepot.ps1') status @Rest
