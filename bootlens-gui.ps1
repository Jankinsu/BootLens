[CmdletBinding()]
param(
    [ValidateSet(5, 10, 20, 50)]
    [int]$Count = 10,

    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

$xamlPath = Join-Path $PSScriptRoot 'ui\MainWindow.xaml'
[xml]$xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$controlNames = @(
    'CountComboBox'
    'RefreshButton'
    'ErrorBorder'
    'ErrorTextBlock'
    'LastBootValue'
    'AverageValue'
    'FastestValue'
    'SlowestValue'
    'LatestBootTimeText'
    'MainPathValue'
    'MainPathProgress'
    'PostBootValue'
    'PostBootProgress'
    'SampleCountText'
    'HistoryDataGrid'
    'FooterStatusText'
)

$controls = @{}

foreach ($name in $controlNames) {
    $control = $window.FindName($name)

    if ($null -eq $control) {
        throw "Required GUI control was not found: $name"
    }

    $controls[$name] = $control
}

if ($ValidateOnly) {
    Write-Output 'BootLens GUI XAML: OK'
    return
}

Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.psm1') -Force

function Format-Duration {
    param(
        [Parameter(Mandatory)]
        [int]$Milliseconds
    )

    return '{0:F1} s' -f ($Milliseconds / 1000.0)
}

function Set-SelectedCount {
    param(
        [Parameter(Mandatory)]
        [int]$Value
    )

    for ($index = 0; $index -lt $controls.CountComboBox.Items.Count; $index++) {
        if ([int]$controls.CountComboBox.Items[$index].Content -eq $Value) {
            $controls.CountComboBox.SelectedIndex = $index
            return
        }
    }
}

function Set-LoadingState {
    param(
        [Parameter(Mandatory)]
        [bool]$IsLoading
    )

    $controls.RefreshButton.IsEnabled = -not $IsLoading
    $controls.CountComboBox.IsEnabled = -not $IsLoading
    $window.Cursor = if ($IsLoading) {
        [Windows.Input.Cursors]::Wait
    }
    else {
        [Windows.Input.Cursors]::Arrow
    }
}

function Show-ErrorMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $controls.ErrorTextBlock.Text = $Message
    $controls.ErrorBorder.Visibility = [Windows.Visibility]::Visible
    $controls.FooterStatusText.Text = 'Read failed'
}

function Update-BootLensView {
    Set-LoadingState -IsLoading $true
    $controls.ErrorBorder.Visibility = [Windows.Visibility]::Collapsed
    $controls.FooterStatusText.Text = 'Reading Windows boot events...'

    try {
        $selectedCount = [int]$controls.CountComboBox.SelectedItem.Content
        $scanEvents = [Math]::Max(100, $selectedCount * 5)
        $report = Get-BootLensReport -Count $selectedCount -ScanEvents $scanEvents

        if ($null -eq $report.Summary -or $report.Records.Count -eq 0) {
            throw 'No confirmed full boot records were found.'
        }

        $summary = $report.Summary
        $latest = $report.Records[0]
        $mainPercent = if ($latest.BootDurationMs -gt 0) {
            100.0 * $latest.MainPathBootDurationMs / $latest.BootDurationMs
        }
        else {
            0
        }
        $postPercent = if ($latest.BootDurationMs -gt 0) {
            100.0 * $latest.PostBootDurationMs / $latest.BootDurationMs
        }
        else {
            0
        }

        $controls.LastBootValue.Text = Format-Duration $summary.LastBootDurationMs
        $controls.AverageValue.Text = Format-Duration $summary.AverageBootDurationMs
        $controls.FastestValue.Text = Format-Duration $summary.FastestBootDurationMs
        $controls.SlowestValue.Text = Format-Duration $summary.SlowestBootDurationMs
        $controls.LatestBootTimeText.Text = $latest.BootStartTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        $controls.MainPathValue.Text = '{0} / {1:F0}%' -f
            (Format-Duration $latest.MainPathBootDurationMs),
            $mainPercent
        $controls.PostBootValue.Text = '{0} / {1:F0}%' -f
            (Format-Duration $latest.PostBootDurationMs),
            $postPercent
        $controls.MainPathProgress.Value = $mainPercent
        $controls.PostBootProgress.Value = $postPercent
        $controls.SampleCountText.Text = '{0} confirmed full boots' -f $summary.SampleCount

        $history = @(
            foreach ($record in $report.Records) {
                $status = if ($record.IsWindowsDegradation -eq $true) {
                    'Degraded'
                }
                elseif ($record.IsWindowsDegradation -eq $false) {
                    'Normal'
                }
                else {
                    'Unknown'
                }

                [pscustomobject]@{
                    Started  = $record.BootStartTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                    Total    = Format-Duration $record.BootDurationMs
                    MainPath = Format-Duration $record.MainPathBootDurationMs
                    PostBoot = Format-Duration $record.PostBootDurationMs
                    Apps     = $record.StartupAppCount
                    Status   = $status
                }
            }
        )

        $controls.HistoryDataGrid.ItemsSource = $history
        $controls.FooterStatusText.Text = 'Updated {0:HH:mm:ss}' -f (Get-Date)
    }
    catch {
        $message = $_.Exception.Message

        if ($message -match 'Administrator|unauthorized|access is denied') {
            $message = @(
                'Administrator access is required to read the boot performance log.'
                'Open the PowerShell (AD) profile in Windows Terminal and run BootLens again.'
            ) -join [Environment]::NewLine
        }

        Show-ErrorMessage -Message $message
    }
    finally {
        Set-LoadingState -IsLoading $false
    }
}

Set-SelectedCount -Value $Count
$controls.RefreshButton.Add_Click({ Update-BootLensView })
$window.Add_ContentRendered({ Update-BootLensView })

$null = $window.ShowDialog()
