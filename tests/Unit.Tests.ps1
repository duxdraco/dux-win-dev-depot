#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Unit tests for DevDepot core modules (Pester 5).
#>
Set-StrictMode -Version Latest

BeforeAll {
    $script:ModulesDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'modules'
    Import-Module (Join-Path $script:ModulesDir 'DevDepot.psm1') -Force -DisableNameChecking
}

Describe 'Common' {
    It 'formats bytes into human units' {
        Format-DevDepotSize 0            | Should -Be '0 B'
        Format-DevDepotSize 1024         | Should -Be '1.0 KB'
        Format-DevDepotSize 1536         | Should -Be '1.5 KB'
        (Format-DevDepotSize 1073741824) | Should -Be '1.0 GB'
    }
    It 'expands environment tokens' {
        Expand-DevDepotPath '%USERPROFILE%\.gradle' | Should -Be (Join-Path $env:USERPROFILE '.gradle')
    }
    It 'builds a well-formed result object' {
        $r = New-DevDepotResult -Provider 'x' -Action 'Migrate' -Status 'Success' -Message 'ok'
        $r.Provider | Should -Be 'x'
        $r.Status   | Should -Be 'Success'
    }
}

Describe 'Config' {
    It 'returns defaults when no file is supplied' {
        $c = Import-DevDepotConfig
        $c.linkStrategy | Should -Be 'Both'
        $c.envVarScope  | Should -Be 'User'
    }
    It 'treats unlisted providers as enabled by default' {
        $c = Import-DevDepotConfig
        Test-DevDepotProviderEnabled -Config $c -ProviderId 'anything' | Should -BeTrue
    }
    It 'honours explicit provider disable and exclude list' {
        $c = [pscustomobject]@{ root='D:\X'; linkStrategy='Both'; envVarScope='User'; logLevel='Info';
            createJunctions=$true; defaultProviderOn=$true; providers=@{ npm=$false }; exclude=@('yarn') }
        Test-DevDepotProviderEnabled -Config $c -ProviderId 'npm'  | Should -BeFalse
        Test-DevDepotProviderEnabled -Config $c -ProviderId 'yarn' | Should -BeFalse
        Test-DevDepotProviderEnabled -Config $c -ProviderId 'pip'  | Should -BeTrue
    }
    It 'flags invalid configuration' {
        $bad = [pscustomobject]@{ root=''; linkStrategy='Nope'; envVarScope='User' }
        (Test-DevDepotConfig -Config $bad).Count | Should -BeGreaterThan 0
    }
}

Describe 'Safety' {
    It 'rejects system locations as sources' {
        (Test-DevDepotSafeSource -Path $env:SystemRoot).IsSafe          | Should -BeFalse
        (Test-DevDepotSafeSource -Path (Join-Path $env:SystemRoot 'x')).IsSafe | Should -BeFalse
        (Test-DevDepotSafeSource -Path 'C:').IsSafe                     | Should -BeFalse
    }
    It 'accepts a normal profile path as source' {
        (Test-DevDepotSafeSource -Path (Join-Path $env:USERPROFILE '.gradle')).IsSafe | Should -BeTrue
    }
    It 'rejects a target nested in the source' {
        (Test-DevDepotSafeTarget -Target 'D:\a\b' -Source 'D:\a').IsSafe | Should -BeFalse
    }
}

