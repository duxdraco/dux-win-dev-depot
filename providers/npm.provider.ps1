# npm - package cache (redirected with npm_config_cache).
@{
    Id          = 'npm'
    Name        = 'npm'
    Category    = 'Node'
    Description = 'npm download cache.'
    Detect      = @{ Commands = @('npm', 'node'); Paths = @('%LOCALAPPDATA%\npm-cache') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\npm-cache'; TargetSubPath = 'node\npm-cache'; EnvVar = 'npm_config_cache'; Strategy = 'Auto' }
    )
}
