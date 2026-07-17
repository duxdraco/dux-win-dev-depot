#Requires -Version 7.0
<#
.SYNOPSIS
    Convenience wrapper: runs 'DevDepot.ps1 analyze' and forwards all parameters.
.EXAMPLE
    .\analyze.ps1
    .\analyze.ps1 -Provider gradle,npm
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] $Rest)
& (Join-Path $PSScriptRoot 'DevDepot.ps1') analyze @Rest
