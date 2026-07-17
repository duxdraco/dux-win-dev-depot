# uv - fast Python package manager cache (redirected with UV_CACHE_DIR).
@{
    Id          = 'uv'
    Name        = 'uv'
    Category    = 'Python'
    Description = 'uv package/build cache.'
    Detect      = @{ Commands = @('uv'); Paths = @('%LOCALAPPDATA%\uv\cache') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\uv\cache'; TargetSubPath = 'python\uv-cache'; EnvVar = 'UV_CACHE_DIR'; Strategy = 'Auto' }
    )
}
