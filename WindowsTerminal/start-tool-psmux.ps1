#!/usr/bin/pwsh

param(
    [Parameter(Mandatory)]
    [string]$ToolName,
    [Parameter(Mandatory)]
    [string]$Executable,
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

$commandSegments = [System.Collections.Generic.List[string]]::new()
# Set PSMUX_SESSION in the server environment before stripping TMUX — psmux set-environment
# requires TMUX to be set. All subsequent panes opened in this session will inherit it.
$escapedSessionForCmd = $sessionName.Replace("'", "''")
$commandSegments.Add("& psmux set-environment -t '$escapedSessionForCmd' PSMUX_SESSION '$escapedSessionForCmd'")
$commandSegments.Add('Remove-Item Env:TMUX -ErrorAction SilentlyContinue')

# psmux does not reliably pass PATH through to new panes (unlike every other
# environment variable, which is inherited fine) - confirmed by direct testing:
# a uniquely-named PATH entry added on the calling process vanishes in the
# pane, while the same entry survives a plain child-process spawn without
# psmux. Re-set it explicitly as a real statement inside the pane itself so
# tools like the "Code.exe" external editor (which needs the VS Code install
# directory on PATH, see the Windows Terminal profile's "environment" block)
# keep working.
$commandSegments.Add("`$env:PATH = " + (Format-PowerShellSingleQuotedLiteral -Value $env:PATH))

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

# Start the server directly. It inherits the real shell environment, and PATH
# is re-set explicitly above because psmux does not pass it through reliably.
$pwshPath = (Get-Command pwsh).Source

$PSNativeCommandUseErrorActionPreference = $false
& psmux new-session -d -s $sessionName -c $repoPath -- $pwshPath -NoLogo -NoExit -Command $sessionCommand
$newSessionExitCode = $LASTEXITCODE
$PSNativeCommandUseErrorActionPreference = $true
if ($newSessionExitCode -ne 0) {
    throw "psmux new-session failed (exitCode=$newSessionExitCode)"
}

& psmux set-environment -t $sessionName PSMUX_SESSION $sessionName
& psmux attach-session -t $sessionName
exit $LASTEXITCODE
