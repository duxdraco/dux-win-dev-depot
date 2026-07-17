#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    End-to-end migration, idempotency and state-based rollback tests (Pester 5).
.DESCRIPTION
    Exercises the transactional engine and the state database against temp
    directories: migrate, verify idempotency, validate, then roll back from state.
#>
Set-StrictMode -Version Latest

BeforeAll {
    $script:ModulesDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'modules'
    Import-Module (Join-Path $script:ModulesDir 'DevDepot.psm1') -Force -DisableNameChecking
    $script:EnvName = 'DEVDEPOT_TEST_CACHE'

    function New-Sandbox {
        $base   = Join-Path $env:TEMP ("dd-it-" + [guid]::NewGuid())
        $source = Join-Path $base 'src\cache'
        $root   = Join-Path $base 'root'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'a.txt') -Value 'alpha'
        New-Item -ItemType Directory -Path (Join-Path $source 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sub\b.txt') -Value 'bravo'
        [pscustomobject]@{ Base = $base; Source = $source; Root = $root }
    }
    function New-TestConfig ($root) {
        [pscustomobject]@{
            root = $root; linkStrategy = 'Both'; envVarScope = 'User'; logLevel = 'Error'
            verification = 'Stats'; safetyLevel = 'Safe'; createJunctions = $true
            defaultProviderOn = $true; providers = @{}; exclude = @()
        }
    }
    function New-TestProvider ($source) {
        @{ Id = 'test'; Name = 'Test'; Category = 'Test'
           Mappings = @(@{ Source = $source; TargetSubPath = 'test\cache'; EnvVar = $script:EnvName; Strategy = 'Both' }) }
    }
}

AfterEach {
    [Environment]::SetEnvironmentVariable($script:EnvName, $null, 'User')
    [Environment]::SetEnvironmentVariable($script:EnvName, $null, 'Process')
}

Describe 'Transactional migration + state' {
    It 'migrates, verifies, records state, is idempotent, then rolls back' {
        $sb = New-Sandbox
        try {
            $log   = New-DevDepotLogger -LogDirectory $env:TEMP -Quiet -MinimumLevel Error
            $state = Import-DevDepotState -BasePath $sb.Base -Root $sb.Root
            $ctx   = New-DevDepotContext -Config (New-TestConfig $sb.Root) -Logger $log -State $state -PowerShellVersion '7.4'
            $p     = New-TestProvider $sb.Source
            $target = Join-Path $sb.Root 'test\cache'

            $m = Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx
            $m.Status | Should -Be 'Success'
            Test-Path (Join-Path $target 'sub\b.txt')  | Should -BeTrue
            Test-DevDepotReparsePoint -Path $sb.Source | Should -BeTrue
            [Environment]::GetEnvironmentVariable($script:EnvName, 'User') | Should -Be $target
            (Get-DevDepotProviderState -State $state -ProviderId 'test') | Should -Not -BeNullOrEmpty

            # Idempotent second run: nothing left to move.
            $m2 = Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx
            $m2.Details.MovedBytes | Should -Be 0

            # Validate clean.
            (Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $ctx).Details.Issues.Count | Should -Be 0

            # Roll back from state.
            Invoke-DevDepotStateRollback -State $state -Logger $log | Out-Null
            Test-DevDepotReparsePoint -Path $sb.Source           | Should -BeFalse
            Test-Path (Join-Path $sb.Source 'a.txt')             | Should -BeTrue
            [Environment]::GetEnvironmentVariable($script:EnvName, 'User') | Should -BeNullOrEmpty
        } finally {
            Remove-Item -LiteralPath $sb.Base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Transaction rollback on failure' {
    It 'undoes committed operations when a later operation fails' {
        $sb = New-Sandbox
        try {
            $log = New-DevDepotLogger -LogDirectory $env:TEMP -Quiet -MinimumLevel Error
            $ctx = New-DevDepotContext -Config (New-TestConfig $sb.Root) -Logger $log -PowerShellVersion '7.4'

            $envName = 'DEVDEPOT_TX_FAIL'
            $good = New-DevDepotEnvVarOperation -Name $envName -Value 'V1' -Scope 'User'
            $bad  = New-DevDepotOperation -Type 'Boom' -Description 'always fails' `
                -Do { param($c) @{ type = 'Boom' } } -Verify { param($c, $r) @{ Ok = $false; Reasons = , @('forced') } } -Undo { param($c, $r) }
            try {
                $tx = Invoke-DevDepotTransaction -Context $ctx -ProviderId 'test' -Operations @($good, $bad)
                $tx.Status     | Should -Be 'Failed'
                $tx.RolledBack | Should -BeTrue
                # The good env var must have been undone.
                [Environment]::GetEnvironmentVariable($envName, 'User') | Should -BeNullOrEmpty
            } finally {
                [Environment]::SetEnvironmentVariable($envName, $null, 'User')
            }
        } finally {
            Remove-Item -LiteralPath $sb.Base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
