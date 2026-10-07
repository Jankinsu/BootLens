Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\BootLens.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected: $Expected; Actual: $Actual"
    }
}

function New-DiagnosticsEvent {
    param(
        [int]$BootDurationMs = 32865,
        [int]$MainPathBootDurationMs = 9265,
        [int]$PostBootDurationMs = 23600
    )

    [pscustomobject]@{
        BootStartTimeUtc          = [DateTimeOffset]'2026-10-07T08:35:20.7602927Z'
        BootDurationMs           = $BootDurationMs
        MainPathBootDurationMs   = $MainPathBootDurationMs
        PostBootDurationMs       = $PostBootDurationMs
        StartupAppCount          = 14
        IsWindowsDegradation     = $false
        IsRebootAfterInstall     = $false
        DiagnosticsEventRecordId = 1096
        DiagnosticsEventVersion = 2
    }
}

$kernelGeneral = [pscustomobject]@{
    TimeCreatedUtc = [DateTimeOffset]'2026-10-07T08:35:20.7891917Z'
    RecordId       = 212988
}
$kernelBoot = [pscustomobject]@{
    TimeCreatedUtc = [DateTimeOffset]'2026-10-07T08:35:20.7895954Z'
    RecordId       = 212995
    BootTypeCode   = 0
}

$record = @(
    ConvertTo-BootRecord `
        -DiagnosticsEvents @(New-DiagnosticsEvent) `
        -KernelBootEvents @($kernelBoot) `
        -KernelGeneralEvents @($kernelGeneral)
)
Assert-Equal 1 $record.Count 'A valid full boot should be accepted.'
Assert-Equal 32865 $record[0].BootDurationMs 'Boot duration should be preserved.'
Assert-Equal 'Measured' $record[0].TimingType 'Timing type should be measured.'
Assert-Equal 212995 $record[0].KernelBootEventRecordId 'Kernel-Boot evidence should be preserved.'

$fastStartupKernelBoot = $kernelBoot.PSObject.Copy()
$fastStartupKernelBoot.BootTypeCode = 1
$record = @(
    ConvertTo-BootRecord `
        -DiagnosticsEvents @(New-DiagnosticsEvent) `
        -KernelBootEvents @($fastStartupKernelBoot) `
        -KernelGeneralEvents @($kernelGeneral)
)
Assert-Equal 0 $record.Count 'A non-zero kernel boot type should be excluded.'

$record = @(
    ConvertTo-BootRecord `
        -DiagnosticsEvents @(New-DiagnosticsEvent) `
        -KernelBootEvents @($kernelBoot) `
        -KernelGeneralEvents @()
)
Assert-Equal 0 $record.Count 'A boot without Kernel-General evidence should be excluded.'

$record = @(
    ConvertTo-BootRecord `
        -DiagnosticsEvents @(New-DiagnosticsEvent -BootDurationMs 32866) `
        -KernelBootEvents @($kernelBoot) `
        -KernelGeneralEvents @($kernelGeneral)
)
Assert-Equal 0 $record.Count 'A duration invariant violation should be excluded.'

$secondKernelBoot = $kernelBoot.PSObject.Copy()
$secondKernelBoot.RecordId = 212996
$record = @(
    ConvertTo-BootRecord `
        -DiagnosticsEvents @(New-DiagnosticsEvent) `
        -KernelBootEvents @($kernelBoot, $secondKernelBoot) `
        -KernelGeneralEvents @($kernelGeneral)
)
Assert-Equal 0 $record.Count 'An ambiguous correlation should be excluded.'

$summaryInput = @(
    [pscustomobject]@{ BootStartTimeUtc = [DateTimeOffset]'2026-10-07T08:35:20Z'; BootDurationMs = 30000 }
    [pscustomobject]@{ BootStartTimeUtc = [DateTimeOffset]'2026-10-06T08:35:20Z'; BootDurationMs = 40000 }
    [pscustomobject]@{ BootStartTimeUtc = [DateTimeOffset]'2026-10-05T08:35:20Z'; BootDurationMs = 50000 }
)
$summary = Get-BootLensSummary -BootRecords $summaryInput
Assert-Equal 3 $summary.SampleCount 'Summary should count all records.'
Assert-Equal 30000 $summary.LastBootDurationMs 'Summary should select the newest boot.'
Assert-Equal 40000 $summary.AverageBootDurationMs 'Summary should calculate the average.'
Assert-Equal 30000 $summary.FastestBootDurationMs 'Summary should calculate the fastest boot.'
Assert-Equal 50000 $summary.SlowestBootDurationMs 'Summary should calculate the slowest boot.'

Write-Output 'BootLens tests: PASS'
