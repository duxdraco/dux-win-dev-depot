# Google Chrome - the whole User Data folder (profiles, HTTP/code/GPU caches,
# service-worker storage). The DiskCacheDir policy would only move the HTTP
# cache and brands the browser as "managed", so the folder is relocated with a
# junction instead. Chrome keeps running in the background after its last
# window closes; migration is refused until no chrome.exe is left.
# Caches inside the moved folder are emptied by `DevDepot clean chrome-cache`.
@{
    Id          = 'chrome'
    Name        = 'Google Chrome'
    Category    = 'Browser'
    Description = 'Chrome User Data: profiles, HTTP/code/GPU caches and service-worker storage.'
    Version     = '1.0.0'
    Detect      = @{ Commands = @(); Paths = @('%LOCALAPPDATA%\Google\Chrome\User Data') }
    Metadata    = @{ BlockingProcesses = @('chrome') }
    Mappings    = @(
        @{ Source = '%LOCALAPPDATA%\Google\Chrome\User Data'; TargetSubPath = 'browser\chrome-user-data'; Strategy = 'Junction' }
    )
}
