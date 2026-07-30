# Postman - Electron app data: caches, indexed collections and logs.
# No cache environment variable; relocated with a junction. Close Postman first.
@{
    Id          = 'postman'
    Name        = 'Postman'
    Category    = 'Tools'
    Description = 'Postman application data and caches.'
    Version     = '1.0.0'
    Detect      = @{ Commands = @(); Paths = @('%LOCALAPPDATA%\Postman') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\Postman'; TargetSubPath = 'tools\postman'; Strategy = 'Junction' }
    )
}
