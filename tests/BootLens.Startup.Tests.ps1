Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\BootLens.Startup.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Expected,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Actual,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected: $Expected; Actual: $Actual"
    }
}

$quoted = ConvertTo-StartupCommandInfo `
    -CommandLine '"C:\Program Files\Example\example.exe" --silent' `
    -ValueKind 'String'
Assert-Equal 'Resolved' $quoted.CommandParseStatus 'A quoted executable should be resolved.'
Assert-Equal 'C:\Program Files\Example\example.exe' $quoted.ExecutablePath 'Quoted path should be preserved.'
Assert-Equal '--silent' $quoted.Arguments 'Quoted command arguments should be preserved.'
Assert-Equal $false $quoted.ExecutableExists 'A missing quoted executable should be reported.'

$network = ConvertTo-StartupCommandInfo `
    -CommandLine '"\\server\share\example.exe" --silent' `
    -ValueKind 'String'
Assert-Equal 'Resolved' $network.CommandParseStatus 'A quoted network path boundary should be resolved.'
Assert-Equal $null $network.ExecutableExists 'A network path should not be probed during discovery.'

$expanded = ConvertTo-StartupCommandInfo `
    -CommandLine '%windir%\system32\SecurityHealthSystray.exe' `
    -ValueKind 'ExpandString'
Assert-Equal 'Resolved' $expanded.CommandParseStatus 'An expanded existing executable should be resolved.'
Assert-Equal $true $expanded.ExecutableExists 'The expanded system executable should exist.'

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BootLens Startup Test ' + [guid]::NewGuid())
$testExecutable = Join-Path $testDirectory 'sample app.exe'

try {
    $null = New-Item -ItemType Directory -Path $testDirectory
    $null = New-Item -ItemType File -Path $testExecutable
    $unquotedCommand = '{0} --background' -f $testExecutable
    $unquoted = ConvertTo-StartupCommandInfo `
        -CommandLine $unquotedCommand `
        -ValueKind 'String'
    Assert-Equal 'Resolved' $unquoted.CommandParseStatus 'An existing unquoted executable should be resolved.'
    Assert-Equal $testExecutable $unquoted.ExecutablePath 'Unquoted path should preserve spaces.'
    Assert-Equal '--background' $unquoted.Arguments 'Unquoted command arguments should be preserved.'
}
finally {
    if (Test-Path -LiteralPath $testExecutable) {
        Remove-Item -LiteralPath $testExecutable -Force
    }

    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Force
    }
}

$unresolved = ConvertTo-StartupCommandInfo `
    -CommandLine 'C:\Missing Program\missing.exe --silent' `
    -ValueKind 'String'
Assert-Equal 'Unresolved' $unresolved.CommandParseStatus 'An ambiguous missing command should remain unresolved.'
Assert-Equal $null $unresolved.ExecutablePath 'An unresolved command should not invent a path.'

$item = ConvertTo-RegistryRunStartupItem `
    -Name 'Example' `
    -CommandLineRaw '"C:\Example\example.exe" --silent' `
    -RegistryValueKind 'String' `
    -Scope 'CurrentUser' `
    -RegistryView 'Shared'
Assert-Equal 3 $item.SchemaVersion 'StartupItem schema version should be three.'
Assert-Equal 'RegistryRun' $item.Source 'StartupItem source should be RegistryRun.'
Assert-Equal 'UserLogon' $item.Trigger 'Registry Run should use the UserLogon trigger.'
Assert-Equal 'Unknown' $item.EnabledState 'Enabled state should not be inferred.'
Assert-Equal `
    'RegistryRun|CurrentUser|Shared|Software\Microsoft\Windows\CurrentVersion\Run|Example' `
    $item.SourceIdentity `
    'Source identity should preserve the registry location.'

$escapedItem = ConvertTo-RegistryRunStartupItem `
    -Name 'Example|Secondary' `
    -CommandLineRaw '"C:\Example\example.exe"' `
    -RegistryValueKind 'String' `
    -Scope 'CurrentUser' `
    -RegistryView 'Shared'
Assert-Equal `
    'RegistryRun|CurrentUser|Shared|Software\Microsoft\Windows\CurrentVersion\Run|Example%7CSecondary' `
    $escapedItem.SourceIdentity `
    'Source identity should escape delimiter characters.'

$folderTestDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BootLens Folder Test ' + [guid]::NewGuid())
$folderTestExecutable = Join-Path $folderTestDirectory 'sample target.exe'
$folderTestShortcut = Join-Path $folderTestDirectory 'Sample Shortcut.lnk'
$folderDesktopIni = Join-Path $folderTestDirectory 'desktop.ini'
$shortcutShell = $null
$shortcutObject = $null

try {
    $null = New-Item -ItemType Directory -Path $folderTestDirectory
    $null = New-Item -ItemType File -Path $folderTestExecutable
    $null = New-Item -ItemType File -Path $folderDesktopIni
    $shortcutShell = New-Object -ComObject WScript.Shell
    $shortcutObject = $shortcutShell.CreateShortcut($folderTestShortcut)
    $shortcutObject.TargetPath = $folderTestExecutable
    $shortcutObject.Arguments = '--background'
    $shortcutObject.WorkingDirectory = $folderTestDirectory
    $shortcutObject.Save()
    $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutObject)
    $shortcutObject = $null
    $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutShell)
    $shortcutShell = $null

    $folderItem = ConvertTo-StartupFolderStartupItem `
        -EntryPath $folderTestShortcut `
        -Scope 'CurrentUser' `
        -StartupFolderKind 'UserStartup' `
        -StartupFolderPath $folderTestDirectory
    Assert-Equal 3 $folderItem.SchemaVersion 'Startup Folder item should use schema version three.'
    Assert-Equal 'StartupFolder' $folderItem.Source 'Startup Folder source should be preserved.'
    Assert-Equal 'Shortcut' $folderItem.StartupEntryType 'A .lnk file should be a shortcut entry.'
    Assert-Equal $folderTestExecutable $folderItem.ExecutablePath 'Shortcut target should be resolved.'
    Assert-Equal '--background' $folderItem.Arguments 'Shortcut arguments should be preserved.'
    Assert-Equal $true $folderItem.ExecutableExists 'Shortcut target existence should be measured.'
    Assert-Equal $null $folderItem.CommandLineRaw 'A shortcut should not fabricate a raw command line.'

    $desktopItem = @(
        ConvertTo-StartupFolderStartupItem `
            -EntryPath $folderDesktopIni `
            -Scope 'CurrentUser' `
            -StartupFolderKind 'UserStartup' `
            -StartupFolderPath $folderTestDirectory
    )
    Assert-Equal 0 $desktopItem.Count 'desktop.ini should be excluded.'
}
finally {
    if ($null -ne $shortcutObject -and [Runtime.InteropServices.Marshal]::IsComObject($shortcutObject)) {
        $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutObject)
    }

    if ($null -ne $shortcutShell -and [Runtime.InteropServices.Marshal]::IsComObject($shortcutShell)) {
        $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutShell)
    }

    foreach ($path in @($folderTestShortcut, $folderDesktopIni, $folderTestExecutable)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    if (Test-Path -LiteralPath $folderTestDirectory) {
        Remove-Item -LiteralPath $folderTestDirectory -Force
    }
}

