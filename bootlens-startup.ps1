[CmdletBinding()]
param(
    [switch]$AsJson,

    [switch]$ShowCommand
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.Startup.psm1') -Force

$items = @(Get-RegistryRunStartupItem)

if ($AsJson) {
    $items | ConvertTo-Json -Depth 4
    return
}

Write-Output 'BootLens Startup Items'
Write-Output ''
Write-Output ('Configured logon items: {0}' -f $items.Count)
Write-Output 'Enabled state: Unknown (not inferred from undocumented data)'
Write-Output ''

if ($items.Count -eq 0) {
    Write-Output 'No Registry Run startup items were found.'
    return
}

if ($ShowCommand) {
    $items |
        Select-Object Name, Scope, RegistryView, CommandParseStatus, CommandLineRaw |
        Format-Table -Wrap -AutoSize
}
else {
    $items |
        Select-Object `
            Name,
            Scope,
            RegistryView,
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
