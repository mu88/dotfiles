<#
.SYNOPSIS
    Registers additional Copilot instructions and links a missing agent directory.
.DESCRIPTION
    Preserves local instructions and existing environment entries. Optionally configures RTK.
    Existing instruction directory links require explicit migration before setup.
.PARAMETER IncludeRtk
    Also configures the RTK hook and additional instructions. Requires RTK on PATH.
.EXAMPLE
    .\Configure.ps1 -IncludeRtk -WhatIf
.EXAMPLE
    .\Configure.ps1 -IncludeRtk
.OUTPUTS
    None.
.NOTES
    Existing local content is never replaced. RTK file symlinks may require elevation.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$IncludeRtk
)

$ErrorActionPreference = 'Stop'

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

if ($IncludeRtk) {
    & (Join-Path $sourceBase 'RTK\Configure.ps1') -CopilotHome $copilotHome
}

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

$target = Join-Path $copilotHome 'agents'
$source = Join-Path $sourceBase 'agents'
if (Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue) {
    Write-Warning "Preserving existing Copilot path without changes: $target"
} else {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required source directory is missing: $source"
    }
    if ($PSCmdlet.ShouldProcess($target, "Create directory junction to $source")) {
        New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null
        New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    }
}
