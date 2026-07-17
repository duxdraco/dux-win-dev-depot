# Maven - local repository under ~/.m2. Maven has no cache env var, so the whole
# .m2 directory is relocated via a junction (settings.xml is preserved).
@{
    Id          = 'maven'
    Name        = 'Maven'
    Category    = 'Java'
    Description = 'Maven local repository and settings under ~/.m2.'
    Detect      = @{ Commands = @('mvn'); Paths = @('%USERPROFILE%\.m2') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.m2'; TargetSubPath = 'java\maven'; Strategy = 'Junction' }
    )
}
