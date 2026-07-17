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
        verification      = 'Stats'    # None | Stats | Hash
        safetyLevel       = 'Safe'     # Safe | Conservative | Aggressive | Experimental
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
    if ($Config.PSObject.Properties.Name -contains 'verification' -and
        $Config.verification -notin @('None', 'Stats', 'Hash')) {
        $problems.Add("'verification' must be None, Stats or Hash.")
    }
    if ($Config.PSObject.Properties.Name -contains 'safetyLevel' -and
        $Config.safetyLevel -notin @('Safe', 'Conservative', 'Aggressive', 'Experimental')) {
        $problems.Add("'safetyLevel' must be Safe, Conservative, Aggressive or Experimental.")
    }
    # Leading comma keeps an empty result an array (not an unwrapped $null).
    return , $problems.ToArray()
}

function Import-DevDepotLayeredConfig {
    <#
    .SYNOPSIS
        Builds configuration from layered sources (lowest to highest precedence):
        built-in defaults -> machine config -> user config -> environment
        variables -> CLI overrides.
    .PARAMETER MachinePath
        Optional machine-wide config.json (e.g. under %ProgramData%).
    .PARAMETER UserPath
        Optional per-user config.json.
    .PARAMETER CliOverrides
        Hashtable of explicit CLI overrides (highest precedence).
    .OUTPUTS
        [pscustomobject] normalized configuration with a Sources list for auditing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $MachinePath,
        [string] $UserPath,
        [hashtable] $CliOverrides = @{}
    )

    $config  = Get-DevDepotDefaultConfig
    $sources = [System.Collections.Generic.List[string]]::new()
    $sources.Add('defaults')

    # File layers reuse the single-file merge semantics.
    foreach ($layer in @(
            @{ Name = 'machine'; Path = $MachinePath },
            @{ Name = 'user';    Path = $UserPath })) {
        if ($layer.Path -and (Test-Path -LiteralPath $layer.Path)) {
            $fileCfg = Import-DevDepotConfig -Path $layer.Path
            foreach ($p in $fileCfg.PSObject.Properties) { $config[$p.Name] = $p.Value }
            $sources.Add("$($layer.Name):$($layer.Path)")
        }
    }

    # Environment-variable layer.
    $envMap = @{
        DEVDEPOT_ROOT         = 'root'
        DEVDEPOT_LINKSTRATEGY = 'linkStrategy'
        DEVDEPOT_ENVVARSCOPE  = 'envVarScope'
        DEVDEPOT_LOGLEVEL     = 'logLevel'
        DEVDEPOT_VERIFICATION = 'verification'
        DEVDEPOT_SAFETYLEVEL  = 'safetyLevel'
    }
    $envUsed = $false
    foreach ($name in $envMap.Keys) {
        $val = [Environment]::GetEnvironmentVariable($name)
        if ($val) { $config[$envMap[$name]] = $val; $envUsed = $true }
    }
    if ($envUsed) { $sources.Add('environment') }

    # CLI overrides (highest precedence). Null/empty values are ignored.
    foreach ($k in $CliOverrides.Keys) {
        if ($null -ne $CliOverrides[$k] -and "$($CliOverrides[$k])" -ne '') {
            $config[$k] = $CliOverrides[$k]
        }
    }
    if ($CliOverrides.Count -gt 0) { $sources.Add('cli') }

    $config['configSources'] = $sources.ToArray()
    return [pscustomobject]$config
}

Export-ModuleMember -Function Get-DevDepotDefaultConfig, Import-DevDepotConfig, Import-DevDepotLayeredConfig,
    Test-DevDepotProviderEnabled, Test-DevDepotConfig
