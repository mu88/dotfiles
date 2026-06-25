$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$logFile = 'D:\temp\psmux.log'
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $logFile -Value "[$timestamp] $Message"
}

$panePidToSession = @{}
& psmux list-panes -a -F '#{session_name}|#{pane_pid}' | ForEach-Object {
    $parts = $_ -split '\|', 2
    if ($parts.Count -eq 2 -and $parts[1] -match '^\d+$') {
        $panePidToSession[[int]$parts[1]] = $parts[0]
    }
}

$processParentMap = @{}
Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId |
    ForEach-Object { $processParentMap[[int]$_.ProcessId] = [int]$_.ParentProcessId }

function Get-PsmuxSessionForCopilotPid {
    param([int]$CopilotPid)
    $visited = [System.Collections.Generic.HashSet[int]]::new()
    $current = $CopilotPid
    while ($null -ne $current -and $current -ne 0 -and $visited.Add([int]$current)) {
        if ($panePidToSession.ContainsKey([int]$current)) { return $panePidToSession[[int]$current] }
        if (-not $processParentMap.ContainsKey([int]$current)) { break }
        $current = $processParentMap[[int]$current]
    }
    return $null
}

# Collect all candidate sessions per psmux session, then pick the most recently updated one.
# This handles stale lock files: same PID can appear in multiple old session dirs.
$sessionCandidates = @{}   # psmuxSession -> list of [updatedAt, displayName]
$sessionStatePath = Join-Path $env:USERPROFILE '.copilot\session-state'

Get-ChildItem $sessionStatePath -Filter 'inuse.*.lock' -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($_.Name -notmatch 'inuse\.(\d+)\.lock') { return }
        $copilotPid = [int]$Matches[1]

        if (-not $processParentMap.ContainsKey($copilotPid)) { return }

        $psmuxSession = Get-PsmuxSessionForCopilotPid -CopilotPid $copilotPid
        if (-not $psmuxSession) { return }

        $workspaceYaml = Join-Path $_.DirectoryName 'workspace.yaml'
        if (-not (Test-Path $workspaceYaml)) { return }

        $updatedAtMatch = Select-String -Path $workspaceYaml -Pattern '^updated_at:\s*(.+)$' | Select-Object -First 1
        $updatedAt = if ($updatedAtMatch) { [datetime]$updatedAtMatch.Matches[0].Groups[1].Value.Trim() } else { [datetime]::MinValue }

        $nameMatch = Select-String -Path $workspaceYaml -Pattern '^name:\s*(.+)$' | Select-Object -First 1
        $displayName = if ($nameMatch) { $nameMatch.Matches[0].Groups[1].Value.Trim() } else { '(Copilot)' }

        if (-not $sessionCandidates.ContainsKey($psmuxSession)) {
            $sessionCandidates[$psmuxSession] = [PSCustomObject]@{ UpdatedAt = $updatedAt; DisplayName = $displayName }
        } elseif ($updatedAt -gt $sessionCandidates[$psmuxSession].UpdatedAt) {
            $sessionCandidates[$psmuxSession] = [PSCustomObject]@{ UpdatedAt = $updatedAt; DisplayName = $displayName }
        }
    }

$psmuxToDisplayName = @{}
foreach ($entry in $sessionCandidates.GetEnumerator()) {
    $psmuxToDisplayName[$entry.Key] = $entry.Value.DisplayName
}

function Get-SessionDisplayLabel {
    param([string]$SessionName)
    $copilotName = $psmuxToDisplayName[$SessionName]
    if ($copilotName) { return '{0} → {1}' -f $SessionName, $copilotName }
    return $SessionName
}

