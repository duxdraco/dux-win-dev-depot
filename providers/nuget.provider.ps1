# NuGet - global packages folder (redirected with NUGET_PACKAGES).
@{
    Id          = 'nuget'
    Name        = 'NuGet'
    Category    = 'DotNet'
    Description = 'NuGet global packages folder (~/.nuget/packages).'
    Detect      = @{ Commands = @('dotnet', 'nuget'); Paths = @('%USERPROFILE%\.nuget\packages') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.nuget\packages'; TargetSubPath = 'dotnet\nuget-packages'; EnvVar = 'NUGET_PACKAGES'; Strategy = 'Auto' }
    )
}
