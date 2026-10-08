Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DiagnosticsLogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
$script:CorrelationToleranceMs = 1000

function Get-EventDataMap {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )

    [xml]$eventXml = $EventRecord.ToXml()
    $eventData = [ordered]@{}
    $dataNodes = $eventXml.SelectNodes(
        "/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data']"
    )

    foreach ($node in $dataNodes) {
        $name = $node.GetAttribute('Name')

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $eventData[$name] = $node.InnerText
        }
    }

    return $eventData
}

function Get-RequiredInt {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Data,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Data.Contains($Name)) {
        throw "Required Event ID 100 field is missing: $Name"
    }

    $value = 0

    if (-not [int]::TryParse(
            [string]$Data[$Name],
            [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value
        )) {
        throw "Event ID 100 field is not a valid integer: $Name"
    }

    return $value
}

function Get-OptionalInt {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Data,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Data.Contains($Name)) {
        return $null
    }

    $value = 0

    if ([int]::TryParse(
            [string]$Data[$Name],
            [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value
        )) {
        return $value
    }

    return $null
}

function Get-OptionalBoolean {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Data,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Data.Contains($Name)) {
        return $null
    }

    $value = $false

    if ([bool]::TryParse([string]$Data[$Name], [ref]$value)) {
        return $value
    }

    return $null
}

function ConvertTo-UtcDateTimeOffset {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor
        [Globalization.DateTimeStyles]::AdjustToUniversal

    if (-not [DateTimeOffset]::TryParse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            $styles,
            [ref]$parsed
        )) {
        throw "Field is not a valid UTC timestamp: $FieldName"
    }

    return $parsed.ToUniversalTime()
}

function ConvertTo-BootTypeCode {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToInt32($Value.Substring(2), 16)
    }

    return [Convert]::ToInt32($Value, [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-DiagnosticsEvent {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )

    $data = Get-EventDataMap -EventRecord $EventRecord

    if (-not $data.Contains('BootStartTime')) {
        throw 'Required Event ID 100 field is missing: BootStartTime'
    }

    [pscustomobject]@{
        BootStartTimeUtc          = ConvertTo-UtcDateTimeOffset `
            -Value ([string]$data['BootStartTime']) `
            -FieldName 'BootStartTime'
        BootDurationMs           = Get-RequiredInt -Data $data -Name 'BootTime'
        MainPathBootDurationMs   = Get-RequiredInt -Data $data -Name 'MainPathBootTime'
        PostBootDurationMs       = Get-RequiredInt -Data $data -Name 'BootPostBootTime'
        StartupAppCount          = Get-OptionalInt -Data $data -Name 'BootNumStartupApps'
        IsWindowsDegradation     = Get-OptionalBoolean -Data $data -Name 'BootIsDegradation'
        IsRebootAfterInstall     = Get-OptionalBoolean -Data $data -Name 'BootIsRebootAfterInstall'
        DiagnosticsEventRecordId = [long]$EventRecord.RecordId
        DiagnosticsEventVersion = [int]$EventRecord.Version
    }
}

function ConvertFrom-KernelBootEvent {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )

    $data = Get-EventDataMap -EventRecord $EventRecord

    if (-not $data.Contains('BootType')) {
        throw 'Required Event ID 27 field is missing: BootType'
    }

    [pscustomobject]@{
        TimeCreatedUtc = [DateTimeOffset]$EventRecord.TimeCreated.ToUniversalTime()
        RecordId       = [long]$EventRecord.RecordId
        BootTypeCode   = ConvertTo-BootTypeCode -Value ([string]$data['BootType'])
    }
}

function ConvertFrom-KernelGeneralEvent {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )

    [pscustomobject]@{
        TimeCreatedUtc = [DateTimeOffset]$EventRecord.TimeCreated.ToUniversalTime()
        RecordId       = [long]$EventRecord.RecordId
    }
}

