[CmdletBinding()]
param(
    [ValidateSet(5, 10, 20, 30, 50)]
    [int]$Count = 30,

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
    'CountLabelText'
    'MainTabControl'
    'ProcessTimelineTab'
    'DegradationTab'
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
    'TrendSummaryText'
    'TrendChartCanvas'
    'DiagnosticSummaryText'
    'HistoryDataGrid'
    'StartupTotalValue'
    'RegistryStartupCountValue'
    'FolderStartupCountValue'
    'TaskStartupCountValue'
    'ServiceStartupCountValue'
    'UnresolvedStartupCountValue'
    'StartupItemCountText'
    'StartupSearchTextBox'
    'StartupSourceFilterComboBox'
    'StartupItemsDataGrid'
    'ProcessTotalValue'
    'ProcessTimestampedValue'
    'ProcessUnavailableValue'
    'ProcessNegativeOffsetValue'
    'ProcessSnapshotText'
    'ProcessTimelineDataGrid'
    'DegradationEventCountValue'
    'DegradationMatchedBootCountValue'
    'DegradationExactPathCountValue'
    'DegradationListStatusText'
    'DegradationDataGrid'
    'FooterStatusText'
)

$controls = @{}
$script:StartupItemRows = @()
$script:StartupItems = @()
$script:ProcessTimelineLoaded = $false
$script:DegradationLoaded = $false

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
Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.Startup.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts\BootLens.Degradation.psm1') -Force

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
}

function Add-TrendText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][double]$X,
        [Parameter(Mandatory)][double]$Y,
        [double]$Width = 100,
        [Windows.Media.Brush]$Foreground = [Windows.Media.Brushes]::Gray,
        [double]$FontSize = 11
    )

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.Width = $Width
    $label.FontSize = $FontSize
    $label.Foreground = $Foreground
    [Windows.Controls.Canvas]::SetLeft($label, $X)
    [Windows.Controls.Canvas]::SetTop($label, $Y)
    [void]$controls.TrendChartCanvas.Children.Add($label)
}

function Update-BootTrendChart {
    param(
        [Parameter(Mandatory)]
        [object[]]$TrendRecords
    )

    $canvas = $controls.TrendChartCanvas
    $canvas.Children.Clear()
    if ($TrendRecords.Count -eq 0) {
        return
    }

    $left = 58.0
    $right = 884.0
    $top = 16.0
    $bottom = 174.0
    $values = @(
        foreach ($record in $TrendRecords) {
            [double]$record.BootDurationMs
            [double]$record.MainPathBootDurationMs
            [double]$record.PostBootDurationMs
        }
    )
    $minimum = [double](($values | Measure-Object -Minimum).Minimum)
    $maximum = [double](($values | Measure-Object -Maximum).Maximum)
    $span = $maximum - $minimum
    if ($span -le 0) {
        $span = [Math]::Max(1000.0, $maximum * 0.1)
        $minimum = [Math]::Max(0.0, $minimum - ($span / 2.0))
        $maximum = $minimum + $span
    }
    else {
        $padding = $span * 0.12
        $minimum = [Math]::Max(0.0, $minimum - $padding)
        $maximum += $padding
    }

    $gridBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#E5E7EB')
    foreach ($fraction in @(0.0, 0.5, 1.0)) {
        $y = $bottom - (($bottom - $top) * $fraction)
        $gridLine = New-Object Windows.Shapes.Line
        $gridLine.X1 = $left
        $gridLine.X2 = $right
        $gridLine.Y1 = $y
        $gridLine.Y2 = $y
        $gridLine.Stroke = $gridBrush
        $gridLine.StrokeThickness = 1
        [void]$canvas.Children.Add($gridLine)
        $axisValue = $minimum + (($maximum - $minimum) * $fraction)
        Add-TrendText -Text ('{0:F0}s' -f ($axisValue / 1000.0)) -X 0 -Y ($y - 8) -Width 52
    }

    $series = @(
        [pscustomobject]@{ Name = 'BootDurationMs'; Color = '#2563EB'; Thickness = 3.0 }
        [pscustomobject]@{ Name = 'MainPathBootDurationMs'; Color = '#7C3AED'; Thickness = 2.0 }
        [pscustomobject]@{ Name = 'PostBootDurationMs'; Color = '#059669'; Thickness = 2.0 }
    )
    foreach ($item in $series) {
        $line = New-Object Windows.Shapes.Polyline
        $line.Stroke = [Windows.Media.BrushConverter]::new().ConvertFromString($item.Color)
        $line.StrokeThickness = $item.Thickness
        $points = New-Object Windows.Media.PointCollection
        for ($index = 0; $index -lt $TrendRecords.Count; $index++) {
            $x = if ($TrendRecords.Count -eq 1) {
                ($left + $right) / 2.0
            }
            else {
                $left + (($right - $left) * $index / ($TrendRecords.Count - 1))
            }
            $value = [double]$TrendRecords[$index].$($item.Name)
            $y = $bottom - (($value - $minimum) / ($maximum - $minimum) * ($bottom - $top))
            [void]$points.Add([Windows.Point]::new($x, $y))
        }
        $line.Points = $points
        [void]$canvas.Children.Add($line)
    }

    $oldestLabel = ([DateTimeOffset]$TrendRecords[0].BootStartTimeUtc).ToLocalTime().ToString('yyyy-MM-dd')
    $newestLabel = ([DateTimeOffset]$TrendRecords[-1].BootStartTimeUtc).ToLocalTime().ToString('yyyy-MM-dd')
    Add-TrendText -Text $oldestLabel -X $left -Y 184 -Width 100
    Add-TrendText -Text $newestLabel -X ($right - 100) -Y 184 -Width 100
}

