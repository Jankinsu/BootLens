Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RegistryRunKeyPath = 'Software\Microsoft\Windows\CurrentVersion\Run'

function Test-LocalAbsolutePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return [bool]($Path -match '^[A-Za-z]:\\')
}

function Get-FilePublisher {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $publisher = [string]$item.VersionInfo.CompanyName

        if (-not [string]::IsNullOrWhiteSpace($publisher)) {
            return $publisher.Trim()
        }
    }
    catch {
        Write-Verbose "Could not read publisher from '$Path': $($_.Exception.Message)"
    }

    return $null
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-ScheduledTaskObjectType {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $cimClass = Get-OptionalPropertyValue -InputObject $InputObject -Name 'CimClass'
    $cimClassName = Get-OptionalPropertyValue -InputObject $cimClass -Name 'CimClassName'

    if (-not [string]::IsNullOrWhiteSpace([string]$cimClassName)) {
        return [string]$cimClassName
    }

    $type = Get-OptionalPropertyValue -InputObject $InputObject -Name 'Type'

    if (-not [string]::IsNullOrWhiteSpace([string]$type)) {
        return [string]$type
    }

    return 'Unknown'
}

function ConvertTo-StartupCommandInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandLine,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'ExpandString')]
        [string]$ValueKind
    )

    $expandedCommandLine = if ($ValueKind -eq 'ExpandString') {
        [Environment]::ExpandEnvironmentVariables($CommandLine)
    }
    else {
        $null
    }
    $commandToParse = if ($null -ne $expandedCommandLine) {
        $expandedCommandLine
    }
    else {
        $CommandLine
    }
    $commandToParse = $commandToParse.Trim()
    $executablePath = $null
    $arguments = $null
    $parseStatus = 'Unresolved'

    $quotedMatch = [regex]::Match($commandToParse, '^"([^"]+)"(?:\s+(.*))?$')

    if ($quotedMatch.Success) {
        $executablePath = $quotedMatch.Groups[1].Value

        if ($quotedMatch.Groups[2].Success -and
            -not [string]::IsNullOrWhiteSpace($quotedMatch.Groups[2].Value)) {
            $arguments = $quotedMatch.Groups[2].Value.Trim()
        }

        $parseStatus = 'Resolved'
    }
    elseif ((Test-LocalAbsolutePath -Path $commandToParse) -and
        (Test-Path -LiteralPath $commandToParse -PathType Leaf)) {
        $executablePath = $commandToParse
        $parseStatus = 'Resolved'
    }
    else {
        $extensionMatches = @(
            [regex]::Matches(
                $commandToParse,
                '(?i)\.(?:exe|com|bat|cmd)(?=\s|$)'
            )
        )
        $existingCandidates = @(
            foreach ($match in $extensionMatches) {
                $candidate = $commandToParse.Substring(0, $match.Index + $match.Length)

                if ((Test-LocalAbsolutePath -Path $candidate) -and
                    (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                    [pscustomobject]@{
                        Path      = $candidate
                        EndOffset = $match.Index + $match.Length
                    }
                }
            }
        )

        if ($existingCandidates.Count -eq 1) {
            $executablePath = $existingCandidates[0].Path
            $remaining = $commandToParse.Substring($existingCandidates[0].EndOffset).Trim()

            if (-not [string]::IsNullOrWhiteSpace($remaining)) {
                $arguments = $remaining
            }

            $parseStatus = 'Resolved'
        }
    }

    $executableExists = if ($parseStatus -eq 'Resolved' -and
        (Test-LocalAbsolutePath -Path $executablePath)) {
        [bool](Test-Path -LiteralPath $executablePath -PathType Leaf)
    }
    else {
        $null
    }
    $publisher = if ($executableExists -eq $true) {
        Get-FilePublisher -Path $executablePath
    }
    else {
        $null
    }

    [pscustomobject][ordered]@{
        CommandLineExpanded = $expandedCommandLine
        ExecutablePath      = $executablePath
        Arguments           = $arguments
        CommandParseStatus  = $parseStatus
        ExecutableExists    = $executableExists
        Publisher           = $publisher
    }
}

