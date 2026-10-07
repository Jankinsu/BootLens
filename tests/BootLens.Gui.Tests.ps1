Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$output = & (Join-Path $PSScriptRoot '..\bootlens-gui.ps1') -ValidateOnly

if ($output -ne 'BootLens GUI XAML: OK') {
    throw "Unexpected GUI validation result: $output"
}

Write-Output 'BootLens GUI tests: PASS'
