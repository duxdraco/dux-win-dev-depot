# JetBrains IDEs - per-user configuration/plugins (Roaming) and caches/indexes
# (Local). No official cache environment variable, so both are relocated with
# junctions. IDEs must be closed during migration.
@{
    Id          = 'jetbrains'
    Name        = 'JetBrains IDEs'
    Category    = 'IDE'
    Description = 'JetBrains per-user config, plugins, caches, indexes and logs (IntelliJ, PhpStorm, WebStorm, PyCharm, Rider, ...).'
    Version     = '1.0.0'
    Detect      = @{
        Commands = @()
        Paths    = @('%APPDATA%\JetBrains', '%LOCALAPPDATA%\JetBrains')
    }
    Mappings    = @(
        @{ Source = '%APPDATA%\JetBrains';      TargetSubPath = 'ide\jetbrains-config'; Strategy = 'Junction' }
        @{ Source = '%LOCALAPPDATA%\JetBrains'; TargetSubPath = 'ide\jetbrains-cache';  Strategy = 'Junction' }
    )
}