function Update-BootHistoryView {
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

    $trend = $report.Trend
    if ($null -ne $trend) {
        $median = Format-Duration ([int]$trend.MedianBootDurationMs)
        $medianDelta = '{0}{1:F1} s' -f $(if ($trend.ChangeFromMedianMs -gt 0) { '+' } else { '' }), ($trend.ChangeFromMedianMs / 1000.0)
        $comparison = if ($null -eq $trend.ChangeFromPreviousBootMs) {
            '只有 1 条样本，暂无相邻启动对比'
        }
        else {
            $previousDelta = '{0}{1:F1} s' -f $(if ($trend.ChangeFromPreviousBootMs -gt 0) { '+' } else { '' }), ($trend.ChangeFromPreviousBootMs / 1000.0)
            '最近一次比前一次 {0}' -f $previousDelta
        }
        $controls.TrendSummaryText.Text = '最近 {0} 次完整启动 · 中位数 {1} · 最近一次比中位数 {2}（正值表示耗时更长） · {3}' -f `
            $trend.SampleCount, $median, $medianDelta, $comparison
        Update-BootTrendChart -TrendRecords @($trend.Records)
    }
    else {
        $controls.TrendSummaryText.Text = '没有可用于趋势展示的完整实测启动记录。'
        $controls.TrendChartCanvas.Children.Clear()
    }

    $diagnostics = $report.Diagnostics
    if ($null -ne $diagnostics) {
        $latestStateText = switch ($diagnostics.LatestWindowsDegradationState) {
            'Flagged' { '最近一次：Windows 标记了启动退化' }
            'NotFlagged' { '最近一次：Windows 未设置启动退化标记' }
            default { '最近一次：Windows 标记未知' }
        }
        $latestDate = ([DateTimeOffset]$diagnostics.LatestBootStartTimeUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        $controls.DiagnosticSummaryText.Text = '最近 {0} 次完整启动：Windows 标记 {1} 次退化、{2} 次未标记、{3} 次未知。{4}（{5}，Event 100 #{6}）' -f `
            $diagnostics.SampleCount,
            $diagnostics.WindowsFlaggedBootCount,
            $diagnostics.WindowsNotFlaggedBootCount,
            $diagnostics.WindowsFlagUnknownBootCount,
            $latestStateText,
            $latestDate,
            $diagnostics.LatestDiagnosticsEventRecordId
    }
    else {
        $controls.DiagnosticSummaryText.Text = '没有可用于诊断观察的完整实测启动记录。'
    }

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
}

