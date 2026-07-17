#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    DevDepot bootstrap module. Imports every core module in dependency order.
.DESCRIPTION
    Import this single module (or dot-source Import-DevDepotCore) to make all
    DevDepot functionality available. Order matters: Common first, then leaf
    utilities, then modules that depend on them, then the provider engine.
#>

$script:ModuleRoot = $PSScriptRoot

# Dependency-ordered list of core modules.
$script:CoreModules = @(
    'DevDepot.Common.psm1'
    'DevDepot.Logger.psm1'
    'DevDepot.Platform.psm1'
    'DevDepot.Privilege.psm1'
    'DevDepot.CommandRunner.psm1'
    'DevDepot.DiskAnalyzer.psm1'
    'DevDepot.Environment.psm1'
    'DevDepot.Registry.psm1'
    'DevDepot.Junction.psm1'
    'DevDepot.FileMigration.psm1'
    'DevDepot.Detection.psm1'
    'DevDepot.Safety.psm1'
    'DevDepot.Config.psm1'
    'DevDepot.Report.psm1'
    'DevDepot.Verify.psm1'
    'DevDepot.State.psm1'
    'DevDepot.Transaction.psm1'
    'DevDepot.Rollback.psm1'
    'DevDepot.Provider.psm1'
)

function Import-DevDepotCore {
    <#
    .SYNOPSIS
        Imports all DevDepot core modules into the current session.
    .PARAMETER Force
        Re-import modules even if already loaded.
    #>
    [CmdletBinding()]
    param([switch] $Force)
    foreach ($name in $script:CoreModules) {
        $path = Join-Path $script:ModuleRoot $name
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Core module not found: $path"
        }
        Import-Module -Name $path -Global -Force:$Force -DisableNameChecking
    }
}

Import-DevDepotCore

Export-ModuleMember -Function Import-DevDepotCore