function ConvertTo-BootRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$DiagnosticsEvents,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$KernelBootEvents,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$KernelGeneralEvents,

        [ValidateRange(1, 10000)]
        [int]$CorrelationToleranceMs = $script:CorrelationToleranceMs
    )

    foreach ($diagnostic in $DiagnosticsEvents) {
        $bootStart = [DateTimeOffset]$diagnostic.BootStartTimeUtc
        $kernelBootMatches = @(
            $KernelBootEvents | Where-Object {
                [Math]::Abs((([DateTimeOffset]$_.TimeCreatedUtc) - $bootStart).TotalMilliseconds) -le
                    $CorrelationToleranceMs
            }
        )
        $kernelGeneralMatches = @(
            $KernelGeneralEvents | Where-Object {
                [Math]::Abs((([DateTimeOffset]$_.TimeCreatedUtc) - $bootStart).TotalMilliseconds) -le
                    $CorrelationToleranceMs
            }
        )

        if ($kernelBootMatches.Count -ne 1 -or $kernelGeneralMatches.Count -ne 1) {
            continue
        }

        $kernelBoot = $kernelBootMatches[0]
        $kernelGeneral = $kernelGeneralMatches[0]

        if ([int]$kernelBoot.BootTypeCode -ne 0) {
            continue
        }

        $bootDurationMs = [int]$diagnostic.BootDurationMs
        $mainPathDurationMs = [int]$diagnostic.MainPathBootDurationMs
        $postBootDurationMs = [int]$diagnostic.PostBootDurationMs

        if ($bootDurationMs -lt 0 -or $mainPathDurationMs -lt 0 -or $postBootDurationMs -lt 0) {
            continue
        }

        if ($bootDurationMs -ne ($mainPathDurationMs + $postBootDurationMs)) {
            continue
        }

        [pscustomobject][ordered]@{
            SchemaVersion              = 1
            BootStartTimeUtc           = $bootStart.ToUniversalTime()
            BootKind                   = 'Full'
            KernelBootTypeCode         = 0
            BootDurationMs             = $bootDurationMs
            MainPathBootDurationMs     = $mainPathDurationMs
            PostBootDurationMs         = $postBootDurationMs
            StartupAppCount            = $diagnostic.StartupAppCount
            IsWindowsDegradation       = $diagnostic.IsWindowsDegradation
            IsRebootAfterInstall       = $diagnostic.IsRebootAfterInstall
            TimingType                 = 'Measured'
            TimingSource               = 'DiagnosticsPerformanceEvent100'
            DiagnosticsEventRecordId   = [long]$diagnostic.DiagnosticsEventRecordId
            DiagnosticsEventVersion    = [int]$diagnostic.DiagnosticsEventVersion
            KernelBootEventRecordId    = [long]$kernelBoot.RecordId
            KernelGeneralEventRecordId = [long]$kernelGeneral.RecordId
        }
    }
}

function Get-BootLensSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$BootRecords
    )

    if ($BootRecords.Count -eq 0) {
        return $null
    }

    $orderedRecords = @($BootRecords | Sort-Object BootStartTimeUtc -Descending)
    $measure = $orderedRecords | Measure-Object -Property BootDurationMs -Average -Minimum -Maximum

    [pscustomobject][ordered]@{
        SampleCount           = $orderedRecords.Count
        LastBootDurationMs    = [int]$orderedRecords[0].BootDurationMs
        AverageBootDurationMs = [int][Math]::Round($measure.Average, 0, [MidpointRounding]::AwayFromZero)
        FastestBootDurationMs = [int]$measure.Minimum
        SlowestBootDurationMs = [int]$measure.Maximum
    }
}

