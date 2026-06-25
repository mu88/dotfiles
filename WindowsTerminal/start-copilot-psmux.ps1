#!/usr/bin/pwsh

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

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

$envInjections = [System.Collections.Generic.List[string]]::new()
$envInjections.Add("`$env:COPILOT_AUTO_UPDATE = 'false'")
foreach ($variableName in @('PATH', 'EDITOR', 'VISUAL', 'COPILOT_EDITOR')) {
    $value = [System.Environment]::GetEnvironmentVariable($variableName)
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
$commandSegments.Add('copilot --no-auto-update')
$copilotCommand = $commandSegments -join '; '

function Normalize-DirectoryPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path.Trim()))
}

$normalizedRepoPath = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
    Normalize-DirectoryPath -Path $gitRoot
}
else {
    Normalize-DirectoryPath -Path $repoPath
}

function Get-SessionCurrentPath {
    param([string]$TargetSession)

    $currentPath = & psmux display-message -p -t $TargetSession '#{pane_current_path}' 2>$null
    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath($currentPath.Trim())
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

& psmux new-session -s $sessionName -- pwsh.exe -NoLogo -NoExit -Command $copilotCommand
