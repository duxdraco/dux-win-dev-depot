#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    End-to-end migration, idempotency and rollback tests using temp directories.
.DESCRIPTION
    Exercises the real engine against a synthetic provider so that Migrate,
    Validate and rollback are verified against the file system and environment.
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
        [pscustomobject]@{ Base=$base; Source=$source; Root=$root }
    }

    function New-TestContext ($root, $manifest) {
        $cfg = [pscustomobject]@{
            root=$root; linkStrategy='Both'; envVarScope='User'; logLevel='Error'
            createJunctions=$true; defaultProviderOn=$true; providers=@{}; exclude=@()
        }
        $log = New-DevDepotLogger -LogDirectory $env:TEMP -Quiet -MinimumLevel Error
        New-DevDepotContext -Config $cfg -Logger $log -Manifest $manifest
    }

    function New-TestProvider ($source) {
        @{
            Id='test'; Name='Test'; Category='Test'
            Mappings=@(@{ Source=$source; TargetSubPath='test\cache'; EnvVar=$script:EnvName; Strategy='Both' })
        }
    }
}

AfterEach {
    # Guarantee the test env var never leaks between tests.
    [Environment]::SetEnvironmentVariable($script:EnvName, $null, 'User')
    [Environment]::SetEnvironmentVariable($script:EnvName, $null, 'Process')
}

Describe 'Migration engine (integration)' {
    It 'moves data, creates a junction and sets the env var' {
        $sb = New-Sandbox
        try {
            $m   = New-DevDepotManifest -Root $sb.Root -BackupDirectory (Join-Path $sb.Base 'backups')
            $ctx = New-TestContext $sb.Root $m
            $p   = New-TestProvider $sb.Source

            $r = Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx
            $r.Status | Should -BeIn @('Success','Warning')

            $target = Join-Path $sb.Root 'test\cache'
            Test-Path (Join-Path $target 'a.txt')      | Should -BeTrue
            Test-Path (Join-Path $target 'sub\b.txt')  | Should -BeTrue
            Test-DevDepotReparsePoint -Path $sb.Source | Should -BeTrue
            (Get-DevDepotLinkTarget -Path $sb.Source).TrimEnd('\') | Should -Be $target.TrimEnd('\')
            [Environment]::GetEnvironmentVariable($script:EnvName,'User') | Should -Be $target
        } finally {
            Remove-Item -LiteralPath $sb.Base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is idempotent when run twice' {
        $sb = New-Sandbox
        try {
            $m   = New-DevDepotManifest -Root $sb.Root -BackupDirectory (Join-Path $sb.Base 'backups')
            $ctx = New-TestContext $sb.Root $m
            $p   = New-TestProvider $sb.Source

            Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx | Out-Null
            $second = Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx
            $second.Status                    | Should -BeIn @('Success','Warning')
            $second.Details.MovedBytes        | Should -Be 0   # nothing left to move
        } finally {
            Remove-Item -LiteralPath $sb.Base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'validates cleanly after migration' {
        $sb = New-Sandbox
        try {
            $m   = New-DevDepotManifest -Root $sb.Root -BackupDirectory (Join-Path $sb.Base 'backups')
            $ctx = New-TestContext $sb.Root $m
            $p   = New-TestProvider $sb.Source
            Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx | Out-Null
            $v = Invoke-DevDepotProviderAction -Provider $p -Action 'Validate' -Context $ctx
            @($v.Details.Issues).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $sb.Base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Rollback (integration)' {
    It 'restores data, removes the junction and clears the env var' {
        $sb = New-Sandbox
        try {
            $m   = New-DevDepotManifest -Root $sb.Root -BackupDirectory (Join-Path $sb.Base 'backups')
            $ctx = New-TestContext $sb.Root $m
            $p   = New-TestProvider $sb.Source
            Invoke-DevDepotProviderAction -Provider $p -Action 'Migrate' -Context $ctx | Out-Null

            Invoke-DevDepotRollback -Manifest $m -Logger $ctx.Logger | Out-Null

            Test-DevDepotReparsePoint -Path $sb.Source          | Should -BeFalse
            Test-Path (Join-Path $sb.Source 'a.txt')            | Should -BeTrue
            Test-Path (Join-Path $sb.Source 'sub\b.txt')        | Should -BeTrue
            [Environment]::GetEnvironmentVariable($script:EnvName,'User') | Should -BeNullOrEmpty
        } finally {
            Remove-Item -LiteralPath $sb.Base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
