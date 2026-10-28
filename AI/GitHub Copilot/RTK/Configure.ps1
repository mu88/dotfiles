<#
.SYNOPSIS
    Connects Copilot to the RTK hook and instructions in MU88_DOTFILES.
.DESCRIPTION
    Creates one file symlink and appends an additional instruction directory.
    Preserves other hooks and local instructions. Does not run rtk init or install tools.
    Existing regular hook files and links to other targets must be migrated manually.
.PARAMETER CopilotHome
    Copilot directory. Defaults to COPILOT_HOME, or ~/.copilot when unset.
.PARAMETER EnvironmentTarget
    Environment scope to update. User persists the setting for future terminals.
    Process supports isolated testing without changing persistent settings.
.EXAMPLE
    .\Configure.ps1 -WhatIf
.EXAMPLE
    .\Configure.ps1
.EXAMPLE
    .\Configure.ps1 -CopilotHome "$env:TEMP\copilot-test" -EnvironmentTarget Process
.OUTPUTS
    None. Use -Verbose for setup details.
.NOTES
    Requires PowerShell 7 and permission to create file symlinks on Windows.
    Restart the terminal and Copilot after changing the user environment.
    Keep the MU88_DOTFILES checkout at its current path while the link is in use.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CopilotHome,
    [ValidateSet('User', 'Process')]
    [string]$EnvironmentTarget = 'User'
)

$ErrorActionPreference = 'Stop'

$dotfilesRoot = $env:MU88_DOTFILES
if ([string]::IsNullOrWhiteSpace($dotfilesRoot)) {
    throw 'MU88_DOTFILES is not set. Configure the canonical dotfiles checkout before running setup.'
}
$sourceBase = Join-Path ([System.IO.Path]::GetFullPath($dotfilesRoot)) 'AI\GitHub Copilot\RTK'

if (-not (Get-Command -Name rtk -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'RTK is not available on PATH. Install it separately before configuring Copilot.'
}

if ([string]::IsNullOrWhiteSpace($CopilotHome)) {
    $CopilotHome = $env:COPILOT_HOME
}
if ([string]::IsNullOrWhiteSpace($CopilotHome)) {
    $CopilotHome = Join-Path $HOME '.copilot'
}

$CopilotHome = [System.IO.Path]::GetFullPath($CopilotHome)
$hookSource = Join-Path $sourceBase 'hooks\rtk-rewrite.json'
$instructionsDirectory = Join-Path ([System.IO.Path]::GetFullPath($dotfilesRoot)) 'AI\Shared\RTK\instructions'
$hookTarget = Join-Path $CopilotHome 'hooks\rtk-rewrite.json'
$environmentName = 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS'

foreach ($source in @($hookSource, (Join-Path $instructionsDirectory 'AGENTS.md'))) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required RTK source file is missing: $source"
    }
}
if ($instructionsDirectory.Contains(',')) {
    throw 'The instruction directory cannot contain commas because Copilot uses comma-separated paths.'
}

$existingHook = Get-Item -LiteralPath $hookTarget -Force -ErrorAction SilentlyContinue
if ($existingHook) {
    if ($existingHook.LinkType -ne 'SymbolicLink') {
        throw "Existing hook is not a file symlink. Back it up and migrate it manually: $hookTarget"
    }
    $resolvedHook = $existingHook.ResolveLinkTarget($true)
    if ($null -eq $resolvedHook -or $resolvedHook.FullName -ine $hookSource) {
        throw "Existing hook points elsewhere. Migrate it manually: $hookTarget"
    }
}

$currentValue = [Environment]::GetEnvironmentVariable($environmentName, $EnvironmentTarget)
$directories = @($currentValue -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$hasInstructions = @($directories | Where-Object {
    $_.Trim().TrimEnd('\', '/') -ieq $instructionsDirectory.TrimEnd('\', '/')
}).Count -gt 0
$newValue = $currentValue
if (-not $hasInstructions) {
    $newValue = (@($directories) + $instructionsDirectory) -join ','
}

if (-not $existingHook -and $PSCmdlet.ShouldProcess($hookTarget, "Create file symlink to $hookSource")) {
    New-Item -ItemType Directory -Path (Split-Path $hookTarget) -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path $hookTarget -Target $hookSource | Out-Null
}
if ($newValue -cne $currentValue -and $PSCmdlet.ShouldProcess(
    "$EnvironmentTarget environment: $environmentName", 'Append RTK instruction directory'
)) {
    [Environment]::SetEnvironmentVariable($environmentName, $newValue, $EnvironmentTarget)
}

Write-Verbose "RTK source: $sourceBase"
Write-Verbose 'Existing local instructions were not changed. No tool installation or rtk init was performed.'
