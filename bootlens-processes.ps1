[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Count = 50,

    [ValidateRange(1, 1000)]
    [int]$ScanEvents = 100,

    [ValidateRange(1, 120)]
    [int]$OperationTimeoutSec = 15,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.psm1') -Force

try {
    $report = Get-BootLensProcessTimeline `
        -ScanEvents $ScanEvents `
        -OperationTimeoutSec $OperationTimeoutSec
}
catch {
    Write-Error $_.Exception.Message
    exit 2
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 6
    return
}

$shownProcesses = @($report.Processes | Select-Object -First $Count)
Write-Output 'BootLens Process Timeline'
Write-Output ''
Write-Output ('Boot start  {0}' -f $report.BootStartTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff'))
Write-Output ('Boot kind   {0}' -f $report.BootKind)
Write-Output ('Snapshot    {0}' -f $report.SnapshotTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff'))
Write-Output ('Processes   {0} total; {1} timestamped; {2} unavailable; {3} before boot anchor' -f `
    $report.ProcessCount,
    $report.TimestampedCount,
    $report.UnavailableCount,
    $report.NegativeOffsetCount
)
Write-Output ('Showing     {0} earliest process records' -f $shownProcesses.Count)
Write-Output ''

$shownProcesses |
    Select-Object `
        Name,
        ProcessId,
        @{ Name = 'Started'; Expression = {
            if ($null -eq $_.CreationTimeUtc) { 'Unknown' }
            else { $_.CreationTimeUtc.ToLocalTime().ToString('HH:mm:ss.fff') }
        } },
        @{ Name = 'Boot Offset'; Expression = {
            if ($null -eq $_.BootOffsetMs) { 'Unknown' }
            else { '{0:+0.000;-0.000;0.000} s' -f ($_.BootOffsetMs / 1000.0) }
        } },
        ExecutablePath |
    Format-Table -AutoSize -Wrap

Write-Output ''
Write-Output 'Scope: current running-process snapshot only; exited processes are not included.'
Write-Output 'Boot Offset is relative to BootStartTimeUtc and may be negative.'
