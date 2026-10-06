[CmdletBinding()]
param(
    [ValidateRange(1, 500)]
    [int]$MaxEvents = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$events = @(
    Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Boot'
        Id           = 27
    } -MaxEvents $MaxEvents
)

foreach ($event in $events) {
    [xml]$eventXml = $event.ToXml()
    $data = @{}
    $dataNodes = $eventXml.SelectNodes(
        "/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data']"
    )

    foreach ($node in $dataNodes) {
        $name = $node.GetAttribute('Name')

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $data[$name] = $node.InnerText
        }
    }

    [pscustomobject]@{
        RecordId     = $event.RecordId
        TimeCreated  = $event.TimeCreated
        BootTypeCode = if ($data.ContainsKey('BootType')) {
            $data['BootType']
        }
        else {
            $null
        }
        LoadOptions  = if ($data.ContainsKey('LoadOptions')) {
            $data['LoadOptions']
        }
        else {
            $null
        }
    }
}
