# TabNine - AI completion engine: downloaded models and local indexes.
# Models are large and fully regenerable; relocated with a junction.
@{
    Id          = 'tabnine'
    Name        = 'TabNine'
    Category    = 'AI'
    Description = 'TabNine downloaded models and local completion indexes.'
    Version     = '1.0.0'
    Detect      = @{ Commands = @(); Paths = @('%APPDATA%\TabNine') }
    Mappings    = @(
        @{ Source = '%APPDATA%\TabNine'; TargetSubPath = 'ai\tabnine'; Strategy = 'Junction' }
    )
}
