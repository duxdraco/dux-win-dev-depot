# Conda - package cache and per-user config under ~/.conda.
@{
    Id          = 'conda'
    Name        = 'Conda'
    Category    = 'Python'
    Description = 'Conda per-user directory (~/.conda): environments list and package cache.'
    Detect      = @{ Commands = @('conda', 'mamba'); Paths = @('%USERPROFILE%\.conda') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.conda'; TargetSubPath = 'python\conda'; Strategy = 'Junction' }
    )
}
