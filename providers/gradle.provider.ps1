# Gradle - Java/Kotlin build tool user home (dependency cache, wrapper dists).
@{
    Id          = 'gradle'
    Name        = 'Gradle'
    Category    = 'Java'
    Description = 'Gradle user home: dependency caches and downloaded wrapper distributions.'
    Detect      = @{ Commands = @('gradle'); Paths = @('%USERPROFILE%\.gradle') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.gradle'; TargetSubPath = 'java\gradle'; EnvVar = 'GRADLE_USER_HOME'; Strategy = 'Auto' }
    )
}