function ConvertTo-RegistryRunStartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$CommandLineRaw,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'ExpandString')]
        [string]$RegistryValueKind,

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateSet('Shared', 'Registry64', 'Registry32')]
        [string]$RegistryView
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or
        [string]::IsNullOrWhiteSpace($CommandLineRaw)) {
        return
    }

    $command = ConvertTo-StartupCommandInfo `
        -CommandLine $CommandLineRaw `
        -ValueKind $RegistryValueKind
    $sourceIdentity = 'RegistryRun|{0}|{1}|{2}|{3}' -f
        $Scope,
        $RegistryView,
        $script:RegistryRunKeyPath,
        [Uri]::EscapeDataString($Name)

    [pscustomobject][ordered]@{
        SchemaVersion       = 3
        Name                = $Name
        Source              = 'RegistryRun'
        Trigger             = 'UserLogon'
        Scope               = $Scope
        CommandLineRaw      = $CommandLineRaw
        CommandLineExpanded = $command.CommandLineExpanded
        ExecutablePath      = $command.ExecutablePath
        Arguments           = $command.Arguments
        CommandParseStatus  = $command.CommandParseStatus
        ExecutableExists    = $command.ExecutableExists
        Publisher           = $command.Publisher
        EnabledState        = 'Unknown'
        RegistryHive        = $Scope
        RegistryView        = $RegistryView
        RegistryKeyPath     = $script:RegistryRunKeyPath
        RegistryValueName   = $Name
        RegistryValueKind   = $RegistryValueKind
        StartupFolderKind   = $null
        StartupFolderPath   = $null
        StartupEntryPath    = $null
        StartupEntryType    = $null
        ShortcutTargetPath  = $null
        ShortcutArguments   = $null
        ShortcutWorkingPath = $null
        TaskPath            = $null
        TaskName            = $null
        TaskState           = $null
        TaskEnabled         = $null
        TaskHidden          = $null
        TaskAuthor          = $null
        TaskDescription     = $null
        TaskPrincipalUserId = $null
        TaskPrincipalLogonType = $null
        TaskPrincipalRunLevel  = $null
        TaskLogonAudience   = $null
        TaskLogonTriggers   = $null
        TaskActions         = $null
        SourceIdentity      = $sourceIdentity
    }
}

function Get-ShortcutInfo {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $shell = $null
    $shortcut = $null

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)

        [pscustomobject]@{
            TargetPath       = [string]$shortcut.TargetPath
            Arguments        = [string]$shortcut.Arguments
            WorkingDirectory = [string]$shortcut.WorkingDirectory
        }
    }
    finally {
        if ($null -ne $shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) {
            $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        }

        if ($null -ne $shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
            $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

function ConvertTo-StartupFolderStartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EntryPath,

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateSet('UserStartup', 'CommonStartup')]
        [string]$StartupFolderKind,

        [Parameter(Mandatory)]
        [string]$StartupFolderPath
    )

    $entry = Get-Item -LiteralPath $EntryPath -Force -ErrorAction Stop

    if ($entry.PSIsContainer -or $entry.Name -ieq 'desktop.ini') {
        return
    }

    $entryType = if ($entry.Extension -ieq '.lnk') {
        'Shortcut'
    }
    else {
        'File'
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($entry.Name)
    $executablePath = $null
    $arguments = $null
    $parseStatus = 'Unresolved'
    $executableExists = $null
    $publisher = $null
    $shortcutTargetPath = $null
    $shortcutArguments = $null
    $shortcutWorkingPath = $null

    if ($entryType -eq 'Shortcut') {
        try {
            $shortcut = Get-ShortcutInfo -Path $entry.FullName
            $shortcutTargetPath = $shortcut.TargetPath
            $shortcutArguments = if ([string]::IsNullOrWhiteSpace($shortcut.Arguments)) {
                $null
            }
            else {
                $shortcut.Arguments
            }
            $shortcutWorkingPath = if ([string]::IsNullOrWhiteSpace($shortcut.WorkingDirectory)) {
                $null
            }
            else {
                $shortcut.WorkingDirectory
            }

            if (-not [string]::IsNullOrWhiteSpace($shortcutTargetPath)) {
                $executablePath = $shortcutTargetPath
                $arguments = $shortcutArguments
                $parseStatus = 'Resolved'
            }
        }
        catch {
            Write-Verbose "Could not resolve shortcut '$($entry.FullName)': $($_.Exception.Message)"
        }
    }
    else {
        $executablePath = $entry.FullName
        $parseStatus = 'Resolved'
    }

    if ($parseStatus -eq 'Resolved' -and
        (Test-LocalAbsolutePath -Path $executablePath)) {
        $executableExists = [bool](Test-Path -LiteralPath $executablePath -PathType Leaf)

        if ($executableExists) {
            $publisher = Get-FilePublisher -Path $executablePath
        }
    }

    $sourceIdentity = 'StartupFolder|{0}|{1}' -f
        $Scope,
        [Uri]::EscapeDataString($entry.FullName)

    [pscustomobject][ordered]@{
        SchemaVersion       = 3
        Name                = $name
        Source              = 'StartupFolder'
        Trigger             = 'UserLogon'
        Scope               = $Scope
        CommandLineRaw      = $null
        CommandLineExpanded = $null
        ExecutablePath      = $executablePath
        Arguments           = $arguments
        CommandParseStatus  = $parseStatus
        ExecutableExists    = $executableExists
        Publisher           = $publisher
        EnabledState        = 'Unknown'
        RegistryHive        = $null
        RegistryView        = $null
        RegistryKeyPath     = $null
        RegistryValueName   = $null
        RegistryValueKind   = $null
        StartupFolderKind   = $StartupFolderKind
        StartupFolderPath   = $StartupFolderPath
        StartupEntryPath    = $entry.FullName
        StartupEntryType    = $entryType
        ShortcutTargetPath  = $shortcutTargetPath
        ShortcutArguments   = $shortcutArguments
        ShortcutWorkingPath = $shortcutWorkingPath
        TaskPath            = $null
        TaskName            = $null
        TaskState           = $null
        TaskEnabled         = $null
        TaskHidden          = $null
        TaskAuthor          = $null
        TaskDescription     = $null
        TaskPrincipalUserId = $null
        TaskPrincipalLogonType = $null
        TaskPrincipalRunLevel  = $null
        TaskLogonAudience   = $null
        TaskLogonTriggers   = $null
        TaskActions         = $null
        SourceIdentity      = $sourceIdentity
    }
}

