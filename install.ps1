#Requires -Version 7.0
<#
.SYNOPSIS
    Convenience wrapper: runs 'DevDepot.ps1 install' and forwards all parameters.
.DESCRIPTION
    Use -WhatIf to preview the migration without making changes.
.EXAMPLE
    .\install.ps1 -WhatIf
    .\install.ps1
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] $Rest)
& (Join-Path $PSScriptRoot 'DevDepot.ps1') install @Rest
