[CmdletBinding()]
param(
    [ValidateSet('All', 'RegistryRun', 'StartupFolder', 'ScheduledTask')]
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
    default { @(Get-BootLensStartupItem) }
})

if ($AsJson) {
    $items | ConvertTo-Json -Depth 4
    return
}

Write-Output 'BootLens Startup Items'
Write-Output ''
Write-Output ('Configured logon items: {0}' -f $items.Count)
Write-Output 'Enabled state: documented task state where available; otherwise Unknown'

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
            EnabledState |
        Format-Table -AutoSize
}