$execTask = [pscustomobject]@{
    TaskPath   = '\Vendor\'
    TaskName   = 'Example Logon Task'
    State      = 'Ready'
    Author     = 'Example Publisher'
    Description = 'Starts an example application at logon.'
    Settings   = [pscustomobject]@{
        Enabled = $true
        Hidden  = $false
    }
    Principal  = [pscustomobject]@{
        UserId   = 'EXAMPLE\User'
        LogonType = 'Interactive'
        RunLevel  = 'Limited'
    }
    Triggers    = @(
        [pscustomobject]@{
            Type    = 'MSFT_TaskLogonTrigger'
            Enabled = $true
            UserId  = 'EXAMPLE\User'
            Delay   = 'PT10S'
        },
        [pscustomobject]@{
            Type    = 'MSFT_TaskBootTrigger'
            Enabled = $true
        }
    )
    Actions     = @(
        [pscustomobject]@{
            Type             = 'MSFT_TaskExecAction'
            Execute          = '"C:\Program Files\Example\example.exe"'
            Arguments        = '--startup'
            WorkingDirectory = 'C:\Program Files\Example'
        }
    )
}
$taskItem = ConvertTo-ScheduledTaskStartupItem -Task $execTask
Assert-Equal 3 $taskItem.SchemaVersion 'Scheduled Task item should use schema version three.'
Assert-Equal 'ScheduledTask' $taskItem.Source 'Scheduled Task source should be preserved.'
Assert-Equal 'Resolved' $taskItem.CommandParseStatus 'A single Exec action should be resolved.'
Assert-Equal 'C:\Program Files\Example\example.exe' $taskItem.ExecutablePath 'Exec quotes should be removed.'
Assert-Equal '--startup' $taskItem.Arguments 'Exec arguments should remain separate.'
Assert-Equal 'SpecificUser' $taskItem.TaskLogonAudience 'An explicit trigger user should be preserved as audience.'
Assert-Equal 'Enabled' $taskItem.EnabledState 'An enabled task with an enabled logon trigger should be enabled.'
Assert-Equal 1 $taskItem.TaskLogonTriggers.Count 'Only logon triggers should be retained.'
Assert-Equal 1 $taskItem.TaskActions.Count 'All task actions should be retained.'
Assert-Equal `
    'ScheduledTask|%5CVendor%5C|Example%20Logon%20Task' `
    $taskItem.SourceIdentity `
    'Scheduled Task identity should include escaped path and name.'

$comTask = [pscustomobject]@{
    TaskPath  = '\Microsoft\Windows\Example\'
    TaskName  = 'COM Logon Task'
    State     = 'Ready'
    Settings  = [pscustomobject]@{ Enabled = $true; Hidden = $true }
    Principal = [pscustomobject]@{ UserId = ''; LogonType = 'Group'; RunLevel = 'Limited' }
    Triggers   = @(
        [pscustomobject]@{
            Type = 'MSFT_TaskLogonTrigger'; Enabled = $false; UserId = ''; Delay = 'PT1M'
        }
    )
    Actions    = @(
        [pscustomobject]@{
            Type = 'MSFT_TaskComHandlerAction'; ClassId = '{00000000-0000-0000-0000-000000000000}'; Data = 'example'
        }
    )
}
$comItem = ConvertTo-ScheduledTaskStartupItem -Task $comTask
Assert-Equal 'NotApplicable' $comItem.CommandParseStatus 'A COM handler should not fabricate an executable.'
Assert-Equal $null $comItem.ExecutablePath 'A COM handler should not expose a fake executable path.'
Assert-Equal 'Disabled' $comItem.EnabledState 'A task without an enabled logon trigger should be disabled.'
Assert-Equal 'AnyUser' $comItem.TaskLogonAudience 'An empty trigger user should mean any user.'
Assert-Equal `
    '{00000000-0000-0000-0000-000000000000}' `
    $comItem.TaskActions[0].ClassId `
    'COM handler metadata should be retained.'

$nonLogonTask = [pscustomobject]@{
    TaskPath  = '\'
    TaskName  = 'Boot Only Task'
    Settings  = [pscustomobject]@{ Enabled = $true; Hidden = $false }
    Principal = [pscustomobject]@{}
    Triggers   = @([pscustomobject]@{ Type = 'MSFT_TaskBootTrigger'; Enabled = $true })
    Actions    = @()
}
$nonLogonItem = @(ConvertTo-ScheduledTaskStartupItem -Task $nonLogonTask)
Assert-Equal 0 $nonLogonItem.Count 'A task without a logon trigger should be excluded.'

$registryProperties = @($item.PSObject.Properties.Name | Sort-Object) -join '|'
$folderProperties = @($folderItem.PSObject.Properties.Name | Sort-Object) -join '|'
$taskProperties = @($taskItem.PSObject.Properties.Name | Sort-Object) -join '|'
Assert-Equal $registryProperties $folderProperties 'Registry and Startup Folder items should share one schema.'
Assert-Equal $registryProperties $taskProperties 'Registry and Scheduled Task items should share one schema.'

Write-Output 'BootLens startup tests: PASS'
