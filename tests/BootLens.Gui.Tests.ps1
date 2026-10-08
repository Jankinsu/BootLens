Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$output = & (Join-Path $PSScriptRoot '..\bootlens-gui.ps1') -ValidateOnly

if ($output -ne 'BootLens GUI XAML: OK') {
    throw "Unexpected GUI validation result: $output"
}

$xamlPath = Join-Path $PSScriptRoot '..\ui\MainWindow.xaml'
[xml]$xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
$degradationGrid = @(
    $xaml.SelectNodes("//*[local-name()='DataGrid']") |
        Where-Object {
            $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml') -eq 'DegradationDataGrid'
        }
)
if ($degradationGrid.Count -ne 1) {
    throw 'Expected one degradation events grid.'
}

$mainColumns = $degradationGrid[0].SelectNodes(
    "./*[local-name()='DataGrid.Columns']/*[local-name()='DataGridTextColumn']"
)
if ($mainColumns.Count -ne 4) {
    throw "Expected four concise main columns, found $($mainColumns.Count)."
}

if ($degradationGrid[0].GetAttribute('RowDetailsVisibilityMode') -ne 'VisibleWhenSelected' -or
    $null -eq $degradationGrid[0].SelectSingleNode("./*[local-name()='DataGrid.RowDetailsTemplate']")) {
    throw 'Expected degradation details to expand when a row is selected.'
}

Write-Output 'BootLens GUI tests: PASS'