function ConvertTo-ScheduledTaskStartupItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Task
    )

    $taskPath = [string](Get-OptionalPropertyValue -InputObject $Task -Name 'TaskPath')
    $taskName = [string](Get-OptionalPropertyValue -InputObject $Task -Name 'TaskName')

    if ([string]::IsNullOrWhiteSpace($taskPath) -or
        [string]::IsNullOrWhiteSpace($taskName)) {
        return
    }

    $logonTriggers = @(
        foreach ($trigger in @(Get-OptionalPropertyValue -InputObject $Task -Name 'Triggers')) {
            if ((Get-ScheduledTaskObjectType -InputObject $trigger) -ne 'MSFT_TaskLogonTrigger') {
                continue
            }

            [pscustomobject][ordered]@{
                Enabled = Get-OptionalPropertyValue -InputObject $trigger -Name 'Enabled'
                UserId  = Get-OptionalPropertyValue -InputObject $trigger -Name 'UserId'
                Delay   = Get-OptionalPropertyValue -InputObject $trigger -Name 'Delay'
            }
        }
    )

    if ($logonTriggers.Count -eq 0) {
        return
    }

    $actions = @(
        foreach ($action in @(Get-OptionalPropertyValue -InputObject $Task -Name 'Actions')) {
            [pscustomobject][ordered]@{
                Type             = Get-ScheduledTaskObjectType -InputObject $action
                Execute          = Get-OptionalPropertyValue -InputObject $action -Name 'Execute'
                Arguments        = Get-OptionalPropertyValue -InputObject $action -Name 'Arguments'
                WorkingDirectory = Get-OptionalPropertyValue -InputObject $action -Name 'WorkingDirectory'
                ClassId          = Get-OptionalPropertyValue -InputObject $action -Name 'ClassId'
                Data             = Get-OptionalPropertyValue -InputObject $action -Name 'Data'
            }
        }
    )
    $settings = Get-OptionalPropertyValue -InputObject $Task -Name 'Settings'
    $principal = Get-OptionalPropertyValue -InputObject $Task -Name 'Principal'
    $taskEnabled = Get-OptionalPropertyValue -InputObject $settings -Name 'Enabled'
    $enabledTriggerCount = @($logonTriggers | Where-Object Enabled -eq $true).Count
    $enabledState = if ($taskEnabled -eq $false -or $enabledTriggerCount -eq 0) {
        'Disabled'
    }
    elseif ($taskEnabled -eq $true) {
        'Enabled'
    }
    else {
        'Unknown'
    }
    $userIds = @(
        $logonTriggers |
            ForEach-Object { [string]$_.UserId } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $emptyUserIdCount = @(
        $logonTriggers |
            Where-Object { [string]::IsNullOrWhiteSpace([string]$_.UserId) }
    ).Count
    $logonAudience = if ($userIds.Count -eq 0) {
        'AnyUser'
    }
    elseif ($emptyUserIdCount -gt 0) {
        'Mixed'
    }
    else {
        'SpecificUser'
    }
    $executablePath = $null
    $arguments = $null
    $commandParseStatus = if ($actions.Count -eq 1 -and
        $actions[0].Type -eq 'MSFT_TaskExecAction') {
        $execute = [string]$actions[0].Execute

        if ([string]::IsNullOrWhiteSpace($execute)) {
            'Unresolved'
        }
        else {
            $expandedExecute = [Environment]::ExpandEnvironmentVariables($execute.Trim())

            if ($expandedExecute.Length -ge 2 -and
                $expandedExecute[0] -eq '"' -and
                $expandedExecute[$expandedExecute.Length - 1] -eq '"') {
                $expandedExecute = $expandedExecute.Substring(1, $expandedExecute.Length - 2)
            }

            $executablePath = $expandedExecute
            $argumentsValue = [string]$actions[0].Arguments
            $arguments = if ([string]::IsNullOrWhiteSpace($argumentsValue)) {
                $null
            }
            else {
                $argumentsValue
            }
            'Resolved'
        }
    }
    elseif ($actions.Count -gt 1) {
        'MultipleTargets'
    }
    else {
        'NotApplicable'
    }
    $executableExists = if ($commandParseStatus -eq 'Resolved' -and
        (Test-LocalAbsolutePath -Path $executablePath)) {
        [bool](Test-Path -LiteralPath $executablePath -PathType Leaf)
    }
    else {
        $null
    }
    $publisher = if ($executableExists -eq $true) {
        Get-FilePublisher -Path $executablePath
    }
    else {
        $null
    }
    $sourceIdentity = 'ScheduledTask|{0}|{1}' -f
        [Uri]::EscapeDataString($taskPath),
        [Uri]::EscapeDataString($taskName)

    [pscustomobject][ordered]@{
        SchemaVersion       = 3
        Name                = $taskName
        Source              = 'ScheduledTask'
        Trigger             = 'UserLogon'
        Scope               = 'LocalMachine'
        CommandLineRaw      = $null
        CommandLineExpanded = $null
        ExecutablePath      = $executablePath
        Arguments           = $arguments
        CommandParseStatus  = $commandParseStatus
        ExecutableExists    = $executableExists
        Publisher           = $publisher
        EnabledState        = $enabledState
        RegistryHive        = $null
        RegistryView        = $null
        RegistryKeyPath     = $null
        RegistryValueName   = $null
        RegistryValueKind   = $null
        StartupFolderKind   = $null
        StartupFolderPath   = $null
        StartupEntryPath    = $null
        StartupEntryType    = $null
        ShortcutTargetPath  = $null
        ShortcutArguments   = $null
        ShortcutWorkingPath = $null
        TaskPath            = $taskPath
        TaskName            = $taskName
        TaskState           = [string](Get-OptionalPropertyValue -InputObject $Task -Name 'State')
        TaskEnabled         = $taskEnabled
        TaskHidden          = Get-OptionalPropertyValue -InputObject $settings -Name 'Hidden'
        TaskAuthor          = Get-OptionalPropertyValue -InputObject $Task -Name 'Author'
        TaskDescription     = Get-OptionalPropertyValue -InputObject $Task -Name 'Description'
        TaskPrincipalUserId = Get-OptionalPropertyValue -InputObject $principal -Name 'UserId'
        TaskPrincipalLogonType = Get-OptionalPropertyValue -InputObject $principal -Name 'LogonType'
        TaskPrincipalRunLevel  = Get-OptionalPropertyValue -InputObject $principal -Name 'RunLevel'
        TaskLogonAudience   = $logonAudience
        TaskLogonTriggers   = $logonTriggers
        TaskActions         = $actions
        SourceIdentity      = $sourceIdentity
    }
}

