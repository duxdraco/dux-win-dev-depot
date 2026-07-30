# Docker Desktop - reports where the WSL2 backend keeps its data.
#
# DELIBERATELY REPORT-ONLY. Docker Desktop owns the location of its data-root:
# it is changed in Settings > Resources > Advanced ("Disk image location"), which
# stops the engine and relocates the docker-desktop-data distribution. Doing that
# behind the user's back inside `install` would kill running containers, so this
# provider only detects and reports.
@{
    Id          = 'docker'
    Name        = 'Docker Desktop'
    Category    = 'Platform'
    Description = 'Reports the Docker Desktop (WSL2 backend) data location (report-only).'
    Version     = '1.0.0'
    Detect      = @{
        Commands = @('docker')
        Paths    = @('%ProgramFiles%\Docker\Docker\Docker Desktop.exe', '%APPDATA%\Docker')
    }
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

            # Docker Desktop's WSL2 backend stores data in its own distributions.
            $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
            if (Test-Path $lxss) {
                foreach ($k in Get-ChildItem $lxss -ErrorAction SilentlyContinue) {
                    $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                    if ($p.DistributionName -notlike 'docker-desktop*') { continue }
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

            foreach ($i in $items) {
                $where = if ($i.OnSystemDrive) { 'SYSTEM DRIVE' } else { 'off system drive' }
                $ctx.Logger.Info(("[docker]  {0,-22} {1,10}  {2}  ({3})" -f `
                    $i.Distro, (Format-DevDepotSize $i.SizeBytes), $i.Source, $where))
            }
            if ($onSystemDrive -gt 0) {
                $ctx.Logger.Warn('[docker] Data-root dang o o he thong. Doi trong Docker Desktop > Settings > Resources > Advanced > Disk image location.')
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
                -Message 'Report-only: doi qua Docker Desktop > Settings > Resources > Advanced > Disk image location.' `
                -Details ([pscustomobject]@{ MovedBytes = [long]0; Committed = @(); RolledBack = $false; Skipped = @('docker:manual'); Warnings = @() })
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
