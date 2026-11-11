# Devin - VS Code-based AI IDE: extensions (~/.devin) and Electron app data,
# caches and CLI session database (Roaming). Neither has a relocation setting,
# so both are moved with junctions. Devin must be closed during migration.
@{
    Id          = 'devin'
    Name        = 'Devin'
    Category    = 'AI'
    Description = 'Devin IDE extensions, application data, caches and CLI sessions.'
    Version     = '1.0.0'
    Detect      = @{
        Commands = @('devin')
        Paths    = @('%USERPROFILE%\.devin', '%APPDATA%\Devin')
    }
    Metadata    = @{ BlockingProcesses = @('Devin') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.devin'; TargetSubPath = 'ai\devin-extensions'; Strategy = 'Junction' }
        @{ Source = '%APPDATA%\Devin';      TargetSubPath = 'ai\devin-data';       Strategy = 'Junction' }
    )
}