function Read-RegistryRunKey {
    param(
        [Parameter(Mandatory)]
        [Microsoft.Win32.RegistryHive]$Hive,

        [Parameter(Mandatory)]
        [Microsoft.Win32.RegistryView]$View,

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateSet('Shared', 'Registry64', 'Registry32')]
        [string]$ViewName
    )

    $baseKey = $null
    $runKey = $null

    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $runKey = $baseKey.OpenSubKey($script:RegistryRunKeyPath, $false)

        if ($null -eq $runKey) {
            Write-Verbose "Registry Run key does not exist for $Scope / $ViewName."
            return
        }

        foreach ($name in @($runKey.GetValueNames() | Sort-Object)) {
            if ([string]::IsNullOrWhiteSpace($name)) {
                Write-Verbose "Excluded an unnamed Registry Run value from $Scope / $ViewName."
                continue
            }

            try {
                $valueKind = $runKey.GetValueKind($name).ToString()

                if ($valueKind -notin @('String', 'ExpandString')) {
                    Write-Verbose "Excluded Registry Run value '$name': unsupported kind $valueKind."
                    continue
                }

                $rawValue = [string]$runKey.GetValue(
                    $name,
                    $null,
                    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                )

                if ([string]::IsNullOrWhiteSpace($rawValue)) {
                    Write-Verbose "Excluded Registry Run value '$name': empty command line."
                    continue
                }

                ConvertTo-RegistryRunStartupItem `
                    -Name $name `
                    -CommandLineRaw $rawValue `
                    -RegistryValueKind $valueKind `
                    -Scope $Scope `
                    -RegistryView $ViewName
            }
            catch {
                Write-Verbose "Excluded Registry Run value '$name': $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Could not read Registry Run items for $Scope / ${ViewName}: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $runKey) {
            $runKey.Dispose()
        }

        if ($null -ne $baseKey) {
            $baseKey.Dispose()
        }
    }
}

function Get-RegistryRunStartupItem {
    [CmdletBinding()]
    param()

    $items = @(
        Read-RegistryRunKey `
            -Hive ([Microsoft.Win32.RegistryHive]::CurrentUser) `
            -View ([Microsoft.Win32.RegistryView]::Default) `
            -Scope 'CurrentUser' `
            -ViewName 'Shared'

        if ([Environment]::Is64BitOperatingSystem) {
            Read-RegistryRunKey `
                -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) `
                -View ([Microsoft.Win32.RegistryView]::Registry64) `
                -Scope 'LocalMachine' `
                -ViewName 'Registry64'
            Read-RegistryRunKey `
                -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) `
                -View ([Microsoft.Win32.RegistryView]::Registry32) `
                -Scope 'LocalMachine' `
                -ViewName 'Registry32'
        }
        else {
            Read-RegistryRunKey `
                -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) `
                -View ([Microsoft.Win32.RegistryView]::Default) `
                -Scope 'LocalMachine' `
                -ViewName 'Registry32'
        }
    )

    return @($items | Sort-Object Scope, Name, RegistryView)
}

function Read-StartupFolder {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateSet('UserStartup', 'CommonStartup')]
        [string]$StartupFolderKind
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Verbose "Startup folder does not exist for $Scope / $StartupFolderKind."
        return
    }

    foreach ($entry in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            ConvertTo-StartupFolderStartupItem `
                -EntryPath $entry.FullName `
                -Scope $Scope `
                -StartupFolderKind $StartupFolderKind `
                -StartupFolderPath $Path
        }
        catch {
            Write-Verbose "Excluded Startup Folder entry '$($entry.FullName)': $($_.Exception.Message)"
        }
    }
}

function Get-StartupFolderStartupItem {
    [CmdletBinding()]
    param()

    $items = @(
        Read-StartupFolder `
            -Path ([Environment]::GetFolderPath('Startup')) `
            -Scope 'CurrentUser' `
            -StartupFolderKind 'UserStartup'
        Read-StartupFolder `
            -Path ([Environment]::GetFolderPath('CommonStartup')) `
            -Scope 'LocalMachine' `
            -StartupFolderKind 'CommonStartup'
    )

    return @($items | Sort-Object Scope, Name)
}

function Get-ScheduledTaskStartupItem {
    [CmdletBinding()]
    param()

    try {
        $items = @(
            foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
                try {
                    ConvertTo-ScheduledTaskStartupItem -Task $task
                }
                catch {
                    $taskIdentity = '{0}{1}' -f
                        [string](Get-OptionalPropertyValue -InputObject $task -Name 'TaskPath'),
                        [string](Get-OptionalPropertyValue -InputObject $task -Name 'TaskName')
                    Write-Verbose "Excluded Scheduled Task '$taskIdentity': $($_.Exception.Message)"
                }
            }
        )

        return @($items | Sort-Object TaskPath, TaskName)
    }
    catch {
        Write-Warning "Could not read Scheduled Tasks. Administrator access may be required: $($_.Exception.Message)"
        return @()
    }
}

function Get-BootLensStartupItem {
    [CmdletBinding()]
    param()

    $items = @(
        Get-RegistryRunStartupItem
        Get-StartupFolderStartupItem
        Get-ScheduledTaskStartupItem
    )

    return @($items | Sort-Object Source, Scope, Name)
}

Export-ModuleMember -Function `
    ConvertTo-StartupCommandInfo, `
    ConvertTo-RegistryRunStartupItem, `
    ConvertTo-StartupFolderStartupItem, `
    ConvertTo-ScheduledTaskStartupItem, `
    Get-RegistryRunStartupItem, `
    Get-StartupFolderStartupItem, `
    Get-ScheduledTaskStartupItem, `
    Get-BootLensStartupItem
