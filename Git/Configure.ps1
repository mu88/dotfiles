#!/usr/bin/pwsh

# Kudos to https://stackoverflow.com/a/65963666/4919526

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

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
