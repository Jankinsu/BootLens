[CmdletBinding()]
param(
    [ValidateSet('All', 'RegistryRun', 'StartupFolder', 'ScheduledTask', 'WindowsService')]
    [string]$Source = 'All',

    [switch]$AsJson,

    [switch]$ShowCommand
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.Startup.psm1') -Force

$items = @(switch ($Source) {
    'RegistryRun' { @(Get-RegistryRunStartupItem) }
    'StartupFolder' { @(Get-StartupFolderStartupItem) }
    'ScheduledTask' { @(Get-ScheduledTaskStartupItem) }
    'WindowsService' { @(Get-WindowsServiceStartupItem) }
    default { @(Get-BootLensStartupItem) }
})

if ($AsJson) {
    $items | ConvertTo-Json -Depth 4
    return
}

Write-Output 'BootLens Startup Items'
Write-Output ''
Write-Output ('Configured startup items: {0}' -f $items.Count)
Write-Output 'Startup state: based on source configuration; unavailable values remain Unknown'

foreach ($sourceGroup in @($items | Group-Object Source | Sort-Object Name)) {
    Write-Output ('  {0}: {1}' -f $sourceGroup.Name, $sourceGroup.Count)
}

Write-Output ''

if ($items.Count -eq 0) {
    Write-Output 'No matching startup items were found.'
    return
}

if ($ShowCommand) {
    $items |
        Select-Object `
            Name,
            Source,
            Scope,
            CommandParseStatus,
            @{ Name = 'SourceDetail'; Expression = {
                switch ($_.Source) {
                    'RegistryRun' { $_.CommandLineRaw }
                    'StartupFolder' { $_.StartupEntryPath }
                    'ScheduledTask' { '{0}{1}' -f $_.TaskPath, $_.TaskName }
                    'WindowsService' { $_.CommandLineRaw }
                }
            } } |
        Format-Table -Wrap -AutoSize
}
else {
    $items |
        Select-Object `
            Name,
            Source,
            Scope,
            @{ Name = 'Executable'; Expression = {
                if ($_.CommandParseStatus -eq 'Resolved') {
                    $_.ExecutablePath
                }
                else {
                    'Unknown'
                }
            } },
            @{ Name = 'StartupState'; Expression = {
                if ($_.Source -eq 'WindowsService') {
                    if ($_.ServiceDelayedAutoStart) { 'Auto (Delayed)' } else { 'Auto' }
                }
                else {
                    $_.EnabledState
                }
            } } |
        Format-Table -AutoSize
}
