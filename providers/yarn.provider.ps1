# Yarn - global cache (redirected with YARN_CACHE_FOLDER) and Yarn data dir.
@{
    Id          = 'yarn'
    Name        = 'Yarn'
    Category    = 'Node'
    Description = 'Yarn global cache and data directory.'
    Detect      = @{ Commands = @('yarn'); Paths = @('%LOCALAPPDATA%\Yarn') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\Yarn\Cache'; TargetSubPath = 'node\yarn-cache'; EnvVar = 'YARN_CACHE_FOLDER'; Strategy = 'Auto' }
    )
}
