#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the DevDepot test suite (Pester 5) and, if available, PSScriptAnalyzer.
.DESCRIPTION
    Fails with a clear message if Pester 5+ is not installed. Intended for local
    use and CI.
.EXAMPLE
    pwsh -File .\tests\Invoke-Tests.ps1
#>
[CmdletBinding()]
param([switch] $SkipAnalyzer)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

$pester = Get-Module -ListAvailable Pester | Where-Object Version -ge ([version]'5.0.0') | Select-Object -First 1
if (-not $pester) {
    throw "Pester 5+ is required. Install with: Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0.0 -Force"
}
Import-Module $pester

$config = New-PesterConfiguration
$config.Run.Path        = $PSScriptRoot
$config.Run.Exit        = $false
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if (-not $SkipAnalyzer) {
    $psa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
    if ($psa) {
        Import-Module $psa
        Write-Host "`nRunning PSScriptAnalyzer..." -ForegroundColor Cyan
        $settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
        $issues = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Settings $settings
        if ($issues) {
            $issues | Format-Table -AutoSize | Out-String | Write-Host
        } else {
            Write-Host 'PSScriptAnalyzer: clean.' -ForegroundColor Green
        }
    } else {
        Write-Host 'PSScriptAnalyzer not installed; skipping lint.' -ForegroundColor Yellow
    }
}

if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) test(s) failed."
}
Write-Host "`nAll $($result.PassedCount) test(s) passed." -ForegroundColor Green