function Apply-StartupItemsFilter {
    $query = $controls.StartupSearchTextBox.Text.Trim()
    $selectedSource = [string]$controls.StartupSourceFilterComboBox.SelectedItem.Content
    $visibleRows = @(
        foreach ($row in $script:StartupItemRows) {
            if ($selectedSource -ne '全部来源' -and $row.Source -ne $selectedSource) {
                continue
            }

            $searchableText = '{0} {1} {2} {3} {4} {5} {6} {7} {8}' -f `
                $row.Name,
                $row.ServiceName,
                $row.Source,
                $row.Scope,
                $row.Executable,
                $row.Publisher,
                $row.Resolution,
                $row.Enabled,
                $row.ServiceStartName

            if (-not [string]::IsNullOrWhiteSpace($query) -and
                $searchableText.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                continue
            }

            $row
        }
    )

    $controls.StartupItemsDataGrid.ItemsSource = $visibleRows
    $controls.StartupItemCountText.Text = '{0} of {1} configured startup items' -f `
        $visibleRows.Count,
        $script:StartupItemRows.Count
}

function Update-StartupItemsView {
    $items = @(Get-BootLensStartupItem)
    $script:StartupItems = @($items)
    $registryCount = @($items | Where-Object Source -eq 'RegistryRun').Count
    $folderCount = @($items | Where-Object Source -eq 'StartupFolder').Count
    $taskCount = @($items | Where-Object Source -eq 'ScheduledTask').Count
    $serviceCount = @($items | Where-Object Source -eq 'WindowsService').Count
    $unresolvedCount = @($items | Where-Object CommandParseStatus -eq 'Unresolved').Count

    $controls.StartupTotalValue.Text = [string]$items.Count
    $controls.RegistryStartupCountValue.Text = [string]$registryCount
    $controls.FolderStartupCountValue.Text = [string]$folderCount
    $controls.TaskStartupCountValue.Text = [string]$taskCount
    $controls.ServiceStartupCountValue.Text = [string]$serviceCount
    $controls.UnresolvedStartupCountValue.Text = [string]$unresolvedCount
    $script:StartupItemRows = @(
        foreach ($item in $items) {
            [pscustomobject]@{
                Name       = $item.Name
                ServiceName = $item.ServiceName
                ServiceStartName = $item.ServiceStartName
                Source     = switch ($item.Source) {
                    'RegistryRun' { 'Registry Run' }
                    'StartupFolder' { 'Startup Folder' }
                    'ScheduledTask' { 'Scheduled Task' }
                    'WindowsService' { 'Windows Service' }
                }
                Scope      = if ($item.Source -eq 'ScheduledTask') {
                    switch ($item.TaskLogonAudience) {
                        'AnyUser' { 'Any user' }
                        'SpecificUser' { 'Specific user' }
                        'Mixed' { 'Mixed users' }
                        default { 'Machine task' }
                    }
                }
                elseif ($item.Scope -eq 'CurrentUser') {
                    'Current user'
                }
                else {
                    'All users'
                }
                Executable = switch ($item.CommandParseStatus) {
                    'Resolved' { $item.ExecutablePath }
                    'NotApplicable' { 'COM handler' }
                    'MultipleTargets' { 'Multiple actions' }
                    default { 'Unknown' }
                }
                Publisher  = if ([string]::IsNullOrWhiteSpace([string]$item.Publisher)) {
                    'Unknown'
                }
                else {
                    $item.Publisher
                }
                Resolution = $item.CommandParseStatus
                Enabled    = if ($item.Source -eq 'WindowsService') {
                    if ($item.ServiceDelayedAutoStart) { 'Auto (Delayed)' } else { 'Auto' }
                }
                else {
                    $item.EnabledState
                }
            }
        }
    )

    Apply-StartupItemsFilter
}

function Update-ProcessTimelineView {
    $report = Get-BootLensProcessTimeline
    $controls.ProcessTotalValue.Text = [string]$report.ProcessCount
    $controls.ProcessTimestampedValue.Text = [string]$report.TimestampedCount
    $controls.ProcessUnavailableValue.Text = [string]$report.UnavailableCount
    $controls.ProcessNegativeOffsetValue.Text = [string]$report.NegativeOffsetCount
    $controls.ProcessSnapshotText.Text = 'Boot {0} · Snapshot {1}' -f `
        $report.BootStartTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss'),
        $report.SnapshotTimeUtc.ToLocalTime().ToString('HH:mm:ss')

    $controls.ProcessTimelineDataGrid.ItemsSource = @(
        foreach ($process in $report.Processes) {
            [pscustomobject]@{
                Name = $process.Name
                ProcessId = $process.ProcessId
                ParentProcessId = if ($null -eq $process.ParentProcessId) { 'Unknown' } else { $process.ParentProcessId }
                Started = if ($null -eq $process.CreationTimeUtc) {
                    'Unknown'
                }
                else {
                    $process.CreationTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')
                }
                BootOffset = if ($null -eq $process.BootOffsetMs) {
                    'Unknown'
                }
                else {
                    '{0:+0.000;-0.000;0.000} s' -f ($process.BootOffsetMs / 1000.0)
                }
                ExecutablePath = if ([string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
                    'Unknown'
                }
                else {
                    $process.ExecutablePath
                }
            }
        }
    )

    $script:ProcessTimelineLoaded = $true
}

function Update-DegradationView {
    $selectedCount = [int]$controls.CountComboBox.SelectedItem.Content
    $scanCount = [Math]::Max(100, $selectedCount * 5)
    $controls.DegradationListStatusText.Text = 'Reading Windows Event 101...'
    $report = Get-BootLensDegradationReport `
        -Count $selectedCount `
        -ScanEvents $scanCount `
        -BootCount 100 `
        -BootScanEvents 1000 `
        -StartupItems $script:StartupItems

    $controls.DegradationEventCountValue.Text = [string]$report.EventCount
    $controls.DegradationMatchedBootCountValue.Text = [string]$report.MatchedBootCount
    $controls.DegradationExactPathCountValue.Text = [string]$report.ExactPathCount
    $controls.DegradationDataGrid.ItemsSource = @(
        foreach ($record in $report.Records) {
            $targetName = if ([string]::IsNullOrWhiteSpace([string]$record.Name)) {
                'Unknown'
            }
            else {
                [string]$record.Name
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$record.FriendlyName)) {
                $targetName = '{0} - {1}' -f $targetName, $record.FriendlyName
            }

            $matchLabel = switch ($record.TargetMatchLevel) {
                'ExactPath' { 'Exact path (current config)' }
                'FamilyCandidate' { 'App family candidate' }
                'GenericHost' { 'Generic host' }
                'Ambiguous' { 'Ambiguous' }
                default { 'Unmatched' }
            }
            $bootLabel = switch ($record.BootAssociationStatus) {
                'Matched' { 'Matched - Event 100 #{0}' -f $record.BootRecordId }
                'Ambiguous' { 'Duplicate anchor' }
                default { 'Unmatched' }
            }
            $matchDetail = if ($record.StartupItemMatches.Count -gt 0) {
                @($record.StartupItemMatches | ForEach-Object {
                    '{0} ({1})' -f $_.Name, $_.Source
                }) -join '; '
            }
            else {
                $record.TargetMatchReason
            }

            [pscustomobject]@{
                BootStart = if ($null -eq $record.StartTimeUtc) {
                    'Unknown'
                }
                else {
                    $record.StartTimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
                }
                EventTime = $record.TimeCreatedUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')
                Target = $targetName
                BootAssociation = $bootLabel
                TargetMatch = $matchLabel
                MatchDetails = $matchDetail
                TotalTime = if ($null -eq $record.TotalTimeMs) { 'Unknown' } else { [string]$record.TotalTimeMs }
                DegradationTime = if ($null -eq $record.DegradationTimeMs) { 'Unknown' } else { [string]$record.DegradationTimeMs }
                Path = if ([string]::IsNullOrWhiteSpace([string]$record.Path)) { 'Unknown' } else { $record.Path }
                EventRecordId = $record.EventRecordId
            }
        }
    )
    $controls.DegradationListStatusText.Text = 'Showing {0} events' -f $report.EventCount
    $script:DegradationLoaded = $true
}

function Update-BootLensView {
    Set-LoadingState -IsLoading $true
    $controls.ErrorBorder.Visibility = [Windows.Visibility]::Collapsed
    $controls.FooterStatusText.Text = 'Reading Windows data...'
    $errors = New-Object 'System.Collections.Generic.List[string]'

    try {
        try {
            Update-BootHistoryView
        }
        catch {
            $message = $_.Exception.Message

            if ($message -match 'Administrator|unauthorized|access is denied') {
                $message = @(
                    'Administrator access is required to read the boot performance log.'
                    'Open the PowerShell (AD) profile in Windows Terminal and run BootLens again.'
                ) -join [Environment]::NewLine
            }

            $errors.Add($message)
        }

        try {
            Update-StartupItemsView
        }
        catch {
            $errors.Add("Startup item discovery failed: $($_.Exception.Message)")
        }

        if ($script:ProcessTimelineLoaded -or
            $controls.MainTabControl.SelectedItem -eq $controls.ProcessTimelineTab) {
            try {
                Update-ProcessTimelineView
            }
            catch {
                $errors.Add("Process timeline discovery failed: $($_.Exception.Message)")
            }
        }

        if ($script:DegradationLoaded -or
            $controls.MainTabControl.SelectedItem -eq $controls.DegradationTab) {
            try {
                Update-DegradationView
            }
            catch {
                $controls.DegradationListStatusText.Text = 'Event 101 unavailable'
                $errors.Add("Startup degradation discovery failed: $($_.Exception.Message)")
            }
        }

        if ($errors.Count -gt 0) {
            Show-ErrorMessage -Message ($errors -join ([Environment]::NewLine + [Environment]::NewLine))
            $controls.FooterStatusText.Text = 'Updated with errors {0:HH:mm:ss}' -f (Get-Date)
        }
        else {
            $controls.FooterStatusText.Text = 'Updated {0:HH:mm:ss}' -f (Get-Date)
        }
    }
    finally {
        Set-LoadingState -IsLoading $false
    }
}

Set-SelectedCount -Value $Count
$controls.RefreshButton.Add_Click({ Update-BootLensView })
$controls.StartupSearchTextBox.Add_TextChanged({ Apply-StartupItemsFilter })
$controls.StartupSourceFilterComboBox.Add_SelectionChanged({ Apply-StartupItemsFilter })
$controls.MainTabControl.Add_SelectionChanged({
    if ($_.Source -ne $controls.MainTabControl) {
        return
    }

    $isProcessTimelineTab = $controls.MainTabControl.SelectedItem -eq $controls.ProcessTimelineTab
    $controls.CountLabelText.Visibility = if ($isProcessTimelineTab) {
        [Windows.Visibility]::Collapsed
    }
    else {
        [Windows.Visibility]::Visible
    }
    $controls.CountComboBox.Visibility = if ($isProcessTimelineTab) {
        [Windows.Visibility]::Collapsed
    }
    else {
        [Windows.Visibility]::Visible
    }

    if ($isProcessTimelineTab -and -not $script:ProcessTimelineLoaded) {
        $controls.ErrorBorder.Visibility = [Windows.Visibility]::Collapsed
        $controls.FooterStatusText.Text = 'Reading current process snapshot...'
        Set-LoadingState -IsLoading $true
        try {
            Update-ProcessTimelineView
            $controls.FooterStatusText.Text = 'Updated {0:HH:mm:ss}' -f (Get-Date)
        }
        catch {
            Show-ErrorMessage -Message $_.Exception.Message
            $controls.FooterStatusText.Text = 'Process timeline unavailable {0:HH:mm:ss}' -f (Get-Date)
        }
        finally {
            Set-LoadingState -IsLoading $false
        }
    }

    $isDegradationTab = $controls.MainTabControl.SelectedItem -eq $controls.DegradationTab
    if ($isDegradationTab -and -not $script:DegradationLoaded) {
        $controls.ErrorBorder.Visibility = [Windows.Visibility]::Collapsed
        Set-LoadingState -IsLoading $true
        try {
            Update-DegradationView
            $controls.FooterStatusText.Text = 'Updated {0:HH:mm:ss}' -f (Get-Date)
        }
        catch {
            $controls.DegradationListStatusText.Text = 'Event 101 unavailable'
            Show-ErrorMessage -Message $_.Exception.Message
            $controls.FooterStatusText.Text = 'Degradation unavailable {0:HH:mm:ss}' -f (Get-Date)
        }
        finally {
            Set-LoadingState -IsLoading $false
        }
    }
})
$window.Add_ContentRendered({ Update-BootLensView })

$null = $window.ShowDialog()
