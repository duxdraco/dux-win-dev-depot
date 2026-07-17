# Deno - module/dependency cache (redirected with DENO_DIR).
@{
    Id          = 'deno'
    Name        = 'Deno'
    Category    = 'Node'
    Description = 'Deno dependency and compilation cache.'
    Detect      = @{ Commands = @('deno'); Paths = @('%LOCALAPPDATA%\deno') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\deno'; TargetSubPath = 'node\deno'; EnvVar = 'DENO_DIR'; Strategy = 'Auto' }
    )
}
