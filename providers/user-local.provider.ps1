# User-local (XDG) - ~/.local holds user-installed CLI tools and shared data,
# typically from `pip install --user`, pipx and similar installers.
#
# NOTE: this contains installed programs rather than a pure cache. It is
# relocated (never deleted) with a junction so every existing path keeps working.
@{
    Id          = 'user-local'
    Name        = 'User-local tools (~/.local)'
    Category    = 'Shared'
    Description = 'User-installed CLI tools and shared data under ~/.local (pip --user, pipx, ...).'
    Version     = '1.0.0'
    Detect      = @{ Commands = @(); Paths = @('%USERPROFILE%\.local') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.local'; TargetSubPath = 'shared\user-local'; Strategy = 'Junction' }
    )
}
