<#
.SYNOPSIS
    Links a missing agent directory and registers Copilot instructions on Windows.
.DESCRIPTION
    Preserves local instructions and existing environment entries.
    Existing instruction directory links require explicit migration before setup.
.EXAMPLE
    .\Configure.ps1 -WhatIf
.EXAMPLE
    .\Configure.ps1
.OUTPUTS
    None.
.NOTES
    Existing local content is never replaced. RTK file symlinks may require elevation.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$dotfilesRoot = $env:MU88_DOTFILES
if ([string]::IsNullOrWhiteSpace($dotfilesRoot)) {
    throw 'MU88_DOTFILES is not set. Configure the canonical dotfiles checkout before running setup.'
}
$sourceBase = Join-Path ([System.IO.Path]::GetFullPath($dotfilesRoot)) 'AI\GitHub Copilot'
$sharedBase = Join-Path ([System.IO.Path]::GetFullPath($dotfilesRoot)) 'AI\Shared'

$copilotHome = $env:COPILOT_HOME
if ([string]::IsNullOrWhiteSpace($copilotHome)) {
    $copilotHome = Join-Path $HOME '.copilot'
}

$localInstructions = Get-Item -LiteralPath (Join-Path $copilotHome 'instructions') -Force -ErrorAction SilentlyContinue
if ($localInstructions -and ($localInstructions.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    throw 'The local instructions directory is a link. Migrate it explicitly before registering additional instructions.'
}

$instructionsDirectory = Join-Path $sharedBase 'instructions'
if (-not (Test-Path -LiteralPath $instructionsDirectory -PathType Container)) {
    throw "Required source directory is missing: $instructionsDirectory"
}
if ($instructionsDirectory.Contains(',')) {
    throw 'The instruction directory cannot contain commas because Copilot uses comma-separated paths.'
}

if (-not $IsLinux) {
    $environmentName = 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS'
    $currentValue = [Environment]::GetEnvironmentVariable($environmentName, 'User')
    $directories = @($currentValue -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hasInstructions = @($directories | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ieq $instructionsDirectory.TrimEnd('\', '/')
    }).Count -gt 0
    if (-not $hasInstructions -and $PSCmdlet.ShouldProcess(
        "User environment: $environmentName", "Append $instructionsDirectory"
    )) {
        $newValue = (@($directories) + $instructionsDirectory) -join ','
        [Environment]::SetEnvironmentVariable($environmentName, $newValue, 'User')
    }
}

$target = Join-Path $copilotHome 'agents'
$source = Join-Path $sourceBase 'agents'
if (Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue) {
    Write-Warning "Preserving existing Copilot path without changes: $target"
} else {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required source directory is missing: $source"
    }
    $linkType = if ($IsLinux) { 'SymbolicLink' } else { 'Junction' }
    if ($PSCmdlet.ShouldProcess($target, "Create $linkType to $source")) {
        New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null
        New-Item -ItemType $linkType -Path $target -Target $source | Out-Null
    }
}

$skillsDirectory = Join-Path $sharedBase 'skills'
if (-not (Test-Path -LiteralPath $skillsDirectory -PathType Container)) {
    throw "Required source directory is missing: $skillsDirectory"
}
$settingsPath = Join-Path $copilotHome 'settings.json'
$alreadyRegistered = $false
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $normalized = $skillsDirectory.TrimEnd('\', '/')
    $alreadyRegistered = (Get-Content -LiteralPath $settingsPath -Raw) -ireplace '\\\\', '\' |
        Select-String -SimpleMatch $normalized -Quiet
}
if (-not $alreadyRegistered -and $PSCmdlet.ShouldProcess(
    "Copilot settings: $settingsPath", "Register skill directory $skillsDirectory"
)) {
    & copilot skill add $skillsDirectory
}
