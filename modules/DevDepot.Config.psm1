#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Loads, merges and validates DevDepot configuration.
.DESCRIPTION
    Configuration precedence (lowest to highest): built-in defaults, then the
    config.json file. Unknown providers default to enabled unless explicitly set
    to false, so newly added providers work without editing config.
#>

function Get-DevDepotDefaultConfig {
    <#
    .SYNOPSIS
        Returns the built-in default configuration as a hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    @{
        root              = 'D:\DevDepot'
        linkStrategy      = 'Both'     # EnvVar | Junction | Both
        envVarScope       = 'User'     # User | Machine
        logLevel          = 'Info'
        createJunctions   = $true
        defaultProviderOn = $true
        providers         = @{}
        exclude           = @()
    }
}

function Import-DevDepotConfig {
    <#
    .SYNOPSIS
        Loads configuration from a JSON file merged over the defaults.
    .PARAMETER Path
        Path to config.json. When absent, defaults are returned unchanged.
    .OUTPUTS
        [pscustomobject] normalized configuration.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string] $Path)

    $config = Get-DevDepotDefaultConfig

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            if ($prop.Name -eq 'providers') {
                $map = @{}
                if ($prop.Value) {
                    foreach ($p in $prop.Value.PSObject.Properties) { $map[$p.Name] = [bool]$p.Value }
                }
                $config['providers'] = $map
            } elseif ($prop.Name -eq 'exclude') {
                $config['exclude'] = @($prop.Value)
            } else {
                $config[$prop.Name] = $prop.Value
            }
        }
    }

    return [pscustomobject]$config
}

function Test-DevDepotProviderEnabled {
    <#
    .SYNOPSIS
        Determines whether a provider is enabled given the configuration.
    .PARAMETER Config
        Configuration object from Import-DevDepotConfig.
    .PARAMETER ProviderId
        Provider id to test.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Config,
        [Parameter(Mandatory)][string] $ProviderId
    )
    if ($Config.exclude -contains $ProviderId) { return $false }
    $providers = $Config.providers
    if ($providers -is [hashtable] -and $providers.ContainsKey($ProviderId)) {
        return [bool]$providers[$ProviderId]
    }
    return [bool]$Config.defaultProviderOn
}

function Test-DevDepotConfig {
    <#
    .SYNOPSIS
        Validates a configuration object, returning a list of problems (empty = OK).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][pscustomobject] $Config)

    $problems = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($Config.root)) {
        $problems.Add("'root' must be a non-empty path.")
    }
    if ($Config.linkStrategy -notin @('EnvVar', 'Junction', 'Both')) {
        $problems.Add("'linkStrategy' must be EnvVar, Junction or Both.")
    }
    if ($Config.envVarScope -notin @('User', 'Machine')) {
        $problems.Add("'envVarScope' must be User or Machine.")
    }
    # Leading comma keeps an empty result an array (not an unwrapped $null).
    return , $problems.ToArray()
}

Export-ModuleMember -Function Get-DevDepotDefaultConfig, Import-DevDepotConfig, Test-DevDepotProviderEnabled, Test-DevDepotConfig
