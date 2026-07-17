# Bun - install directory and cache under ~/.bun (redirected with BUN_INSTALL).
@{
    Id          = 'bun'
    Name        = 'Bun'
    Category    = 'Node'
    Description = 'Bun install root and package cache (~/.bun).'
    Detect      = @{ Commands = @('bun'); Paths = @('%USERPROFILE%\.bun') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.bun'; TargetSubPath = 'node\bun'; EnvVar = 'BUN_INSTALL'; Strategy = 'Auto' }
    )
}
