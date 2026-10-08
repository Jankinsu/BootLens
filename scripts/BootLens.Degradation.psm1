Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'BootLens.psm1')

$script:DiagnosticsLogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'

function Get-DegradationEventData {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )

    [xml]$eventXml = $EventRecord.ToXml()
    $data = [ordered]@{}
    $nodes = $eventXml.SelectNodes(
        "/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data']"
    )

    foreach ($node in $nodes) {
        $name = $node.GetAttribute('Name')
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $data[$name] = $node.InnerText
        }
    }

    return $data
}

function ConvertTo-DegradationUtcTime {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor
        [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [DateTimeOffset]::TryParse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            $styles,
            [ref]$parsed
        )) {
        return $null
    }

    return $parsed.ToUniversalTime()
}

function Get-DegradationOptionalInt {
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

function Normalize-DegradationPath {
    param(
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [IO.Path]::IsPathRooted($expanded)) {
        return $null
    }

    try {
        return [IO.Path]::GetFullPath($expanded).TrimEnd([char[]]@('\', '/'))
    }
    catch {
        return $null
    }
}

function ConvertTo-DegradationIdentityToken {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    $baseName = [IO.Path]::GetFileNameWithoutExtension($Value.Trim())
    return [regex]::Replace($baseName, '[^\p{L}\p{N}]', '').ToUpperInvariant()
}

function ConvertTo-BootLensDegradationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$EventData,

        [Parameter(Mandatory)]
        [long]$EventRecordId,

        [Parameter(Mandatory)]
        [DateTimeOffset]$TimeCreatedUtc,

        [int]$EventVersion = 1,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$BootRecords,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$StartupItems
    )

    $startTimeRaw = if ($EventData.Contains('StartTime')) { [string]$EventData['StartTime'] } else { $null }
    $startTimeUtc = ConvertTo-DegradationUtcTime -Value $startTimeRaw
    $bootMatches = @()
    if ($null -ne $startTimeUtc) {
        $startTicks = $startTimeUtc.UtcDateTime.Ticks
        $bootMatches = @(
            $BootRecords | Where-Object {
                $bootTime = ([DateTimeOffset]$_.BootStartTimeUtc).ToUniversalTime()
                $bootTime.UtcDateTime.Ticks -eq $startTicks
            }
        )
    }

    $bootAssociationStatus = if ($bootMatches.Count -eq 1) {
        'Matched'
    }
    elseif ($bootMatches.Count -gt 1) {
        'Ambiguous'
    }
    else {
        'Unmatched'
    }
    $bootRecord = if ($bootMatches.Count -eq 1) { $bootMatches[0] } else { $null }

    $name = if ($EventData.Contains('Name')) { [string]$EventData['Name'] } else { $null }
    $path = if ($EventData.Contains('Path')) { [string]$EventData['Path'] } else { $null }
    $normalizedEventPath = Normalize-DegradationPath -Path $path
    $startupMatches = @()
    $targetMatchLevel = 'Unmatched'
    $targetMatchReason = 'No reliable startup-item match was found.'

    if ([IO.Path]::GetFileName($name) -ieq 'svchost.exe') {
        $targetMatchLevel = 'GenericHost'
        $targetMatchReason = 'The event identifies svchost.exe but contains no service, group, PID, or command-line identity.'
    }
    elseif ($null -ne $normalizedEventPath) {
        $startupMatches = @(
            $StartupItems | Where-Object {
                $candidatePath = Normalize-DegradationPath -Path ([string]$_.ExecutablePath)
                $null -ne $candidatePath -and
                    [string]::Equals($candidatePath, $normalizedEventPath, [StringComparison]::OrdinalIgnoreCase)
            }
        )

        if ($startupMatches.Count -eq 1) {
            $targetMatchLevel = 'ExactPath'
            $targetMatchReason = 'The event path exactly matches one item in the current startup-item snapshot.'
        }
        elseif ($startupMatches.Count -gt 1) {
            $targetMatchLevel = 'Ambiguous'
            $targetMatchReason = 'The event path matches multiple current startup-item entries.'
        }
        else {
            $eventToken = ConvertTo-DegradationIdentityToken -Value $name
            if ($eventToken.Length -gt 0) {
                $startupMatches = @(
                    $StartupItems | Where-Object {
                        (ConvertTo-DegradationIdentityToken -Value ([string]$_.Name)) -eq $eventToken
                    }
                )
            }

            if ($startupMatches.Count -eq 1) {
                $targetMatchLevel = 'FamilyCandidate'
                $targetMatchReason = 'The normalized event executable name matches one current startup-item name, but the full paths differ.'
            }
            elseif ($startupMatches.Count -gt 1) {
                $targetMatchLevel = 'Ambiguous'
                $targetMatchReason = 'The normalized event executable name matches multiple current startup-item names.'
            }
        }
    }

    $matchItems = @(
        foreach ($item in $startupMatches) {
            [pscustomobject][ordered]@{
                Name           = [string]$item.Name
                Source         = [string]$item.Source
                Scope          = [string]$item.Scope
                ExecutablePath = [string]$item.ExecutablePath
            }
        }
    )

    [pscustomobject][ordered]@{
        SchemaVersion             = 1
        Source                    = 'DiagnosticsPerformanceEvent101'
        SourceIdentity            = 'DiagnosticsPerformanceEvent101|{0}' -f $EventRecordId
        EventRecordId             = $EventRecordId
        EventVersion              = $EventVersion
        TimeCreatedUtc            = $TimeCreatedUtc.ToUniversalTime()
        StartTimeRaw              = $startTimeRaw
        StartTimeUtc              = $startTimeUtc
        BootAssociationStatus     = $bootAssociationStatus
        BootRecordId              = if ($null -ne $bootRecord) { [long]$bootRecord.DiagnosticsEventRecordId } else { $null }
        BootDurationMs            = if ($null -ne $bootRecord) { [int]$bootRecord.BootDurationMs } else { $null }
        Name                      = $name
        FriendlyName              = if ($EventData.Contains('FriendlyName')) { [string]$EventData['FriendlyName'] } else { $null }
        Version                   = if ($EventData.Contains('Version')) { [string]$EventData['Version'] } else { $null }
        TotalTimeMs               = Get-DegradationOptionalInt -Data $EventData -Name 'TotalTime'
        DegradationTimeMs         = Get-DegradationOptionalInt -Data $EventData -Name 'DegradationTime'
        Path                      = $path
        ProductName               = if ($EventData.Contains('ProductName')) { [string]$EventData['ProductName'] } else { $null }
        CompanyName               = if ($EventData.Contains('CompanyName')) { [string]$EventData['CompanyName'] } else { $null }
        TargetMatchLevel          = $targetMatchLevel
        TargetMatchReason         = $targetMatchReason
        StartupItemMatchCount     = $matchItems.Count
        StartupItemMatches        = $matchItems
    }
}

function ConvertTo-BootLensDegradationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Records,

        [ValidateRange(1, 100)]
        [int]$Count = 10
    )

    $orderedRecords = @(
        $Records |
            Sort-Object `
                @{ Expression = { if ($null -eq $_.StartTimeUtc) { [DateTime]::MinValue } else { ([DateTimeOffset]$_.StartTimeUtc).UtcDateTime } }; Descending = $true },
                @{ Expression = { $_.EventRecordId }; Descending = $true } |
            Select-Object -First $Count
    )
    $matchedBootIds = @(
        $orderedRecords |
            Where-Object { $_.BootAssociationStatus -eq 'Matched' } |
            Select-Object -ExpandProperty BootRecordId -Unique
    )

    [pscustomobject][ordered]@{
        SchemaVersion          = 1
        Source                 = 'DiagnosticsPerformanceEvent101'
        EventCount             = $orderedRecords.Count
        MatchedBootCount       = $matchedBootIds.Count
        ExactPathCount         = @($orderedRecords | Where-Object TargetMatchLevel -eq 'ExactPath').Count
        FamilyCandidateCount  = @($orderedRecords | Where-Object TargetMatchLevel -eq 'FamilyCandidate').Count
        GenericHostCount       = @($orderedRecords | Where-Object TargetMatchLevel -eq 'GenericHost').Count
        AmbiguousTargetCount   = @($orderedRecords | Where-Object TargetMatchLevel -eq 'Ambiguous').Count
        UnmatchedTargetCount   = @($orderedRecords | Where-Object TargetMatchLevel -eq 'Unmatched').Count
        UnmatchedBootCount     = @($orderedRecords | Where-Object BootAssociationStatus -ne 'Matched').Count
        Records                = $orderedRecords
    }
}

function Get-BootLensDegradationReport {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 100)]
        [int]$Count = 10,

        [ValidateRange(1, 1000)]
        [int]$ScanEvents = 100,

        [ValidateRange(1, 100)]
        [int]$BootCount = 100,

        [ValidateRange(1, 1000)]
        [int]$BootScanEvents = 1000,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$StartupItems
    )

    try {
        $log = Get-WinEvent -ListLog $script:DiagnosticsLogName -ErrorAction Stop
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

    $bootReport = Get-BootLensReport -Count $BootCount -ScanEvents $BootScanEvents
    try {
        $rawEvents = @(
            Get-WinEvent -FilterHashtable @{
                LogName = $script:DiagnosticsLogName
                Id      = 101
            } -MaxEvents $ScanEvents -ErrorAction Stop
        )
    }
    catch [System.InvalidOperationException] {
        $rawEvents = @()
    }
    catch {
        throw @(
            "Failed to read Event ID 101 records from: $script:DiagnosticsLogName"
            "Windows reported: $($_.Exception.Message)"
        ) -join [Environment]::NewLine
    }

    $records = @(
        foreach ($event in $rawEvents) {
            try {
                ConvertTo-BootLensDegradationRecord `
                    -EventData (Get-DegradationEventData -EventRecord $event) `
                    -EventRecordId ([long]$event.RecordId) `
                    -TimeCreatedUtc ([DateTimeOffset]$event.TimeCreated.ToUniversalTime()) `
                    -EventVersion ([int]$event.Version) `
                    -BootRecords $bootReport.Records `
                    -StartupItems $StartupItems
            }
            catch {
                Write-Verbose "Excluded Diagnostics Event 101 record $($event.RecordId): $($_.Exception.Message)"
            }
        }
    )

    return ConvertTo-BootLensDegradationReport -Records $records -Count $Count
}

Export-ModuleMember -Function `
    ConvertTo-BootLensDegradationRecord, `
    ConvertTo-BootLensDegradationReport, `
    Get-BootLensDegradationReport
