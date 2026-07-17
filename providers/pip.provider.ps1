# pip - HTTP/wheel download cache (redirected with PIP_CACHE_DIR).
@{
    Id          = 'pip'
    Name        = 'pip'
    Category    = 'Python'
    Description = 'pip download and wheel build cache.'
    Detect      = @{ Commands = @('pip', 'pip3', 'python'); Paths = @('%LOCALAPPDATA%\pip\Cache') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\pip\Cache'; TargetSubPath = 'python\pip-cache'; EnvVar = 'PIP_CACHE_DIR'; Strategy = 'Auto' }
    )
}
