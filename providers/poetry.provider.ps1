# Poetry - dependency and artifact cache (redirected with POETRY_CACHE_DIR).
@{
    Id          = 'poetry'
    Name        = 'Poetry'
    Category    = 'Python'
    Description = 'Poetry cache (virtualenvs, artifacts, downloads).'
    Detect      = @{ Commands = @('poetry'); Paths = @('%LOCALAPPDATA%\pypoetry\Cache') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\pypoetry\Cache'; TargetSubPath = 'python\poetry-cache'; EnvVar = 'POETRY_CACHE_DIR'; Strategy = 'Auto' }
    )
}
