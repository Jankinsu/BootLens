[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$Count = 30,

    [ValidateRange(1, 1000)]
    [int]$ScanEvents = 100,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.psm1') -Force

function Format-Duration {
    param(
        [Parameter(Mandatory)]
        [int]$Milliseconds
    )

    return '{0:F1} s' -f ($Milliseconds / 1000.0)
}

try {
    $report = Get-BootLensReport -Count $Count -ScanEvents $ScanEvents
}
catch {
    Write-Error $_.Exception.Message
    exit 2
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 5
    return
}

if ($null -eq $report.Summary) {
    Write-Error 'No confirmed full boot records were found.'
    exit 3
}

$summary = $report.Summary
$latest = $report.Records[0]
$status = if ($latest.IsWindowsDegradation -eq $true) {
    'Windows flagged degradation'
}
elseif ($latest.IsWindowsDegradation -eq $false) {
    'No Windows degradation flag'
}
else {
    'Unknown'
}

Write-Output 'BootLens'
Write-Output ''
Write-Output ('Last Boot   {0}' -f (Format-Duration $summary.LastBootDurationMs))
Write-Output ('Main Path   {0}' -f (Format-Duration $latest.MainPathBootDurationMs))
Write-Output ('Post Boot   {0}' -f (Format-Duration $latest.PostBootDurationMs))
Write-Output ('Average     {0}' -f (Format-Duration $summary.AverageBootDurationMs))
Write-Output ('Fastest     {0}' -f (Format-Duration $summary.FastestBootDurationMs))
Write-Output ('Slowest     {0}' -f (Format-Duration $summary.SlowestBootDurationMs))
if ($null -ne $report.Trend) {
    Write-Output ('Median      {0}' -f (Format-Duration $report.Trend.MedianBootDurationMs))
    if ($null -ne $report.Trend.ChangeFromPreviousBootMs) {
        $previousChange = [long]$report.Trend.ChangeFromPreviousBootMs
        $sign = if ($previousChange -gt 0) { '+' } else { '' }
        Write-Output ('Vs Previous {0}{1:F1} s (positive means longer)' -f $sign, ($previousChange / 1000.0))
    }
}
Write-Output ('Status      {0}' -f $status)
Write-Output ('Samples     {0} confirmed full boots' -f $summary.SampleCount)
if ($null -ne $report.Diagnostics) {
    $diagnostics = $report.Diagnostics
    Write-Output (
        'Windows flag {0} flagged, {1} not flagged, {2} unknown of {3} recent boots' -f
        $diagnostics.WindowsFlaggedBootCount,
        $diagnostics.WindowsNotFlaggedBootCount,
        $diagnostics.WindowsFlagUnknownBootCount,
        $diagnostics.SampleCount
    )
    Write-Output ('Flag source  Event 100 #{0}' -f $diagnostics.LatestDiagnosticsEventRecordId)
}
Write-Output ''
Write-Output 'Recent Boots'

$report.Records |
    Select-Object `
        @{ Name = 'Started'; Expression = { $_.BootStartTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } },
        @{ Name = 'Total'; Expression = { Format-Duration $_.BootDurationMs } },
        @{ Name = 'MainPath'; Expression = { Format-Duration $_.MainPathBootDurationMs } },
        @{ Name = 'PostBoot'; Expression = { Format-Duration $_.PostBootDurationMs } },
        @{ Name = 'Apps'; Expression = { $_.StartupAppCount } } |
    Format-Table -AutoSize

Write-Verbose (
    'Scanned {0} Diagnostics records; excluded {1} records that did not satisfy BootRecord v1.' -f
        $report.ScannedDiagnosticsCount,
        $report.ExcludedDiagnosticsCount
)
