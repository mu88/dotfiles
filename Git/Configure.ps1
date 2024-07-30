#!/usr/bin/pwsh

# Kudos to https://stackoverflow.com/a/65963666/4919526

$gitDirectory = $PSScriptRoot
$configs = @{
    "core.hooksPath" = Join-Path $gitDirectory "hooks"
    "include.path" = Join-Path $gitDirectory ".gitconfig"
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
