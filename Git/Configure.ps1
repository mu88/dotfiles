#!/usr/bin/pwsh

<#
.SYNOPSIS
    Configures the shared Git settings for this checkout.
.DESCRIPTION
    On Linux, registers the shared configuration and hooks using Git's config commands.
    On Windows, preserves the existing environment-based setup.
.EXAMPLE
    ./Configure.ps1 -WhatIf
.EXAMPLE
    ./Configure.ps1
.OUTPUTS
    None.
.NOTES
    Visible conflicting hook paths are not overwritten. Review inactive conditional includes before setup.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

# Kudos to https://stackoverflow.com/a/65963666/4919526

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if ($IsLinux) {
    $sharedConfig = Join-Path $PSScriptRoot '.gitconfig'
    $hooksPath = Join-Path $PSScriptRoot 'hooks'
    $globalConfig = Join-Path $HOME '.gitconfig'
    $signingConfig = Join-Path $HOME '.gitconfig-mu88-local'
    $allowedSigners = Join-Path $PSScriptRoot '.ssh/allowedSigners'
    $signingScript = Join-Path $PSScriptRoot 'Get-GitSigningKey.ps1'

    if (-not [string]::IsNullOrWhiteSpace($env:GIT_CONFIG_GLOBAL) -and
        [IO.Path]::GetFullPath($env:GIT_CONFIG_GLOBAL, $HOME) -cne [IO.Path]::GetFullPath($globalConfig)) {
        throw 'GIT_CONFIG_GLOBAL points elsewhere; resolve it explicitly before setup.'
    }
    foreach ($path in @($sharedConfig, $hooksPath, $allowedSigners, $signingScript)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required Git setup path is missing: $path"
        }
    }
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $existingHook = & git -C $HOME config --path --get core.hooksPath 2>$null
        $hookExitCode = $LASTEXITCODE
        $existingIncludes = @(& git -C $HOME config --file $globalConfig --path --get-all include.path 2>$null)
        $includeExitCode = $LASTEXITCODE
    } finally {
        $PSNativeCommandUseErrorActionPreference = $true
    }
    if ($hookExitCode -notin @(0, 1) -or $includeExitCode -notin @(0, 1)) {
        throw 'Could not read the Git configuration; no changes were made.'
    }
    if ($hookExitCode -eq 0 -and $existingHook.TrimEnd('/') -cne $hooksPath.TrimEnd('/')) {
        throw 'An existing Git hook path points elsewhere; resolve it explicitly before setup.'
    }

    $hasSharedConfig = @($existingIncludes | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and [IO.Path]::GetFullPath($_, $HOME) -ceq [IO.Path]::GetFullPath($sharedConfig)
    }).Count -gt 0
    if (-not $hasSharedConfig -and $PSCmdlet.ShouldProcess($globalConfig, 'Add the shared Git configuration include')) {
        & git config --file $globalConfig --add include.path $sharedConfig
    }
    if ($PSCmdlet.ShouldProcess($globalConfig, 'Set the shared Git hook path')) {
        & git config --file $globalConfig --replace-all core.hooksPath $hooksPath
    }
    if (Test-Path -LiteralPath $signingConfig) {
        Write-Warning "Existing signing configuration preserved; review its settings: $signingConfig"
    } elseif ($PSCmdlet.ShouldProcess($signingConfig, 'Create the local SSH signing configuration')) {
        $quotedScript = "'" + $signingScript.Replace("'", "'`"'`"'") + "'"
        & git config --file $signingConfig gpg.ssh.allowedSignersFile $allowedSigners
        & git config --file $signingConfig gpg.ssh.defaultKeyCommand "pwsh -NoProfile -File $quotedScript"
    }
    return
}

if (-not $PSCmdlet.ShouldProcess('Windows user Git configuration', 'Apply the environment-based Git setup')) {
    return
}

function Get-GitEnvironmentConfig {
    param([Parameter(Mandatory)] [System.EnvironmentVariableTarget]$Target)

    $countText = [Environment]::GetEnvironmentVariable("GIT_CONFIG_COUNT", $Target)
    $count = 0
    [void][int]::TryParse($countText, [ref]$count)

    for ($index = 0; $index -lt $count; $index++) {
        [PSCustomObject]@{
            Key = [Environment]::GetEnvironmentVariable("GIT_CONFIG_KEY_$index", $Target)
            Value = [Environment]::GetEnvironmentVariable("GIT_CONFIG_VALUE_$index", $Target)
        }
    }
}

function Set-GitEnvironmentConfig {
    param(
        [Parameter(Mandatory)] [System.EnvironmentVariableTarget]$Target,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$ManagedConfig
    )

    $existingConfig = @(Get-GitEnvironmentConfig -Target $Target | Where-Object { -not $ManagedConfig.Contains($_.Key) })
    $updatedConfig = @($existingConfig) + @(
        $ManagedConfig.GetEnumerator() |
            Where-Object { $null -ne $_.Value } |
            ForEach-Object { [PSCustomObject]@{ Key = $_.Key; Value = $_.Value } }
    )
    $previousCount = @(Get-GitEnvironmentConfig -Target $Target).Count

    for ($index = 0; $index -lt [Math]::Max($previousCount, $updatedConfig.Count); $index++) {
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$index", $null, $Target)
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$index", $null, $Target)
    }

    [Environment]::SetEnvironmentVariable("GIT_CONFIG_COUNT", $updatedConfig.Count, $Target)
    for ($index = 0; $index -lt $updatedConfig.Count; $index++) {
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$index", $updatedConfig[$index].Key, $Target)
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$index", $updatedConfig[$index].Value, $Target)
    }
}

Write-Host "When running on Windows, do not forget to configure 'core.sshCommand' and 'gpg.ssh.program' when signing Git commits via Bitwarden SSH Agent (see https://bitwarden.com/help/ssh-agent/#configure-git-for-ssh-signing)."

$gitDirectory = $PSScriptRoot
$allowedSignersFile = (Join-Path $gitDirectory ".ssh" "allowedSigners").Replace('\', '/')
$signingKeyCommand = (Join-Path $gitDirectory "Get-GitSigningKey.ps1").Replace('\', '/')
$localGitConfig = Join-Path $HOME ".gitconfig-mu88-local"

@"
[gpg "ssh"]
    allowedSignersFile = $allowedSignersFile
    defaultKeyCommand = pwsh -NoProfile -File \"$signingKeyCommand\"
"@ | Set-Content -LiteralPath $localGitConfig -Encoding utf8NoBOM

$managedConfigs = [ordered]@{
    "core.hooksPath" = Join-Path $gitDirectory "hooks"
    "include.path" = Join-Path $gitDirectory ".gitconfig"
    "gpg.ssh.allowedSignersFile" = $null
}

Set-GitEnvironmentConfig -Target User -ManagedConfig $managedConfigs
Set-GitEnvironmentConfig -Target Process -ManagedConfig $managedConfigs
