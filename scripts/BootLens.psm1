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

function Get-BootLensReport {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 100)]
        [int]$Count = 10,

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
        Records                  = $records
        ScannedDiagnosticsCount  = $rawDiagnostics.Count
        ExcludedDiagnosticsCount = $rawDiagnostics.Count - $allRecords.Count
    }
}

Export-ModuleMember -Function ConvertTo-BootRecord, Get-BootLensSummary, Get-BootLensReport
