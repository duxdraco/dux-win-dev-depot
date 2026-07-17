# sbt / Coursier - Scala build tool caches (~/.sbt, ~/.ivy2) plus the Coursier
# artifact cache (redirected with COURSIER_CACHE).
@{
    Id          = 'sbt'
    Name        = 'sbt / Coursier'
    Category    = 'Java'
    Description = 'Scala sbt caches (~/.sbt, ~/.ivy2) and the Coursier artifact cache.'
    Detect      = @{ Commands = @('sbt', 'scala', 'cs'); Paths = @('%USERPROFILE%\.sbt', '%USERPROFILE%\.ivy2') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.sbt';             TargetSubPath = 'java\sbt';       Strategy = 'Junction' }
        @{ Source = '%USERPROFILE%\.ivy2';            TargetSubPath = 'java\ivy2';      Strategy = 'Junction' }
        @{ Source = '%LOCALAPPDATA%\Coursier\cache';  TargetSubPath = 'java\coursier';  EnvVar = 'COURSIER_CACHE'; Strategy = 'Auto' }
    )
}
