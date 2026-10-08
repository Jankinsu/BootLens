[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$MaxEvents = 20,

    [switch]$Summary,

    [ValidateRange(1, [long]::MaxValue)]
    [long]$RecordId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'

try {
    $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
}
catch {
    $message = @(
        "Cannot access the Windows boot performance log: $logName"
        'Open PowerShell as Administrator and run this script again.'
        "Windows reported: $($_.Exception.Message)"
    ) -join [Environment]::NewLine

    Write-Error $message
    exit 2
}

if (-not $log.IsEnabled) {
    Write-Error "The Windows boot performance log is disabled: $logName"
    exit 3
}

try {
    if ($PSBoundParameters.ContainsKey('RecordId')) {
        $filterXPath = "*[System[(EventID=101) and (EventRecordID=$RecordId)]]"
        $events = @(
            Get-WinEvent -LogName $logName -FilterXPath $filterXPath -ErrorAction Stop
        )
    }
    else {
        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Id      = 101
            } -MaxEvents $MaxEvents -ErrorAction Stop
        )
    }
}
catch [System.InvalidOperationException] {
    if ($PSBoundParameters.ContainsKey('RecordId')) {
        Write-Warning "No Event ID 101 record with RecordId $RecordId was found in: $logName"
    }
    else {
        Write-Warning "No Event ID 101 records were found in: $logName"
    }
    return
}
catch {
    Write-Error "Failed to read Event ID 101 records. Windows reported: $($_.Exception.Message)"
    exit 4
}

if ($events.Count -eq 0) {
    if ($PSBoundParameters.ContainsKey('RecordId')) {
        Write-Warning "No Event ID 101 record with RecordId $RecordId was found in: $logName"
    }
    else {
        Write-Warning "No Event ID 101 records were found in: $logName"
    }
    return
}

$records = @(
    foreach ($event in $events) {
        [xml]$eventXml = $event.ToXml()
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

        [pscustomobject]@{
            RecordId    = $event.RecordId
            TimeCreated = $event.TimeCreated
            Level       = $event.LevelDisplayName
            Message     = $event.Message
            EventData   = $eventData
        }
    }
)

if ($Summary) {
    Write-Output ('Event ID 101 records: {0}' -f $records.Count)

    $summaryRecords = @(
        foreach ($record in $records) {
            [pscustomobject]@{
                RecordId          = $record.RecordId
                TimeCreated       = $record.TimeCreated
                StartTimeUtc      = $record.EventData['StartTime']
                Name              = $record.EventData['Name']
                TotalTimeMs       = $record.EventData['TotalTime']
                DegradationTimeMs = $record.EventData['DegradationTime']
            }
        }
    )

    $summaryRecords | Format-Table -AutoSize
    return
}

$records | ConvertTo-Json -Depth 5
