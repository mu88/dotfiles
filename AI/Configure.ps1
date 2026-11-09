<#
.SYNOPSIS
    Configures Copilot, OpenCode, and RTK.
.DESCRIPTION
    On Linux, also adds their environment settings to the login profile.
.EXAMPLE
    ./Configure.ps1 -WhatIf
.EXAMPLE
    ./Configure.ps1
.OUTPUTS
    None.
.NOTES
    Existing login profile contents are preserved.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Command -Name rtk -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'RTK is not available on PATH. Install it separately before configuring Copilot.'
}

if ($IsLinux) {
    $dotfilesRoot = if ([string]::IsNullOrWhiteSpace($env:MU88_DOTFILES)) {
        Split-Path -Parent $PSScriptRoot
    } else { $env:MU88_DOTFILES }
    $dotfilesRoot = [System.IO.Path]::GetFullPath($dotfilesRoot).TrimEnd('/')
    if ($dotfilesRoot.Contains(',')) {
        throw 'The dotfiles path cannot contain commas because Copilot uses comma-separated paths.'
    }
    $escapedRoot = $dotfilesRoot.Replace("'", "'`"'`"'")
    $profilePath = Join-Path $HOME '.profile'
    $profileContent = if (Test-Path -LiteralPath $profilePath) {
        [System.IO.File]::ReadAllText($profilePath)
    } else { '' }
    $blocks = @(
        @(
            '# >>> dotfiles AI >>>'
            "export MU88_DOTFILES='$escapedRoot'"
            'export OPENCODE_CONFIG="$MU88_DOTFILES/AI/OpenCode/opencode.json"'
            'case ",${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}," in'
            '    *",$MU88_DOTFILES/AI/Shared/instructions,"*) ;;'
            '    *) export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:+$COPILOT_CUSTOM_INSTRUCTIONS_DIRS,}$MU88_DOTFILES/AI/Shared/instructions" ;;'
            'esac'
            '# <<< dotfiles AI <<<'
        ) -join "`n"
    )
    $blocks += @(
        '# >>> dotfiles RTK >>>'
        'case ",${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}," in'
        '    *",$MU88_DOTFILES/AI/Shared/RTK/instructions,"*) ;;'
        '    *) export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:+$COPILOT_CUSTOM_INSTRUCTIONS_DIRS,}$MU88_DOTFILES/AI/Shared/RTK/instructions" ;;'
        'esac'
        '# <<< dotfiles RTK <<<'
    ) -join "`n"
    $blocks += @(
        '# >>> dotfiles OpenCode CLI >>>'
        'if [ -z "${OPENCODE_CLI_CONFIG_CONTENT+x}" ]; then'
        '    if OPENCODE_CLI_CONFIG_CONTENT="$(cat "$MU88_DOTFILES/AI/OpenCode/cli.json")"; then'
        '        export OPENCODE_CLI_CONFIG_CONTENT'
        '    else'
        '        printf "%s\n" "Failed to read the shared OpenCode CLI configuration." >&2'
        '    fi'
        'fi'
        '# <<< dotfiles OpenCode CLI <<<'
    ) -join "`n"
    foreach ($block in $blocks) {
        $marker = ($block -split "`n")[0]
        if ($profileContent.Contains($marker)) {
            if (-not $profileContent.Contains($block)) {
                throw "Existing setup block differs in $profilePath. Review it before running setup."
            }
            continue
        }
        $prefix = if ($profileContent.Length -gt 0 -and -not $profileContent.EndsWith("`n")) { "`n" } else { '' }
        $addition = "$prefix$block`n"
        if ($PSCmdlet.ShouldProcess($profilePath, "Append $marker settings")) {
            [System.IO.File]::AppendAllText($profilePath, $addition)
        }
        $profileContent += $addition
    }
}

$originalDotfiles = $env:MU88_DOTFILES
try {
    if ($IsLinux) { $env:MU88_DOTFILES = $dotfilesRoot }
    & (Join-Path $PSScriptRoot 'GitHub Copilot/Configure.ps1')
    & (Join-Path $PSScriptRoot 'GitHub Copilot/RTK/Configure.ps1')
    if (-not $IsLinux) {
        & (Join-Path $PSScriptRoot 'OpenCode/Configure.ps1')
    }
} finally {
    if ($IsLinux) { $env:MU88_DOTFILES = $originalDotfiles }
}

if ($IsLinux -and -not $WhatIfPreference) {
    Write-Host 'Log in again to apply the Linux environment settings.'
}