Describe 'Provider descriptor validation' {
    It 'accepts a minimal valid descriptor' {
        $d = @{ Id='x'; Name='X'; Category='Test' }
        (Test-DevDepotProviderDescriptor -Descriptor $d).Count | Should -Be 0
    }
    It 'rejects a descriptor missing required keys' {
        (Test-DevDepotProviderDescriptor -Descriptor @{ Id='x' }).Count | Should -BeGreaterThan 0
    }
    It 'loads the bundled providers without error' {
        $log = New-DevDepotLogger -LogDirectory $env:TEMP -Quiet
        $providers = Import-DevDepotProviders -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'providers') -Logger $log
        $providers.Count | Should -BeGreaterThan 0
        ($providers | Where-Object Id -eq 'gradle') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Cleanup' {
    BeforeEach {
        $script:Base = Join-Path $env:TEMP ("dd-clean-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Base -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    }
    It 'selects only Chromium cache files and keeps profile data' {
        $ud = Join-Path $script:Base 'User Data'
        foreach ($d in 'Default\Cache\Cache_Data', 'Profile 1\Code Cache\js', 'GrShaderCache', 'Default\Network') {
            New-Item -ItemType Directory -Path (Join-Path $ud $d) -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $ud 'Default\Cache\Cache_Data\f1') -Value 'a'
        Set-Content -LiteralPath (Join-Path $ud 'Profile 1\Code Cache\js\f2') -Value 'b'
        Set-Content -LiteralPath (Join-Path $ud 'GrShaderCache\f3') -Value 'c'
        Set-Content -LiteralPath (Join-Path $ud 'Default\Network\Cookies') -Value 'keep'

        $files = Get-DevDepotChromiumCacheFiles -UserData $ud
        $files.Count | Should -Be 3
        Remove-DevDepotFileList -Files $files | Should -BeGreaterThan 0
        Test-Path (Join-Path $ud 'Default\Network\Cookies') | Should -BeTrue
        @(Get-DevDepotChromiumCacheFiles -UserData $ud).Count | Should -Be 0
    }
    It 'selects only temp files older than the cutoff' {
        $old = Join-Path $script:Base 'old.txt'; Set-Content -LiteralPath $old -Value 'x'
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-10)
        Set-Content -LiteralPath (Join-Path $script:Base 'new.txt') -Value 'y'
        (Get-DevDepotStaleTempFiles -Path $script:Base -MaxAgeDays 7).Name | Should -Be 'old.txt'
    }
    It 'skips admin tasks when not elevated and blocked tasks while their process runs' {
        $log = New-DevDepotLogger -LogDirectory $env:TEMP -Quiet
        $ctx = New-DevDepotContext -Config (Import-DevDepotConfig) -Logger $log
        $measure = { param($c, $t) [pscustomobject]@{ Bytes = [long]10; Note = '' } }
        $run     = { param($c, $t) throw 'must not run' }

        $ctx.Privilege = [pscustomobject]@{ IsElevated = $false }
        $admin = @{ Id = 'a'; Name = 'A'; RequiresAdmin = $true; BlockingProcesses = @(); Measure = $measure; Run = $run }
        (Invoke-DevDepotCleanupTask -Task $admin -Context $ctx).Status | Should -Be 'Skipped'

        $busy = @{ Id = 'b'; Name = 'B'; RequiresAdmin = $false; BlockingProcesses = @((Get-Process -Id $PID).ProcessName)
                   Measure = $measure; Run = $run }
        $r = Invoke-DevDepotCleanupTask -Task $busy -Context $ctx
        $r.Status | Should -Be 'Skipped'
        @($r.Details.Warnings).Count | Should -Be 1
    }
    It 'reports without deleting in simulation' {
        $log = New-DevDepotLogger -LogDirectory $env:TEMP -Quiet
        $ctx = New-DevDepotContext -Config (Import-DevDepotConfig) -Logger $log -Simulate
        $t = @{ Id = 's'; Name = 'S'; RequiresAdmin = $false; BlockingProcesses = @()
                Measure = { param($c, $t) [pscustomobject]@{ Bytes = [long]10; Note = '' } }; Run = { param($c, $t) throw 'must not run' } }
        $r = Invoke-DevDepotCleanupTask -Task $t -Context $ctx
        $r.Status                    | Should -Be 'Simulated'
        $r.Details.ReclaimableBytes  | Should -Be 10
    }
    It 'defines every built-in task with the required shape' {
        foreach ($t in Get-DevDepotCleanupTasks) {
            foreach ($k in 'Id', 'Name', 'RequiresAdmin', 'BlockingProcesses', 'Measure', 'Run') { $t.ContainsKey($k) | Should -BeTrue }
        }
    }
}

Describe 'State database round-trip' {
    It 'records a provider and reloads it from disk' {
        $base = Join-Path $env:TEMP ("dd-state-" + [guid]::NewGuid())
        try {
            $s = Import-DevDepotState -BasePath $base -Root 'E:\DevDepot'
            Set-DevDepotProviderState -State $s -ProviderId 'npm' -ProviderVersion '1.0.0' `
                -Operations @(@{ type='EnvVar'; name='npm_config_cache'; scope='User'; previousValue=$null; newValue='E:\x' })
            Save-DevDepotState -State $s | Out-Null
            $reloaded = Import-DevDepotState -BasePath $base
            (Get-DevDepotProviderState -State $reloaded -ProviderId 'npm') | Should -Not -BeNullOrEmpty
            @((Get-DevDepotProviderState -State $reloaded -ProviderId 'npm').operations).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