function Get-BootLensTrend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$BootRecords,

        [ValidateRange(1, 100)]
        [int]$Count = 30
    )

    $records = @(
        $BootRecords |
            Where-Object {
                [string]$_.BootKind -eq 'Full' -and
                [string]$_.TimingType -eq 'Measured'
            } |
            Sort-Object BootStartTimeUtc -Descending |
            Select-Object -First $Count
    )

    if ($records.Count -eq 0) {
        return $null
    }

    $chronologicalRecords = @($records | Sort-Object BootStartTimeUtc)
    $durations = @($records | ForEach-Object { [long]$_.BootDurationMs } | Sort-Object)
    $middle = [int][Math]::Floor($durations.Count / 2)
    $median = if (($durations.Count % 2) -eq 1) {
        [long]$durations[$middle]
    }
    else {
        [long][Math]::Round(
            ($durations[$middle - 1] + $durations[$middle]) / 2.0,
            0,
            [MidpointRounding]::AwayFromZero
        )
    }

    $newest = $records[0]
    $previous = if ($records.Count -gt 1) { $records[1] } else { $null }

    [pscustomobject][ordered]@{
        SchemaVersion              = 1
        Source                     = 'DiagnosticsPerformanceEvent100'
        Scope                      = 'RecentMeasuredFullBoots'
        WindowLimit                = $Count
        SampleCount                = $records.Count
        OldestBootStartTimeUtc     = $chronologicalRecords[0].BootStartTimeUtc
        NewestBootStartTimeUtc     = $newest.BootStartTimeUtc
        MedianBootDurationMs      = $median
        LatestBootDurationMs      = [long]$newest.BootDurationMs
        ChangeFromMedianMs        = [long]$newest.BootDurationMs - $median
        PreviousBootDurationMs    = if ($null -ne $previous) { [long]$previous.BootDurationMs } else { $null }
        ChangeFromPreviousBootMs  = if ($null -ne $previous) {
            [long]$newest.BootDurationMs - [long]$previous.BootDurationMs
        }
        else {
            $null
        }
        Records = @(
            foreach ($record in $chronologicalRecords) {
                [pscustomobject][ordered]@{
                    BootStartTimeUtc       = $record.BootStartTimeUtc
                    BootDurationMs        = [long]$record.BootDurationMs
                    MainPathBootDurationMs = [long]$record.MainPathBootDurationMs
                    PostBootDurationMs    = [long]$record.PostBootDurationMs
                }
            }
        )
    }
}

function Get-BootLensDiagnosticSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$BootRecords,

        [ValidateRange(1, 100)]
        [int]$Count = 30
    )

    $records = @(
        $BootRecords |
            Where-Object {
                [string]$_.BootKind -eq 'Full' -and
                [string]$_.TimingType -eq 'Measured'
            } |
            Sort-Object BootStartTimeUtc -Descending |
            Select-Object -First $Count
    )

    if ($records.Count -eq 0) {
        return $null
    }

    $latest = $records[0]
    $latestState = if ($latest.IsWindowsDegradation -eq $true) {
        'Flagged'
    }
    elseif ($latest.IsWindowsDegradation -eq $false) {
        'NotFlagged'
    }
    else {
        'Unknown'
    }

    [pscustomobject][ordered]@{
        SchemaVersion                   = 1
        Source                          = 'DiagnosticsPerformanceEvent100'
        Scope                           = 'RecentMeasuredFullBoots'
        WindowLimit                     = $Count
        SampleCount                     = $records.Count
        WindowsFlaggedBootCount         = @($records | Where-Object { $_.IsWindowsDegradation -eq $true }).Count
        WindowsNotFlaggedBootCount      = @($records | Where-Object { $_.IsWindowsDegradation -eq $false }).Count
        WindowsFlagUnknownBootCount    = @($records | Where-Object { $null -eq $_.IsWindowsDegradation }).Count
        LatestBootStartTimeUtc          = $latest.BootStartTimeUtc
        LatestBootDurationMs            = [long]$latest.BootDurationMs
        LatestWindowsDegradationState   = $latestState
        LatestDiagnosticsEventRecordId  = [long]$latest.DiagnosticsEventRecordId
    }
}

