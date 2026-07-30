# JDKs - JVM distributions downloaded by JetBrains IDEs / SDKMAN into ~/.jdks.
# Re-downloadable; relocated with a junction so IDEs keep resolving the path.
@{
    Id          = 'jdks'
    Name        = 'Downloaded JDKs'
    Category    = 'Java'
    Description = 'JDK distributions downloaded into ~/.jdks by IDEs and SDK managers.'
    Version     = '1.0.0'
    Detect      = @{ Commands = @(); Paths = @('%USERPROFILE%\.jdks') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.jdks'; TargetSubPath = 'java\jdks'; Strategy = 'Junction' }
    )
}
