#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Generates JSON, Markdown and HTML reports from a report data object.
.DESCRIPTION
    The report data object is a plain PSCustomObject/hashtable so it is trivially
    serialisable. HTML output is fully self-contained (inline CSS, no external
    assets) so it can be opened or emailed anywhere.
#>

function ConvertTo-DevDepotHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object] $Report)

    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

    $rows = foreach ($p in @($Report.Providers)) {
        $badge = if ($p.Detected) { '<span class="ok">detected</span>' } else { '<span class="muted">absent</span>' }
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td class="num">{3}</td><td>{4}</td></tr>' -f `
            (& $enc $p.Name), (& $enc $p.Category), $badge, (& $enc $p.SizeHuman), (& $enc ($p.Status))
    }

    $warnRows = foreach ($w in @($Report.Warnings)) { '<li>{0}</li>' -f (& $enc $w) }
    $errRows  = foreach ($e in @($Report.Errors))   { '<li>{0}</li>' -f (& $enc $e) }
    $recRows  = foreach ($r in @($Report.Recommendations)) { '<li>{0}</li>' -f (& $enc $r) }

    @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DevDepot Report - $(& $enc $Report.Command)</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: Segoe UI, system-ui, sans-serif; margin: 2rem; line-height: 1.5; }
  h1 { margin-bottom: 0; }
  .sub { color: #888; margin-top: .25rem; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  th, td { border-bottom: 1px solid #8884; padding: .5rem .75rem; text-align: left; }
  th { text-transform: uppercase; font-size: .75rem; letter-spacing: .05em; }
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
  .ok { color: #1a7f37; font-weight: 600; }
  .muted { color: #888; }
  .cards { display: flex; gap: 1rem; flex-wrap: wrap; }
  .card { border: 1px solid #8884; border-radius: 8px; padding: 1rem 1.25rem; min-width: 12rem; }
  .card .big { font-size: 1.6rem; font-weight: 700; }
  ul { margin: .25rem 0; }
</style></head><body>
<h1>DevDepot Report</h1>
<div class="sub">$(& $enc $Report.Command) &middot; run $(& $enc $Report.RunId) &middot; $(& $enc $Report.GeneratedAt)</div>
<div class="cards">
  <div class="card"><div>Root</div><div class="big">$(& $enc $Report.Root)</div></div>
  <div class="card"><div>Providers detected</div><div class="big">$($Report.Totals.DetectedCount)</div></div>
  <div class="card"><div>Reclaimable</div><div class="big">$(& $enc $Report.Totals.ReclaimableHuman)</div></div>
  <div class="card"><div>Moved</div><div class="big">$(& $enc $Report.Totals.MovedHuman)</div></div>
</div>
<h2>Providers</h2>
<table><thead><tr><th>Provider</th><th>Category</th><th>State</th><th class="num">Size</th><th>Status</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody></table>
<h2>Warnings ($(@($Report.Warnings).Count))</h2><ul>$($warnRows -join "`n")</ul>
<h2>Errors ($(@($Report.Errors).Count))</h2><ul>$($errRows -join "`n")</ul>
<h2>Recommendations</h2><ul>$($recRows -join "`n")</ul>
</body></html>
"@
}

function ConvertTo-DevDepotMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object] $Report)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# DevDepot Report - $($Report.Command)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- **Run:** $($Report.RunId)")
    [void]$sb.AppendLine("- **Generated:** $($Report.GeneratedAt)")
    [void]$sb.AppendLine("- **Root:** ``$($Report.Root)``")
    [void]$sb.AppendLine("- **Providers detected:** $($Report.Totals.DetectedCount)")
    [void]$sb.AppendLine("- **Reclaimable:** $($Report.Totals.ReclaimableHuman)")
    [void]$sb.AppendLine("- **Moved:** $($Report.Totals.MovedHuman)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Providers')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Provider | Category | State | Size | Status |')
    [void]$sb.AppendLine('|----------|----------|-------|------|--------|')
    foreach ($p in @($Report.Providers)) {
        $state = if ($p.Detected) { 'detected' } else { 'absent' }
        [void]$sb.AppendLine("| $($p.Name) | $($p.Category) | $state | $($p.SizeHuman) | $($p.Status) |")
    }
    [void]$sb.AppendLine()
    foreach ($section in @(
            @{ Title = 'Warnings'; Items = $Report.Warnings },
            @{ Title = 'Errors'; Items = $Report.Errors },
            @{ Title = 'Recommendations'; Items = $Report.Recommendations })) {
        [void]$sb.AppendLine("## $($section.Title)")
        [void]$sb.AppendLine()
        $items = @($section.Items)
        if ($items.Count -eq 0) { [void]$sb.AppendLine('_None._') }
        foreach ($i in $items) { [void]$sb.AppendLine("- $i") }
        [void]$sb.AppendLine()
    }
    return $sb.ToString()
}

function Export-DevDepotReport {
    <#
    .SYNOPSIS
        Writes JSON, Markdown and HTML report files.
    .PARAMETER Report
        Report data object.
    .PARAMETER Directory
        Output directory (created if missing).
    .PARAMETER Formats
        Subset of Json, Markdown, Html. Defaults to all three.
    .OUTPUTS
        [pscustomobject] with the paths written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object] $Report,
        [Parameter(Mandatory)][string] $Directory,
        [ValidateSet('Json', 'Markdown', 'Html')][string[]] $Formats = @('Json', 'Markdown', 'Html')
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $base   = Join-Path $Directory ("report-{0}-{1}" -f $Report.Command, $Report.RunId)
    $paths  = [ordered]@{}

    if ('Json' -in $Formats -and $PSCmdlet.ShouldProcess("$base.json", 'Write JSON report')) {
        $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$base.json" -Encoding utf8
        $paths['Json'] = "$base.json"
    }
    if ('Markdown' -in $Formats -and $PSCmdlet.ShouldProcess("$base.md", 'Write Markdown report')) {
        ConvertTo-DevDepotMarkdown -Report $Report | Set-Content -LiteralPath "$base.md" -Encoding utf8
        $paths['Markdown'] = "$base.md"
    }
    if ('Html' -in $Formats -and $PSCmdlet.ShouldProcess("$base.html", 'Write HTML report')) {
        ConvertTo-DevDepotHtml -Report $Report | Set-Content -LiteralPath "$base.html" -Encoding utf8
        $paths['Html'] = "$base.html"
    }

    return [pscustomobject]$paths
}

Export-ModuleMember -Function Export-DevDepotReport, ConvertTo-DevDepotHtml, ConvertTo-DevDepotMarkdown
