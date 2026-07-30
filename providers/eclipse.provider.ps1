# Eclipse / p2 - the shared bundle pool and p2 metadata repository under ~/.p2.
# Regenerable from the update sites; relocated with a junction.
@{
    Id          = 'eclipse'
    Name        = 'Eclipse (p2)'
    Category    = 'Java'
    Description = 'Eclipse p2 bundle pool and metadata repository (~/.p2).'
    Version     = '1.0.0'
    Detect      = @{ Commands = @('eclipse'); Paths = @('%USERPROFILE%\.p2') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.p2'; TargetSubPath = 'java\eclipse-p2'; Strategy = 'Junction' }
    )
}
