function Enter-ProfileMutex {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try { $sid = $identity.User.Value } finally { $identity.Dispose() }
    $mutex = [System.Threading.Mutex]::new($false, ('Global\WezTermProfileStart-' + $sid))
    try {
        if (-not $mutex.WaitOne([TimeSpan]::FromSeconds(10))) { throw 'Lock unavailable.' }
        return $mutex
    } catch {
        $exception = $_.Exception
        while ($null -ne $exception) {
            if ($exception -is [System.Threading.AbandonedMutexException]) {
                try { $mutex.ReleaseMutex() } catch { }
                break
            }
            $exception = $exception.InnerException
        }
        $mutex.Dispose()
        throw 'Lock unavailable.'
    }
}

function Exit-ProfileMutex($Mutex) {
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Get-ProfileGuis {
    $processes = @(Get-Process -ErrorAction Stop)
    $guis = @()
    $completed = $false
    try {
        foreach ($process in $processes) {
            if ($process.ProcessName -ieq 'wezterm-gui') {
                if ($process.HasExited) { throw 'Process unavailable.' }
                $handle = $process.Handle
                $start = $process.StartTime
                $path = [System.IO.Path]::GetFullPath($process.MainModule.FileName)
                if ($handle -eq [IntPtr]::Zero) { throw 'Process unavailable.' }
                $guis += [pscustomobject]@{ Process = $process; Id = $process.Id; Path = $path }
            } elseif ($process.ProcessName -match '^wezterm(?:$|-)') {
                throw 'Unexpected WezTerm process.'
            }
        }
        $completed = $true
    } finally {
        foreach ($process in $processes) {
            $keep = $false
            if ($completed) {
                foreach ($gui in $guis) {
                    if ([object]::ReferenceEquals($process, $gui.Process)) { $keep = $true; break }
                }
            }
            if (-not $keep) { $process.Dispose() }
        }
    }
    return $guis
}

function Test-ProfilePath([string] $Path, [string] $Kind) {
    if ($Kind -eq 'Directory') { return [System.IO.Directory]::Exists($Path) }
    return [System.IO.File]::Exists($Path)
}

function Get-ProfileSocket([int] $ProcessId) {
    $profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    return [System.IO.Path]::Combine($profile, '.local', 'share', 'wezterm', "gui-sock-$ProcessId")
}

function Set-ProfileChildEnvironment($Environment, [string] $Socket, $StartupProfiles) {
    foreach ($key in @($Environment.Keys)) {
        if ($key -in @('WEZTERM_PANE', 'WEZTERM_UNIX_SOCKET', 'WEZTERM_STARTUP_PROFILES')) { [void] $Environment.Remove($key) }
    }
    if ($Socket) { $Environment['WEZTERM_UNIX_SOCKET'] = $Socket }
    if ($null -ne $StartupProfiles) { $Environment['WEZTERM_STARTUP_PROFILES'] = $StartupProfiles }
}

function New-ProfileProcessInfo([string] $Path, [string[]] $Arguments, [string] $Socket, $StartupProfiles, [bool] $CaptureOutput) {
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Path
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $CaptureOutput
    $info.RedirectStandardOutput = $CaptureOutput
    $info.RedirectStandardError = $CaptureOutput
    foreach ($argument in $Arguments) { [void] $info.ArgumentList.Add($argument) }
    Set-ProfileChildEnvironment $info.Environment $Socket $StartupProfiles
    return $info
}

function Invoke-ProfileProcess($Info, [bool] $Wait) {
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $Info
    $result = @{ Started = $false; Succeeded = $false; Output = ''; CleanupFailed = $false }
    try {
        $result.Started = $process.Start()
        if ($result.Started -and $Wait) {
            $output = $process.StandardOutput.ReadToEndAsync()
            $errorOutput = $process.StandardError.ReadToEndAsync()
            if ($process.WaitForExit(5000) -and [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]] @($output, $errorOutput), 5000)) {
                $result.Output = $output.GetAwaiter().GetResult()
                [void] $errorOutput.GetAwaiter().GetResult()
                $result.Succeeded = ($process.ExitCode -eq 0)
            }
        }
    } finally {
        try { $process.Dispose() } catch { $result.CleanupFailed = $true }
    }
    return $result
}