function Get-BootLensReport {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 100)]
        [int]$Count = 30,

        [ValidateRange(1, 1000)]
        [int]$ScanEvents = 100
    )

    try {
        $log = Get-WinEvent -ListLog $script:DiagnosticsLogName
    }
    catch {
        throw @(
            "Cannot access the Windows boot performance log: $script:DiagnosticsLogName"
            'Open PowerShell as Administrator and run BootLens again.'
            "Windows reported: $($_.Exception.Message)"
        ) -join [Environment]::NewLine
    }

    if (-not $log.IsEnabled) {
        throw "The Windows boot performance log is disabled: $script:DiagnosticsLogName"
    }

    try {
        $rawDiagnostics = @(
            Get-WinEvent -FilterHashtable @{
                LogName = $script:DiagnosticsLogName
                Id      = 100
            } -MaxEvents $ScanEvents
        )
        $rawKernelBoot = @(
            Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-Kernel-Boot'
                Id           = 27
            } -MaxEvents $ScanEvents
        )
        $rawKernelGeneral = @(
            Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-Kernel-General'
                Id           = 12
            } -MaxEvents $ScanEvents
        )
    }
    catch {
        throw "Failed to read Windows boot events. Windows reported: $($_.Exception.Message)"
    }

    $diagnostics = @()

    foreach ($event in $rawDiagnostics) {
        try {
            $diagnostics += ConvertFrom-DiagnosticsEvent -EventRecord $event
        }
        catch {
            Write-Verbose "Excluded Diagnostics event $($event.RecordId): $($_.Exception.Message)"
        }
    }

    $kernelBoot = @()

    foreach ($event in $rawKernelBoot) {
        try {
            $kernelBoot += ConvertFrom-KernelBootEvent -EventRecord $event
        }
        catch {
            Write-Verbose "Excluded Kernel-Boot event $($event.RecordId): $($_.Exception.Message)"
        }
    }

    $kernelGeneral = @(
        $rawKernelGeneral | ForEach-Object {
            ConvertFrom-KernelGeneralEvent -EventRecord $_
        }
    )
    $allRecords = @(
        ConvertTo-BootRecord `
            -DiagnosticsEvents $diagnostics `
            -KernelBootEvents $kernelBoot `
            -KernelGeneralEvents $kernelGeneral
    )
    $records = @(
        $allRecords |
            Sort-Object BootStartTimeUtc -Descending |
            Select-Object -First $Count
    )

    [pscustomobject][ordered]@{
        Summary                  = Get-BootLensSummary -BootRecords $records
        Trend                    = Get-BootLensTrend -BootRecords $records -Count $Count
        Diagnostics              = Get-BootLensDiagnosticSummary -BootRecords $records -Count $Count
        Records                  = $records
        ScannedDiagnosticsCount  = $rawDiagnostics.Count
        ExcludedDiagnosticsCount = $rawDiagnostics.Count - $allRecords.Count
    }
}

function ConvertTo-BootLensProcessTimeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Processes,

        [Parameter(Mandatory)]
        [object]$BootRecord,

        [DateTimeOffset]$SnapshotTimeUtc = [DateTimeOffset]::UtcNow
    )

    if ([string]$BootRecord.BootKind -ne 'Full') {
        throw 'Process timeline requires a confirmed full BootRecord.'
    }

    $bootStartUtc = ([DateTimeOffset]$BootRecord.BootStartTimeUtc).ToUniversalTime()
    $snapshotUtc = $SnapshotTimeUtc.ToUniversalTime()
    $records = @(
        foreach ($process in $Processes) {
            $processId = 0
            if (-not [int]::TryParse([string]$process.ProcessId, [ref]$processId)) {
                continue
            }

            $parentProcessId = $null
            $parsedParentProcessId = 0
            if ([int]::TryParse([string]$process.ParentProcessId, [ref]$parsedParentProcessId)) {
                $parentProcessId = $parsedParentProcessId
            }

            $creationTimeUtc = $null
            $bootOffsetMs = $null
            $creationDateProperty = $process.PSObject.Properties['CreationDate']

            if ($null -ne $creationDateProperty -and $null -ne $creationDateProperty.Value) {
                try {
                    $creationDate = [datetime]$creationDateProperty.Value
                    if ($creationDate -ne [datetime]::MinValue) {
                        $creationTimeUtc = [DateTimeOffset]$creationDate.ToUniversalTime()
                        $bootOffsetMs = [long][Math]::Round(
                            ($creationTimeUtc - $bootStartUtc).TotalMilliseconds,
                            0,
                            [MidpointRounding]::AwayFromZero
                        )
                    }
                }
                catch {
                    $creationTimeUtc = $null
                    $bootOffsetMs = $null
                }
            }

            $name = [string]$process.Name
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = 'Unknown'
            }

            $executablePath = $null
            $executablePathProperty = $process.PSObject.Properties['ExecutablePath']
            if ($null -ne $executablePathProperty -and
                -not [string]::IsNullOrWhiteSpace([string]$executablePathProperty.Value)) {
                $executablePath = [string]$executablePathProperty.Value
            }

            $identityTime = if ($null -ne $creationTimeUtc) {
                $creationTimeUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
            }
            else {
                'Unavailable@{0}' -f $snapshotUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
            }

            [pscustomobject][ordered]@{
                SchemaVersion       = 1
                Source              = 'Win32ProcessCreationDate'
                SourceIdentity      = 'Win32Process|{0}|{1}' -f $processId, $identityTime
                Name                = $name
                ProcessId           = $processId
                ParentProcessId     = $parentProcessId
                ExecutablePath      = $executablePath
                CreationTimeUtc     = $creationTimeUtc
                BootStartTimeUtc    = $bootStartUtc
                BootKind            = 'Full'
                BootOffsetMs        = $bootOffsetMs
                CreationTimeStatus  = if ($null -eq $creationTimeUtc) { 'Unavailable' } else { 'Available' }
            }
        }
    )
    $sortedRecords = @(
        $records | Sort-Object `
            @{ Expression = { if ($null -eq $_.BootOffsetMs) { [long]::MaxValue } else { [long]$_.BootOffsetMs } } },
            ProcessId
    )

    [pscustomobject][ordered]@{
        SchemaVersion          = 1
        Source                 = 'Win32ProcessCreationDate'
        SnapshotTimeUtc        = $snapshotUtc
        BootStartTimeUtc       = $bootStartUtc
        BootKind               = 'Full'
        Scope                  = 'CurrentRunningProcesses'
        ProcessCount           = $sortedRecords.Count
        TimestampedCount       = @($sortedRecords | Where-Object CreationTimeStatus -eq 'Available').Count
        UnavailableCount       = @($sortedRecords | Where-Object CreationTimeStatus -eq 'Unavailable').Count
        NegativeOffsetCount    = @($sortedRecords | Where-Object { $null -ne $_.BootOffsetMs -and $_.BootOffsetMs -lt 0 }).Count
        Processes              = $sortedRecords
    }
}

