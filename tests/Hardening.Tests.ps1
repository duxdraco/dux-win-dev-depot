#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Phase 2.5 hardening tests: metadata, capability gating, ordering, safety,
    verification and layered configuration (Pester 5).
#>
Set-StrictMode -Version Latest

BeforeAll {
    $script:ModulesDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'modules'
    Import-Module (Join-Path $script:ModulesDir 'DevDepot.psm1') -Force -DisableNameChecking
    function Fake ($id, $deps = @(), $conflicts = @(), $priority = 100, $minPS = '7.0') {
        @{ Id = $id; Name = $id; Category = 'T'
           Metadata = @{ Dependencies = $deps; Conflicts = $conflicts; Priority = $priority; MinimumPowerShell = $minPS } }
    }
    function Ctx ($psVer = '7.4', $winVer = '10.0.22000', $elevated = $true) {
        [pscustomobject]@{
            Config = (Import-DevDepotConfig); Logger = (New-DevDepotLogger -LogDirectory $env:TEMP -Quiet)
            PowerShellVersion = $psVer; WindowsVersion = $winVer
            Privilege = [pscustomobject]@{ IsElevated = $elevated }; Simulate = $true
        }
    }
}

Describe 'Provider metadata' {
    It 'applies defaults to a bare descriptor' {
        $m = Get-DevDepotProviderMetadata -Provider @{ Id = 'x'; Name = 'X'; Category = 'T' }
        $m.Priority          | Should -Be 100
        $m.MinimumPowerShell | Should -Be '7.0'
        $m.SupportsRollback  | Should -BeTrue
        $m.Version           | Should -Be '0.0.0'
    }
}

Describe 'Capability gating' {
    It 'passes when environment meets requirements' {
        (Test-DevDepotProviderCapable -Provider (Fake 'a' -minPS '7.0') -Context (Ctx)).Capable | Should -BeTrue
    }
    It 'fails when PowerShell is too old' {
        $r = Test-DevDepotProviderCapable -Provider (Fake 'a' -minPS '9.9') -Context (Ctx -psVer '7.4')
        $r.Capable | Should -BeFalse
        $r.Reasons.Count | Should -BeGreaterThan 0
    }
    It 'fails when admin required but not elevated' {
        $p = @{ Id = 'a'; Name = 'A'; Category = 'T'; Metadata = @{ RequiresAdmin = $true } }
        (Test-DevDepotProviderCapable -Provider $p -Context (Ctx -elevated $false)).Capable | Should -BeFalse
    }
}

Describe 'Dependency / conflict ordering' {
    It 'orders dependencies before dependents' {
        $res = Resolve-DevDepotProviderOrder -Providers @((Fake 'b' -deps @('a')), (Fake 'a'))
        $ids = @($res.Ordered | ForEach-Object { $_.Id })
        ($ids.IndexOf('a')) | Should -BeLessThan ($ids.IndexOf('b'))
    }
    It 'respects priority within a level' {
        $res = Resolve-DevDepotProviderOrder -Providers @((Fake 'hi' -priority 200), (Fake 'lo' -priority 1))
        @($res.Ordered)[0].Id | Should -Be 'lo'
    }
    It 'detects conflicts' {
        $res = Resolve-DevDepotProviderOrder -Providers @((Fake 'a' -conflicts @('b')), (Fake 'b'))
        $res.Conflicts.Count | Should -BeGreaterThan 0
    }
    It 'detects missing dependencies' {
        $res = Resolve-DevDepotProviderOrder -Providers @((Fake 'a' -deps @('ghost')))
        $res.MissingDependencies.Count | Should -BeGreaterThan 0
    }
    It 'detects cycles' {
        $res = Resolve-DevDepotProviderOrder -Providers @((Fake 'a' -deps @('b')), (Fake 'b' -deps @('a')))
        $res.Cycles.Count | Should -BeGreaterThan 0
    }
}

Describe 'Safety levels' {
    It 'permits operations at or below the ceiling' {
        Test-DevDepotSafetyAllowed -OperationLevel 'Safe'       -Ceiling 'Conservative' | Should -BeTrue
        Test-DevDepotSafetyAllowed -OperationLevel 'Aggressive' -Ceiling 'Safe'         | Should -BeFalse
    }
}

Describe 'Verification' {
    It 'reports byte/count mismatches' {
        $a = [pscustomobject]@{ FileCount = 2; DirCount = 1; TotalBytes = 100 }
        $b = [pscustomobject]@{ FileCount = 2; DirCount = 1; TotalBytes = 90 }
        (Compare-DevDepotStats -Expected $a -Actual $b).Ok | Should -BeFalse
        (Compare-DevDepotStats -Expected $a -Actual $a).Ok | Should -BeTrue
    }
}

Describe 'Layered configuration' {
    It 'applies environment then CLI overrides in order' {
        $env:DEVDEPOT_SAFETYLEVEL = 'Aggressive'
        try {
            $c1 = Import-DevDepotLayeredConfig
            $c1.safetyLevel | Should -Be 'Aggressive'
            $c2 = Import-DevDepotLayeredConfig -CliOverrides @{ safetyLevel = 'Experimental' }
            $c2.safetyLevel | Should -Be 'Experimental'   # CLI beats env
        } finally {
            $env:DEVDEPOT_SAFETYLEVEL = $null
        }
    }
}
