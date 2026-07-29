#!/usr/bin/pwsh

param(
    [Parameter(Mandatory)]
    [string]$ToolName,
    [Parameter(Mandatory)]
    [string]$Executable,
    [Parameter(Mandatory)]
    [string]$EnvPrefix,
    [string[]]$Arguments = @()
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Normalize-DirectoryPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path.Trim()))
}

function Get-SessionCurrentPath {
    param([string]$TargetSession)

    $currentPath = & psmux display-message -p -t $TargetSession '#{pane_current_path}' 2>$null
    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath($currentPath.Trim())
}

function Format-PowerShellSingleQuotedLiteral {
    param([string]$Value)

    return "'{0}'" -f $Value.Replace("'", "''")
}

$repoPath = [System.IO.Path]::GetFullPath($PWD.Path)
$sessionName = ''
$gitRoot = $null

# Resolve the repository root once so session identity stays stable across subdirectories.
$PSNativeCommandUseErrorActionPreference = $false
try {
    $gitRoot = git -C $PWD.Path rev-parse --show-toplevel 2>$null
}
finally {
    $PSNativeCommandUseErrorActionPreference = $true
}

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
    $sessionName = Split-Path -Leaf $gitRoot.Trim()
}
else {
    $sessionName = 'WT_' + (Get-Date -Format 'yyMMdd_HHmmss')
}

$Host.UI.RawUI.WindowTitle = $sessionName

$resolvedCommand = Get-Command $Executable -ErrorAction SilentlyContinue
if (-not $resolvedCommand) {
    throw "Executable '$Executable' not found."
}

$resolvedExecutablePath = [string]$resolvedCommand.Source
$envInjections = [System.Collections.Generic.List[string]]::new()
$environmentVariables = [System.Environment]::GetEnvironmentVariables()
foreach ($entry in $environmentVariables.GetEnumerator()) {
    $variableName = [string]$entry.Key
    $allowedByPrefix = -not [string]::IsNullOrWhiteSpace($EnvPrefix) -and $variableName -like ("{0}*" -f $EnvPrefix)

    # WT_* (WT_SESSION, WT_PROFILE_ID, ...) must be forwarded explicitly: the psmux server is
    # bootstrapped via WMI (Win32_Process::Create, see below) as a child of WmiPrvSE.exe, which
    # runs in a bare SYSTEM/DCOM environment without any Windows Terminal session variables.
    # Without this, tools launched inside the pane (e.g. Copilot CLI) cannot detect they are
    # running under Windows Terminal and silently suppress terminal-only features (e.g. OSC 9;4
    # progress).
    if ($variableName -notin @('PATH', 'EDITOR', 'VISUAL') -and
        -not $allowedByPrefix -and
        $variableName -notlike 'NODE_*' -and
        $variableName -notlike '*PROXY*' -and
        $variableName -notlike 'WT_*') {
        continue
    }

    $value = [string]$entry.Value
    if (-not [string]::IsNullOrEmpty($value)) {
        $escapedValue = $value.Replace("'", "''")
        $envInjections.Add("`$env:$variableName = '$escapedValue'")
    }
}

$commandSegments = [System.Collections.Generic.List[string]]::new()
# Set PSMUX_SESSION in the server environment before stripping TMUX — psmux set-environment
# requires TMUX to be set. All subsequent panes opened in this session will inherit it.
$escapedSessionForCmd = $sessionName.Replace("'", "''")
$commandSegments.Add("& psmux set-environment -t '$escapedSessionForCmd' PSMUX_SESSION '$escapedSessionForCmd'")
$commandSegments.Add('Remove-Item Env:TMUX -ErrorAction SilentlyContinue')
$commandSegments.AddRange($envInjections)

$quotedExecutable = Format-PowerShellSingleQuotedLiteral -Value $resolvedExecutablePath
$quotedArguments = @($Arguments | ForEach-Object { Format-PowerShellSingleQuotedLiteral -Value $_ })
$toolCommand = @("& $quotedExecutable")
if ($quotedArguments.Count -gt 0) {
    $toolCommand += ($quotedArguments -join ' ')
}
$commandSegments.Add(($toolCommand -join ' '))
$sessionCommand = $commandSegments -join '; '

