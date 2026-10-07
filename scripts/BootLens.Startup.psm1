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
        SchemaVersion       = 1
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

Export-ModuleMember -Function `
    ConvertTo-StartupCommandInfo, `
    ConvertTo-RegistryRunStartupItem, `
    Get-RegistryRunStartupItem
