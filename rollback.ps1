#Requires -Version 7.0
<#
.SYNOPSIS
    Convenience wrapper: runs 'DevDepot.ps1 rollback' and forwards all parameters.
.EXAMPLE
    .\rollback.ps1 -ManifestPath .\backups
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] $Rest)
& (Join-Path $PSScriptRoot 'DevDepot.ps1') rollback @Rest
