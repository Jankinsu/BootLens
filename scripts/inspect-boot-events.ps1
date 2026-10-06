[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$MaxEvents = 10,

    [string]$ExportRawXmlDirectory,

    [string]$ExportJsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'

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

        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $eventData[$name] = $node.InnerText
    }

    return $eventData
}

function Get-OptionalValue {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Data,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($Data.Contains($Name)) {
        return $Data[$Name]
    }

    return $null
}

try {
    $log = Get-WinEvent -ListLog $logName
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
    $events = @(
        Get-WinEvent -FilterHashtable @{
            LogName = $logName
            Id      = 100
        } -MaxEvents $MaxEvents
    )
}
catch [System.InvalidOperationException] {
    Write-Warning "No Event ID 100 records were found in: $logName"
    return
}
catch {
    Write-Error "Failed to read Event ID 100 records. Windows reported: $($_.Exception.Message)"
    exit 4
}

if ($events.Count -eq 0) {
    Write-Warning "No Event ID 100 records were found in: $logName"
    return
}

if (-not [string]::IsNullOrWhiteSpace($ExportRawXmlDirectory)) {
    $null = New-Item -ItemType Directory -Path $ExportRawXmlDirectory -Force
    $exportPath = (Resolve-Path -LiteralPath $ExportRawXmlDirectory).Path

    foreach ($event in $events) {
        $fileName = 'event-100-{0}-{1}.xml' -f $event.TimeCreated.ToString('yyyyMMdd-HHmmss'), $event.RecordId
        $filePath = Join-Path $exportPath $fileName
        Set-Content -LiteralPath $filePath -Value $event.ToXml() -Encoding UTF8
    }

    Write-Verbose "Exported raw Event ID 100 XML files to: $exportPath"
}

$records = @(
foreach ($event in $events) {
    $data = Get-EventDataMap -EventRecord $event

    [pscustomobject]@{
        RecordId              = $event.RecordId
        TimeCreated           = $event.TimeCreated
        BootStartTime         = Get-OptionalValue -Data $data -Name 'BootStartTime'
        BootEndTime           = Get-OptionalValue -Data $data -Name 'BootEndTime'
        BootTimeMs            = Get-OptionalValue -Data $data -Name 'BootTime'
        MainPathBootTimeMs    = Get-OptionalValue -Data $data -Name 'MainPathBootTime'
        BootPostBootTimeMs    = Get-OptionalValue -Data $data -Name 'BootPostBootTime'
        SystemBootInstance    = Get-OptionalValue -Data $data -Name 'SystemBootInstance'
        UserBootInstance      = Get-OptionalValue -Data $data -Name 'UserBootInstance'
        RebootAfterInstall    = Get-OptionalValue -Data $data -Name 'BootIsRebootAfterInstall'
        RawEventData          = $data
    }
}
)

if (-not [string]::IsNullOrWhiteSpace($ExportJsonPath)) {
    $jsonParent = Split-Path -Parent $ExportJsonPath

    if (-not [string]::IsNullOrWhiteSpace($jsonParent)) {
        $null = New-Item -ItemType Directory -Path $jsonParent -Force
    }

    $records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ExportJsonPath -Encoding UTF8
    Write-Verbose "Exported parsed Event ID 100 data to: $ExportJsonPath"
}

$records
