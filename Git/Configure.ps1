#!/usr/bin/pwsh

# Kudos to https://stackoverflow.com/a/65963666/4919526

Write-Host "When running on Windows, do not forget to configure 'core.sshCommand' and 'gpg.ssh.program' when signing Git commits via Bitwarden SSH Agent (see https://bitwarden.com/help/ssh-agent/#configure-git-for-ssh-signing)."

$gitDirectory = $PSScriptRoot
$configs = @{
    "core.hooksPath" = Join-Path $gitDirectory "hooks"
    "include.path" = Join-Path $gitDirectory ".gitconfig"
    "gpg.ssh.allowedSignersFile" = Join-Path $gitDirectory ".ssh" "allowedSigners"
}

Write-Host "Setting GIT_CONFIG_COUNT to $($configs.Count)"
[Environment]::SetEnvironmentVariable("GIT_CONFIG_COUNT", $configs.Count, "User")

$i = 0
foreach ($element in $configs.GetEnumerator()) {
    $key = $element.Key
    $value = $element.Value
    Write-Host "Setting GIT_CONFIG_KEY_$i to $key"
    Write-Host "Setting GIT_CONFIG_VALUE_$i to $value"
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$i", $key, "User")
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$i", $value, "User")
    $i++
}