function Get-BootLensProcessTimeline {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 1000)]
        [int]$ScanEvents = 100,

        [ValidateRange(1, 120)]
        [int]$OperationTimeoutSec = 15
    )

    $bootReport = Get-BootLensReport -Count 1 -ScanEvents $ScanEvents
    if ($null -eq $bootReport.Summary -or $bootReport.Records.Count -eq 0) {
        throw 'No confirmed full boot record is available for the process timeline.'
    }

    try {
        $processes = @(
            Get-CimInstance -ClassName Win32_Process `
                -OperationTimeoutSec $OperationTimeoutSec `
                -ErrorAction Stop
        )
    }
    catch {
        throw @(
            'Cannot read the current process snapshot from Win32_Process.'
            'Open PowerShell as Administrator and run BootLens again.'
            "Windows reported: $($_.Exception.Message)"
        ) -join [Environment]::NewLine
    }

    return ConvertTo-BootLensProcessTimeline `
        -Processes $processes `
        -BootRecord $bootReport.Records[0]
}

Export-ModuleMember -Function `
    ConvertTo-BootRecord, `
    Get-BootLensSummary, `
    Get-BootLensTrend, `
    Get-BootLensDiagnosticSummary, `
    Get-BootLensReport, `
    ConvertTo-BootLensProcessTimeline, `
    Get-BootLensProcessTimeline
