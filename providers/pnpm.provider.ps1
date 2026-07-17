# pnpm - content-addressable store and state under %LOCALAPPDATA%\pnpm.
@{
    Id          = 'pnpm'
    Name        = 'pnpm'
    Category    = 'Node'
    Description = 'pnpm content-addressable store and global state.'
    Detect      = @{ Commands = @('pnpm'); Paths = @('%LOCALAPPDATA%\pnpm') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\pnpm'; TargetSubPath = 'node\pnpm'; Strategy = 'Junction' }
    )
}
