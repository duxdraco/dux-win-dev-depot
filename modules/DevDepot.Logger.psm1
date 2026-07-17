#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Structured, level-based logging for DevDepot.
.DESCRIPTION
    Provides a logger instance (PSCustomObject) that writes to both the console
    (with colour) and a timestamped log file. The logger is passed explicitly to
    consumers (dependency injection) rather than kept as global mutable state.
#>

# Ordered severity map. Messages below the configured threshold are suppressed.
$script:LogLevels = [ordered]@{
    Trace = 0
    Debug = 1
    Info  = 2
    Warn  = 3
    Error = 4
    None  = 5
}

$script:LevelColour = @{
    Trace = 'DarkGray'
    Debug = 'Gray'
    Info  = 'White'
    Warn  = 'Yellow'
    Error = 'Red'
}

function New-DevDepotLogger {
    <#
    .SYNOPSIS
        Creates a new logger instance.
    .PARAMETER LogDirectory
        Directory where log files are written. Created if it does not exist.
    .PARAMETER MinimumLevel
        Lowest severity that will be emitted (Trace, Debug, Info, Warn, Error, None).
    .PARAMETER Quiet
        When set, suppresses console output but still writes to file.
    .PARAMETER Name
        Logical name used in the log file name.
    .OUTPUTS
        [pscustomobject] logger instance with Trace/Debug/Info/Warn/Error methods.
    .EXAMPLE
        $log = New-DevDepotLogger -LogDirectory .\logs -MinimumLevel Debug
        $log.Info('Starting migration')
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $LogDirectory,
        [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'None')]
        [string] $MinimumLevel = 'Info',
        [switch] $Quiet,
        [string] $Name = 'devdepot'
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logFile = Join-Path $LogDirectory ('{0}-{1}.log' -f $Name, $stamp)

    $logger = [pscustomobject]@{
        PSTypeName   = 'DevDepot.Logger'
        LogFile      = $logFile
        MinimumLevel = $MinimumLevel
        Quiet        = [bool]$Quiet
        ErrorCount   = 0
        WarnCount    = 0
        Levels       = $script:LogLevels
        Colours      = $script:LevelColour
    }

    # Core write routine. Invoked as a method so $this binds to the logger.
    $logger | Add-Member -MemberType ScriptMethod -Name Write -Value {
        param([string] $Level, [string] $Message)
        if ($this.Levels[$Level] -lt $this.Levels[$this.MinimumLevel]) { return }

        if ($Level -eq 'Error') { $this.ErrorCount++ }
        if ($Level -eq 'Warn')  { $this.WarnCount++ }

        $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $line = '{0} [{1,-5}] {2}' -f $ts, $Level.ToUpperInvariant(), $Message

        # File output is best-effort; never let a logging failure abort a migration.
        try { Add-Content -LiteralPath $this.LogFile -Value $line -Encoding utf8 } catch { }

        if (-not $this.Quiet) {
            Write-Host $line -ForegroundColor $this.Colours[$Level]
        }
    }

    $logger | Add-Member -MemberType ScriptMethod -Name Trace -Value { param($m) $this.Write('Trace', $m) }
    $logger | Add-Member -MemberType ScriptMethod -Name Debug -Value { param($m) $this.Write('Debug', $m) }
    $logger | Add-Member -MemberType ScriptMethod -Name Info  -Value { param($m) $this.Write('Info',  $m) }
    $logger | Add-Member -MemberType ScriptMethod -Name Warn  -Value { param($m) $this.Write('Warn',  $m) }
    $logger | Add-Member -MemberType ScriptMethod -Name Error -Value { param($m) $this.Write('Error', $m) }

    return $logger
}

Export-ModuleMember -Function New-DevDepotLogger
