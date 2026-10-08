Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\BootLens.Degradation.psm1') -Force

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

$bootStartUtc = [DateTimeOffset]'2026-07-25T14:59:29.7561980Z'
$boot = [pscustomobject]@{
    BootStartTimeUtc         = $bootStartUtc
    DiagnosticsEventRecordId = 1019
    BootDurationMs           = 42646
}

$mathworksItem = [pscustomobject]@{
    Name           = 'Mathworks Service Host'
    Source         = 'RegistryRun'
    Scope          = 'CurrentUser'
    ExecutablePath = 'C:\Users\SJQ\AppData\Local\MathWorks\ServiceHost\v2026.10.1.1\bin\win64\MathWorksServiceHost.exe'
}
$serviceItem = [pscustomobject]@{
    Name           = 'Example Service'
    Source         = 'WindowsService'
    Scope          = 'AllUsers'
    ExecutablePath = 'C:\Windows\System32\svchost.exe'
}

$mathworks = ConvertTo-BootLensDegradationRecord `
    -EventData ([ordered]@{
        StartTime       = '2026-07-25T14:59:29.7561980Z'
        Name            = 'MathworksServiceHost.exe'
        FriendlyName    = ''
        TotalTime       = '5106'
        DegradationTime = '5871'
        Path            = 'C:\Users\SJQ\AppData\Local\MathWorks\ServiceHost\v2026.9.0.2\bin\win64\MathworksServiceHost.exe'
    }) `
    -EventRecordId 1093 `
    -TimeCreatedUtc ([DateTimeOffset]'2026-07-25T15:01:28.9701515Z') `
    -BootRecords @($boot) `
    -StartupItems @($mathworksItem, $serviceItem)

Assert-Equal 'Matched' $mathworks.BootAssociationStatus 'Exact UTC start time should link to the full boot.'
Assert-Equal 1019 $mathworks.BootRecordId 'The matched boot diagnostics record ID should be preserved.'
Assert-Equal 'FamilyCandidate' $mathworks.TargetMatchLevel 'A versioned path mismatch with matching item name should be a family candidate.'
Assert-Equal 1 $mathworks.StartupItemMatchCount 'A unique family candidate should be retained.'
Assert-Equal 5106 $mathworks.TotalTimeMs 'Event total time should be preserved as reported.'
Assert-Equal 5871 $mathworks.DegradationTimeMs 'Degradation time may exceed total time and must be preserved.'
Assert-Equal 42646 $mathworks.BootDurationMs 'The matched boot total should remain a separate metric.'

$exactPathItem = [pscustomobject]@{
    Name           = 'Example App'
    Source         = 'RegistryRun'
    Scope          = 'CurrentUser'
    ExecutablePath = 'c:\apps\example.exe'
}
$exactPath = ConvertTo-BootLensDegradationRecord `
    -EventData ([ordered]@{
        StartTime = '2026-07-25T22:59:29.7561980+08:00'
        Name      = 'EXAMPLE.EXE'
        Path      = 'C:\Apps\Example.exe\'
    }) `
    -EventRecordId 1094 `
    -TimeCreatedUtc ([DateTimeOffset]'2026-07-25T15:01:29Z') `
    -BootRecords @($boot) `
    -StartupItems @($exactPathItem)
Assert-Equal 'ExactPath' $exactPath.TargetMatchLevel 'Windows path matching should ignore case and a trailing separator.'
Assert-Equal 'Matched' $exactPath.BootAssociationStatus 'Offset timestamps representing the same UTC instant should match.'

$svchost = ConvertTo-BootLensDegradationRecord `
    -EventData ([ordered]@{
        StartTime = '2026-07-25T14:59:29.7561980Z'
        Name      = 'svchost.exe'
        Path      = 'C:\Windows\System32\svchost.exe'
    }) `
    -EventRecordId 1095 `
    -TimeCreatedUtc ([DateTimeOffset]'2026-07-25T15:01:30Z') `
    -BootRecords @($boot) `
    -StartupItems @($serviceItem)
Assert-Equal 'GenericHost' $svchost.TargetMatchLevel 'svchost must not be attributed to a specific service by shared image path.'
Assert-Equal 0 $svchost.StartupItemMatchCount 'Generic host records must not expose a guessed service match.'

$unmatched = ConvertTo-BootLensDegradationRecord `
    -EventData ([ordered]@{
        StartTime = 'not-a-time'
        Name      = 'UnknownApp.exe'
        TotalTime = 'invalid'
    }) `
    -EventRecordId 1096 `
    -TimeCreatedUtc ([DateTimeOffset]'2026-07-25T15:01:31Z') `
    -BootRecords @($boot) `
    -StartupItems @()
Assert-Equal 'Unmatched' $unmatched.BootAssociationStatus 'Invalid start time should remain unmatched.'
Assert-Equal 'Unmatched' $unmatched.TargetMatchLevel 'No path or candidate should remain unmatched.'
Assert-Equal $null $unmatched.TotalTimeMs 'Invalid optional metric should remain unavailable.'

$ambiguousBoot = $boot.PSObject.Copy()
$ambiguousBoot.DiagnosticsEventRecordId = 1020
$ambiguous = ConvertTo-BootLensDegradationRecord `
    -EventData ([ordered]@{
        StartTime = '2026-07-25T14:59:29.7561980Z'
        Name      = 'UnknownApp.exe'
    }) `
    -EventRecordId 1097 `
    -TimeCreatedUtc ([DateTimeOffset]'2026-07-25T15:01:32Z') `
    -BootRecords @($boot, $ambiguousBoot) `
    -StartupItems @()
Assert-Equal 'Ambiguous' $ambiguous.BootAssociationStatus 'Duplicate exact boot anchors should be reported as ambiguous.'
Assert-Equal $null $ambiguous.BootRecordId 'An ambiguous boot must not arbitrarily select one boot record.'

$report = ConvertTo-BootLensDegradationReport -Records @($svchost, $mathworks, $exactPath, $unmatched) -Count 4
Assert-Equal 4 $report.EventCount 'The report should apply the requested visible event count.'
Assert-Equal 1 $report.MatchedBootCount 'Matched boot summary should count unique boot records.'
Assert-Equal 1 $report.ExactPathCount 'Exact path summary should count exact path matches.'
Assert-Equal 1 $report.FamilyCandidateCount 'Family summary should count candidate matches.'
Assert-Equal 1 $report.GenericHostCount 'Generic host summary should count host-only records.'
Assert-Equal 1 $report.UnmatchedBootCount 'Unmatched boot association should be counted.'

Write-Output 'BootLens degradation tests: PASS'
