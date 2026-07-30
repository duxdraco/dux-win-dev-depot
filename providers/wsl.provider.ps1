# WSL2 - reports where each distribution's ext4.vhdx lives.
#
# DELIBERATELY REPORT-ONLY. Relocating a distro requires `wsl --shutdown` (which
# stops every running container and Linux workload), moving a multi-GB VHDX and
# rewriting the Lxss registry key. That is far too disruptive to run inside a
# routine `install`, so this provider detects and reports instead of migrating.
#
# To relocate a distribution, use the documented manual procedure in
# docs/Troubleshooting.md (section "Moving a WSL distribution").
@{
    Id          = 'wsl'
    Name        = 'WSL2 distributions'
    Category    = 'Platform'
    Description = 'Reports the on-disk location of WSL2 distribution virtual disks (report-only).'
    Version     = '1.0.0'
    Detect      = @{ Commands = @('wsl'); Paths = @() }
    Metadata    = @{
        SupportsMigrate = $false
        Priority        = 900
    }
    Hooks       = @{
        Analyze = {
            param($provider, $ctx)
            $items = [System.Collections.Generic.List[object]]::new()
            $total = [long]0
            $onSystemDrive = 0
            $sysRoot = [System.IO.Path]::GetPathRoot($env:SystemDrive + '\')

            $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
            if (Test-Path $lxss) {
                foreach ($k in Get-ChildItem $lxss -ErrorAction SilentlyContinue) {
                    $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                    if (-not $p.DistributionName) { continue }
                    $base = ($p.BasePath -replace '^\\\\\?\\', '')
                    $vhd  = Join-Path $base 'ext4.vhdx'
                    $size = if (Test-Path -LiteralPath $vhd) { (Get-Item -LiteralPath $vhd).Length } else { [long]0 }
                    $onSys = $base.StartsWith($sysRoot, [StringComparison]::OrdinalIgnoreCase)
                    if ($onSys) { $onSystemDrive++; $total += $size }
                    $items.Add([pscustomobject]@{
                        Source        = $base
                        Target        = $base
                        Distro        = $p.DistributionName
                        SizeBytes     = $size
                        OnSystemDrive = $onSys
                    })
                }
            }

            $ctx.Logger.Info("[wsl] $($items.Count) distro; $onSystemDrive con tren o he thong.")
            foreach ($i in $items) {
                $where = if ($i.OnSystemDrive) { 'SYSTEM DRIVE' } else { 'off system drive' }
                $ctx.Logger.Info(("[wsl]   {0,-22} {1,10}  {2}  ({3})" -f `
                    $i.Distro, (Format-DevDepotSize $i.SizeBytes), $i.Source, $where))
            }

            New-DevDepotResult -Provider $provider.Id -Action 'Analyze' -Status 'Success' `
                -Message ("{0} distro, {1} tren o he thong" -f $items.Count, $onSystemDrive) `
                -Details ([pscustomobject]@{
                    Detected       = ($items.Count -gt 0)
                    Classification = if ($onSystemDrive -gt 0) { 'ReadyToMigrate' } elseif ($items.Count) { 'AlreadyOptimized' } else { 'NotInstalled' }
                    Items          = $items.ToArray()
                    TotalBytes     = $total
                    Reclaimable    = $total
                })
        }
        Migrate = {
            param($provider, $ctx)
            New-DevDepotResult -Provider $provider.Id -Action 'Migrate' -Status 'Skipped' `
                -Message 'Report-only: di chuyen WSL can `wsl --shutdown` va sua registry. Xem docs/Troubleshooting.md.' `
                -Details ([pscustomobject]@{ MovedBytes = [long]0; Committed = @(); RolledBack = $false; Skipped = @('wsl:manual'); Warnings = @() })
        }
        Validate = {
            param($provider, $ctx)
            New-DevDepotResult -Provider $provider.Id -Action 'Validate' -Status 'Success' `
                -Message 'Report-only provider.' -Details ([pscustomobject]@{ Issues = @() })
        }
        Repair = {
            param($provider, $ctx)
            New-DevDepotResult -Provider $provider.Id -Action 'Repair' -Status 'Skipped' `
                -Message 'Report-only provider.' -Details ([pscustomobject]@{ Fixed = @() })
        }
    }
}
