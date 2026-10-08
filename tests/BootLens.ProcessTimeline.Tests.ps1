Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\BootLens.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Expected,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Actual,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected: $Expected; Actual: $Actual"
    }
}

$bootStart = [DateTimeOffset]'2026-10-07T08:35:20.7602927Z'
$boot = [pscustomobject]@{
    BootStartTimeUtc = $bootStart
    BootKind         = 'Full'
}
$snapshot = [DateTimeOffset]'2026-10-07T08:36:00Z'
$processes = @(
    [pscustomobject]@{
        Name           = 'LaterProcess'
        ProcessId      = 200
        ParentProcessId = 100
        ExecutablePath = 'C:\Apps\later.exe'
        CreationDate   = [datetime]'2026-10-07T08:35:22.2602927Z'
    }
    [pscustomobject]@{
        Name           = 'BeforeAnchor'
        ProcessId      = 172
        ParentProcessId = 4
        ExecutablePath = $null
        CreationDate   = [datetime]'2026-10-07T08:35:20.5610450Z'
    }
    [pscustomobject]@{
        Name           = 'UnknownTime'
        ProcessId      = 300
        ParentProcessId = 4
        ExecutablePath = $null
        CreationDate   = $null
    }
)

$report = ConvertTo-BootLensProcessTimeline `
    -Processes $processes `
    -BootRecord $boot `
    -SnapshotTimeUtc $snapshot

Assert-Equal 1 $report.SchemaVersion 'Timeline schema should start at version 1.'
Assert-Equal 'CurrentRunningProcesses' $report.Scope 'Timeline scope should be explicit.'
Assert-Equal 3 $report.ProcessCount 'Timeline should preserve every snapshot process.'
Assert-Equal 2 $report.TimestampedCount 'Timestamped processes should be counted.'
Assert-Equal 1 $report.UnavailableCount 'Unavailable timestamps should be retained and counted.'
Assert-Equal 1 $report.NegativeOffsetCount 'Negative offsets should be counted, not clamped.'
Assert-Equal -199 $report.Processes[0].BootOffsetMs 'The negative offset should be rounded and preserved.'
Assert-Equal 'BeforeAnchor' $report.Processes[0].Name 'Negative-offset records should sort before later processes.'
Assert-Equal 1500 $report.Processes[1].BootOffsetMs 'Positive offsets should be measured in milliseconds.'
Assert-Equal 'UnknownTime' $report.Processes[2].Name 'Records without timestamps should sort after timestamped records.'
Assert-Equal $null $report.Processes[2].BootOffsetMs 'Unavailable time must not receive an estimated offset.'
Assert-Equal 'Win32Process|172|2026-10-07T08:35:20.5610450+00:00' `
    $report.Processes[0].SourceIdentity `
    'Process identity should include the process ID and creation timestamp.'

$invalidBoot = $boot.PSObject.Copy()
$invalidBoot.BootKind = 'FastStartup'
$threw = $false
try {
    ConvertTo-BootLensProcessTimeline -Processes $processes -BootRecord $invalidBoot -SnapshotTimeUtc $snapshot
}
catch {
    $threw = $true
}
Assert-Equal $true $threw 'A non-full boot must not produce a process timeline.'

Write-Output 'BootLens process timeline tests: PASS'