$normalizedRepoPath = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
    Normalize-DirectoryPath -Path $gitRoot
}
else {
    Normalize-DirectoryPath -Path $repoPath
}

$sessionExists = $false
# "psmux ls" exits non-zero when no session exists; handle that as normal control flow.
$PSNativeCommandUseErrorActionPreference = $false
try {
    & psmux ls | ForEach-Object {
        if ($_ -match '^(?<name>[^:]+):') {
            if ($Matches['name'] -eq $sessionName) {
                $sessionExists = $true
            }
        }
    }
}
finally {
    $PSNativeCommandUseErrorActionPreference = $true
}

if ($sessionExists) {
    # Reuse only when session path still matches the current repository root.
    $currentPath = Get-SessionCurrentPath -TargetSession $sessionName
    if ($currentPath -and (Normalize-DirectoryPath -Path $currentPath) -ieq $normalizedRepoPath) {
        & psmux set-environment -t $sessionName PSMUX_SESSION $sessionName
        & psmux attach-session -t $sessionName
        exit $LASTEXITCODE
    }

    # Same name but different path: remove stale session and recreate it.
    & psmux kill-session -t $sessionName
}

# Windows Terminal assigns every tab's process tree to a kill-on-close Job
# Object that does not permit breakaway (unlike sshd's job, see psmux issue
# #187). If we call "psmux new-session" directly here, the server process is
# spawned as a descendant of THIS process and inherits that job, so closing
# the tab kills the psmux session server itself (not just the client) even
# though psmux's server spawn code already tries CREATE_BREAKAWAY_FROM_JOB.
#
# Workaround: bootstrap the server fully detached (-d) via WMI's
# Win32_Process::Create. WMI spawns the child as a descendant of WmiPrvSE.exe,
# which is never part of Windows Terminal's job tree, so the server survives
# tab/window closure unconditionally. Once the session is confirmed alive, we
# attach to it as an ordinary client from this (job-bound) process; if that
# client dies when the tab closes, only the client detaches - the server,
# living outside the job, is unaffected.
$psmuxPath = (Get-Command psmux).Source
$pwshPath = (Get-Command pwsh).Source
$escapedSessionCommand = $sessionCommand.Replace('"', '\"')
$wmiCommandLine = '"{0}" new-session -d -s "{1}" -- "{2}" -NoLogo -NoExit -Command "{3}"' -f `
    $psmuxPath, $sessionName, $pwshPath, $escapedSessionCommand

# SW_HIDE (0) on the startup info suppresses the console window WMI would
# otherwise briefly flash for this bootstrap process before psmux forks
# off its own hidden server console.
$processStartup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
$bootstrapResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine               = $wmiCommandLine
    CurrentDirectory          = $repoPath
    ProcessStartupInformation = $processStartup
}
if ($bootstrapResult.ReturnValue -ne 0) {
    throw "Win32_Process::Create failed with ReturnValue=$($bootstrapResult.ReturnValue)"
}
$bootstrapPid = $bootstrapResult.ProcessId

# Poll for the session to appear (readiness gate), bailing out early if the
# bootstrap process has already died.
$readyDeadline = [datetime]::UtcNow.AddSeconds(10)
$sessionReady = $false
while ([datetime]::UtcNow -lt $readyDeadline) {
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        & psmux ls | ForEach-Object {
            if ($_ -match '^(?<name>[^:]+):' -and $Matches['name'] -eq $sessionName) { $sessionReady = $true }
        }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $true
    }
    if ($sessionReady) { break }
    if (-not (Get-Process -Id $bootstrapPid -ErrorAction SilentlyContinue)) {
        throw "Bootstrap process $bootstrapPid exited before session '$sessionName' became visible."
    }
    Start-Sleep -Milliseconds 150
}
if (-not $sessionReady) {
    throw "Timed out waiting for session '$sessionName' to appear after WMI bootstrap."
}

& psmux set-environment -t $sessionName PSMUX_SESSION $sessionName
& psmux attach-session -t $sessionName
exit $LASTEXITCODE