function Invoke-ProfileStart {
    <#
    .SYNOPSIS
    Requests profile starts in an existing GUI or starts one GUI.
    .DESCRIPTION
    A staged best-effort launcher. Cold requests do not confirm individual profiles.
    .PARAMETER ProfileId
    Ordered profile GUIDs, with or without braces.
    .PARAMETER Cwd
    Optional absolute working directory.
    .PARAMETER WezTermPath
    Absolute path to wezterm.exe, next to wezterm-gui.exe.
    .PARAMETER AppendDefault
    Append the GUI configuration's default profile.
    .OUTPUTS
    Hashtable containing status, acknowledged requests and uncertainty.
    .EXAMPLE
    Invoke-ProfileStart -ProfileId '{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}' -WezTermPath 'C:\Tools\wezterm.exe'
    .NOTES
    Requires a compatible GUI configuration. Independent GUI starts remain a race.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [string[]] $ProfileId = @(),
        [string] $Cwd,
        [Parameter(Mandatory)] [string] $WezTermPath,
        [switch] $AppendDefault
    )
    $ErrorActionPreference = 'Stop'
    $mutex = $null
    $guis = @()
    $result = @{ Status = 'Failed'; OperationStatus = 'Failed'; AcknowledgedSpawns = 0; OutcomeUncertain = $false; CleanupFailed = $false; Message = 'Unable to start profiles.' }
    try {
        if (-not $AppendDefault -and $ProfileId.Count -ne 1) { throw 'Invalid request.' }
        $profiles = @($ProfileId | ForEach-Object {
            $guid = [guid]::Empty
            if (-not ([guid]::TryParseExact($_, 'B', [ref] $guid) -or [guid]::TryParseExact($_, 'D', [ref] $guid)) -or $guid -eq [guid]::Empty) { throw 'Invalid request.' }
            $guid.ToString('B').ToLowerInvariant()
        })
        if ($WezTermPath -notmatch '^[A-Za-z]:\\' -or [System.IO.Path]::GetFileName($WezTermPath) -ine 'wezterm.exe') { throw 'Invalid request.' }
        $binary = [System.IO.Path]::GetFullPath($WezTermPath)
        $guiPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($binary), 'wezterm-gui.exe')
        if (-not (Test-ProfilePath $binary 'File') -or -not (Test-ProfilePath $guiPath 'File')) { throw 'Executable unavailable.' }
        if ($PSBoundParameters.ContainsKey('Cwd')) {
            if (-not [System.IO.Path]::IsPathFullyQualified($Cwd)) { throw 'Invalid request.' }
            $Cwd = [System.IO.Path]::GetFullPath($Cwd)
            if (-not (Test-ProfilePath $Cwd 'Directory')) { throw 'Directory unavailable.' }
        }
        $mutex = Enter-ProfileMutex
        $guis = @(Get-ProfileGuis)
        if ($guis.Count -gt 1) { $result.Message = 'Multiple WezTerm GUIs found.'; throw 'Multiple GUIs.' }
        if ($guis.Count -eq 0) {
            if ($AppendDefault -and $profiles.Count -gt 0 -and $PSBoundParameters.ContainsKey('Cwd')) { throw 'Startup cwd is unsupported.' }
            $arguments = @('start', '--always-new-process')
            $startup = $null
            if ($AppendDefault -and -not $PSBoundParameters.ContainsKey('Cwd')) {
                $startup = ConvertTo-Json -InputObject @($profiles) -Compress
            } else {
                if ($PSBoundParameters.ContainsKey('Cwd')) { $arguments += @('--cwd', $Cwd) }
                $selector = if ($AppendDefault) { 'default' } else { $profiles[0] }
                $arguments += @('--', 'C:\<wezterm-profile-dispatch>', $selector)
            }
            $info = New-ProfileProcessInfo $guiPath $arguments '' $startup $false
            $result.OutcomeUncertain = $true
            $start = Invoke-ProfileProcess $info $false
            if ($start.Started) { $result.OperationStatus = 'GuiStartRequested' }
            if ($start.CleanupFailed) { $result.CleanupFailed = $true }
            if (-not $start.Started -or $result.CleanupFailed) { throw 'Start failed.' }
            $result.Status = 'GuiStartRequested'
        } else {
            $gui = $guis[0]
            if ($gui.Path -ine $guiPath -and (Get-FileHash -LiteralPath $gui.Path -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $guiPath -Algorithm SHA256).Hash) { throw 'Unexpected GUI executable.' }
            $socket = Get-ProfileSocket $gui.Id
            $selectors = @($profiles)
            if ($AppendDefault) { $selectors += 'default' }
            foreach ($selector in $selectors) {
                if ($gui.Process.HasExited) { throw 'GUI unavailable.' }
                $snapshot = @(Get-ProfileGuis)
                try {
                    if ($snapshot.Count -ne 1 -or $snapshot[0].Id -ne $gui.Id) { throw 'GUI changed.' }
                } finally {
                    foreach ($entry in $snapshot) { $entry.Process.Dispose() }
                }
                $listInfo = New-ProfileProcessInfo $binary @('cli', '--no-auto-start', 'list', '--format', 'json') $socket $null $true
                $list = Invoke-ProfileProcess $listInfo $true
                if ($list.CleanupFailed) { $result.CleanupFailed = $true }
                if (-not $list.Succeeded -or $result.CleanupFailed) { throw 'List failed.' }
                $rows = ConvertFrom-Json -InputObject $list.Output -AsHashtable -NoEnumerate -ErrorAction Stop
                if ($rows -isnot [array] -or $rows.Count -eq 0) { throw 'Window list unavailable.' }
                $windows = @($rows | ForEach-Object { if ($_.window_id -isnot [long]) { throw 'Invalid window.' }; $_.window_id } | Select-Object -Unique)
                if ($windows.Count -ne 1) { $result.Message = 'Expected exactly one WezTerm window.'; throw 'Multiple windows.' }
                $arguments = @('cli', '--no-auto-start', 'spawn', '--window-id', [string] $windows[0], '--domain-name', ('profile-' + $selector))
                if ($PSBoundParameters.ContainsKey('Cwd')) { $arguments += @('--cwd', $Cwd) }
                $arguments += @('--', 'C:\<wezterm-profile-dispatch>')
                $spawnInfo = New-ProfileProcessInfo $binary $arguments $socket $null $true
                $result.OutcomeUncertain = $true
                $spawn = Invoke-ProfileProcess $spawnInfo $true
                if ($spawn.CleanupFailed) { $result.CleanupFailed = $true }
                if (-not $spawn.Succeeded -or $spawn.Output.Trim() -notmatch '^\d+$') { throw 'Spawn failed.' }
                $result.AcknowledgedSpawns++
                $result.OutcomeUncertain = $false
                if ($result.CleanupFailed) {
                    if ($result.AcknowledgedSpawns -eq $selectors.Count) { $result.OperationStatus = 'Completed' }
                    throw 'Cleanup failed.'
                }
            }
            $result.OperationStatus = 'Completed'
            $result.Status = 'Completed'
        }
    } catch {
        $result.Status = 'Failed'
    } finally {
        foreach ($gui in $guis) {
            try { $gui.Process.Dispose() } catch { $result.CleanupFailed = $true; $result.Status = 'Failed' }
        }
        if ($null -ne $mutex) {
            try { Exit-ProfileMutex $mutex } catch { $result.CleanupFailed = $true; $result.Status = 'Failed' }
        }
    }
    return $result
}
