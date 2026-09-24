#!/usr/bin/pwsh
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isElevated) {
    $confirmation = Read-Host 'This script needs to elevate to Administrator. Continue? (y/N)'
    if ($confirmation -notin @('y', 'Y')) {
        Read-Host 'Cancelled, press Enter to close'
        exit
    }
    Start-Process -FilePath 'pwsh.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    exit
}

if ($env:HTTP_PROXY -or $env:http_proxy -or $env:HTTPS_PROXY -or $env:https_proxy) {
    $proxy = $env:HTTP_PROXY ?? $env:http_proxy ?? $env:HTTPS_PROXY ?? $env:https_proxy
    $useProxy = $true
} else {
    $useProxy = $false
}

$versionToInstall = Read-Host 'Enter the .NET version to install (e.g., 10.0.400)'
if ($versionToInstall -notmatch '^\d+\.\d+\.\d+$') {
    Read-Host 'Invalid version format. Please use the format X.Y.Z (e.g., 10.0.400). Press Enter to close.'
    exit
}

$dotnetInstallScript = Join-Path $env:TEMP 'dotnet-install.ps1'

$downloadParams = @{
    Uri    = 'https://dot.net/v1/dotnet-install.ps1'
    OutFile = $dotnetInstallScript
}

$installParams = @{
    Version      = $versionToInstall
    Architecture = 'x64'
    InstallDir   = 'C:\Program Files\dotnet'
}

if ($useProxy) {
    $downloadParams.Proxy = $proxy
    $downloadParams.ProxyUseDefaultCredentials = $true

    $installParams.ProxyAddress = $proxy
    $installParams.ProxyUseDefaultCredentials = $true
}

Invoke-WebRequest @downloadParams
& $dotnetInstallScript @installParams

Remove-Item $dotnetInstallScript -Force
