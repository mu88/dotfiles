# Run only in Windows Terminal as other terminals might not properly support other PowerShell modules and screw up the formatting
if (!$env:WT_SESSION) {
    return
}

Push-Location $PSScriptRoot

try {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true

    if ($env:MU88_REQUIRES_GITHUB_TOKEN -eq '1' -and [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $token = gh auth token
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw "gh auth token returned no token."
        }

        $env:GITHUB_TOKEN = $token.Trim()
    }

    Import-Module posh-git
    Import-Module PSReadLine

    # Terminal-Icons reads and rewrites shared XML files during import.
    $terminalIconsUserId = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $terminalIconsMutex = [System.Threading.Mutex]::new($false, "Local\TerminalIcons.Import.$terminalIconsUserId")
    $terminalIconsLockAcquired = $false
    try {
        try {
            $terminalIconsLockAcquired = $terminalIconsMutex.WaitOne([TimeSpan]::FromSeconds(30))
        }
        catch [System.Threading.AbandonedMutexException] {
            $terminalIconsLockAcquired = $true
            throw 'A previous Terminal-Icons import was interrupted. Check the shared theme XML files before retrying.'
        }

        if (-not $terminalIconsLockAcquired) {
            throw 'Timed out after 30 seconds waiting for another Terminal-Icons import.'
        }

        Import-Module -Name Terminal-Icons
    }
    finally {
        try {
            if ($terminalIconsLockAcquired) {
                $terminalIconsMutex.ReleaseMutex()
            }
        }
        finally {
            $terminalIconsMutex.Dispose()
        }
    }

    # See https://github.com/JanDeDobbeleer/oh-my-posh/issues/6535#issuecomment-3077804893
    $env:OSTYPE = $null
    oh-my-posh init pwsh --config "OhMyPosh.json" | Invoke-Expression

    # See https://www.hanselman.com/blog/adding-predictive-intellisense-to-my-windows-terminal-powershell-prompt-with-psreadline
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows

    # PowerShell parameter completion shim for the dotnet CLI
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
            dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
               [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
}
catch {
    $profileError = $_
    try {
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) "PowerShell-profile-$PID.log"
        $logEntry = @(
            "Timestamp: $([DateTimeOffset]::Now.ToString('o'))"
            "Process ID: $PID"
            "Script: $($profileError.InvocationInfo.ScriptName)"
            "Line: $($profileError.InvocationInfo.ScriptLineNumber)"
            "Position: $($profileError.InvocationInfo.PositionMessage)"
            "Exception: $($profileError.Exception.ToString())"
            "Error ID: $($profileError.FullyQualifiedErrorId)"
            "Stack trace: $($profileError.ScriptStackTrace)"
            ''
        ) -join [Environment]::NewLine
        Add-Content -LiteralPath $logPath -Value $logEntry -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write profile error log: $($_.Exception.Message)"
    }
    throw
}
finally {
    Pop-Location
}