function Invoke-PsmuxSessionChange {
    param([string]$SessionName)

    # TMUX_PANE is set by psmux for every pane process and is NOT stripped (only TMUX is
    # removed by start-copilot-psmux.ps1 to suppress nested-session warnings). It is the
    # reliable inside-psmux signal. All ConPTY clients share /dev/pts/0, so attach-session -t
    # ignores the target and reattaches to the last session — only switch-client works reliably.
    Write-Log "TMUX_PANE='$($env:TMUX_PANE)'"

    if (-not [string]::IsNullOrWhiteSpace($env:TMUX_PANE)) {
        Write-Log "Inside psmux → switch-client -t '$SessionName'"
        & psmux switch-client -t $SessionName
        Write-Log "switch-client exit code: $LASTEXITCODE"
        return
    }

    Write-Log "Outside psmux → attach-session -t '$SessionName' (session is detached)"
    $PSNativeCommandUseErrorActionPreference = $false
    $clientsBefore = & psmux list-clients 2>&1
    $PSNativeCommandUseErrorActionPreference = $true
    Write-Log "Clients before attach ($($clientsBefore.Count)):"
    $clientsBefore | ForEach-Object { Write-Log "  $_" }

    & psmux attach-session -t $SessionName
    $attachExit = $LASTEXITCODE
    Write-Log "attach-session exit code: $attachExit"

    $PSNativeCommandUseErrorActionPreference = $false
    $clientsAfter = & psmux list-clients 2>&1
    $PSNativeCommandUseErrorActionPreference = $true
    Write-Log "Clients after attach ($($clientsAfter.Count)):"
    $clientsAfter | ForEach-Object { Write-Log "  $_" }
}

$sessionLines = & psmux ls

Write-Log "=== Script start ==="
Write-Log "TMUX_PANE=$($env:TMUX_PANE) | TMUX=$($env:TMUX)"
Write-Log "psmux ls raw output ($($sessionLines.Count) lines):"
$sessionLines | ForEach-Object { Write-Log "  '$_'" }

if (-not $sessionLines -or $sessionLines.Count -eq 0) {
    Write-Host 'No psmux sessions found.'
    exit 0
}

$sessionNames = @()
$attachedSessions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($line in $sessionLines) {
    if ($line -match '^(?<name>[^:]+):') {
        $name = $Matches['name'].Trim()
        $sessionNames += $name
        if ($line -match '\(attached\)') {
            [void]$attachedSessions.Add($name)
        }
    }
}

Write-Log "Parsed session names ($($sessionNames.Count)): $($sessionNames -join ', ')"
Write-Log "Attached sessions: $($attachedSessions -join ', ')"

if ($sessionNames.Count -eq 0) {
    Write-Host 'No attachable psmux sessions found.'
    exit 0
}

# Outside psmux: only offer detached sessions — attach-session is broken for already-attached
# sessions on Windows because all ConPTY clients share the same /dev/pts/0 identifier.
# Inside psmux (PSMUX_SESSION set): offer all sessions and use switch-client.
$insidePsmux = -not [string]::IsNullOrWhiteSpace($env:TMUX_PANE)
Write-Log "insidePsmux=$insidePsmux"

$candidateSessions = if ($insidePsmux) {
    $sessionNames
} else {
    @($sessionNames | Where-Object { -not $attachedSessions.Contains($_) })
}

Write-Log "Candidate sessions ($($candidateSessions.Count)): $($candidateSessions -join ', ')"

if ($candidateSessions.Count -eq 0) {
    Write-Host 'All sessions are currently attached. Use Windows Terminal to navigate to the right tab.'
    exit 0
}

if ($candidateSessions.Count -eq 1) {
    $targetSession = $candidateSessions[0]
    $Host.UI.RawUI.WindowTitle = Get-SessionDisplayLabel $targetSession
}
else {
    Write-Host ''
    Write-Host 'Available psmux sessions:'
    for ($index = 0; $index -lt $candidateSessions.Count; $index++) {
        $displayIndex = $index + 1
        Write-Host ('[{0}] {1}' -f $displayIndex, (Get-SessionDisplayLabel $candidateSessions[$index]))
    }

    Write-Host ''
    $selection = Read-Host 'Choose session number'
    $selectedIndex = 0
    if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
        Write-Host 'Invalid selection.'
        exit 1
    }

    if ($selectedIndex -lt 1 -or $selectedIndex -gt $candidateSessions.Count) {
        Write-Host 'Selection out of range.'
        exit 1
    }

    $targetSession = $candidateSessions[$selectedIndex - 1]
    Write-Log "User selected index=$selectedIndex → targetSession='$targetSession'"
    $Host.UI.RawUI.WindowTitle = Get-SessionDisplayLabel $targetSession
}

Write-Log "Calling Invoke-PsmuxSessionChange with SessionName='$targetSession'"
Write-Log "Env check before attach: TERM=$($env:TERM) | TERM_PROGRAM=$($env:TERM_PROGRAM) | WT_SESSION=$($env:WT_SESSION)"
Invoke-PsmuxSessionChange -SessionName $targetSession
