#!/usr/bin/pwsh
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    [string] $ProxyAddress = ($env:HTTP_PROXY ?? $env:http_proxy ?? $env:HTTPS_PROXY ?? $env:https_proxy)
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$installDirectory = 'C:\Program Files\dotnet'
$sdkDirectory = Join-Path (Join-Path $installDirectory 'sdk') $Version
$msbuildPath = Join-Path $sdkDirectory 'MSBuild.dll'
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isElevated) {
    if ($WhatIfPreference) {
        $null = $PSCmdlet.ShouldProcess($installDirectory, "Install .NET SDK $Version")
        return
    }

    $elevatedArguments = @(
        '-NoProfile',
        '-NoExit',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f $PSCommandPath),
        '-Version',
        $Version
    )

    if ($ProxyAddress) {
        $elevatedArguments += @('-ProxyAddress', ('"{0}"' -f $ProxyAddress))
    }

    Start-Process -FilePath 'pwsh.exe' -Verb RunAs -ArgumentList $elevatedArguments
    return
}

$dotnetInstallScript = Join-Path $env:TEMP "dotnet-install-$([guid]::NewGuid()).ps1"

try {
    if (Test-Path -LiteralPath $msbuildPath) {
        Write-Output ".NET SDK $Version is already installed."
        return
    }

    if (Test-Path -LiteralPath $sdkDirectory) {
        $sdkFiles = @(Get-ChildItem -LiteralPath $sdkDirectory -Force)
        if ($sdkFiles.Count -gt 0) {
            throw "Incomplete .NET SDK directory detected: $sdkDirectory. Remove or repair it before retrying."
        }

        if ($PSCmdlet.ShouldProcess($sdkDirectory, 'Remove empty incomplete .NET SDK directory')) {
            Remove-Item -LiteralPath $sdkDirectory -Force
        }
    }

    if (-not $PSCmdlet.ShouldProcess($installDirectory, "Install .NET SDK $Version")) {
        return
    }

    $downloadParameters = @{
        Uri     = 'https://dot.net/v1/dotnet-install.ps1'
        OutFile = $dotnetInstallScript
    }
    $installParameters = @{
        Version      = $Version
        Architecture = 'x64'
        InstallDir   = $installDirectory
    }

    if ($ProxyAddress) {
        $downloadParameters.Proxy = $ProxyAddress
        $downloadParameters.ProxyUseDefaultCredentials = $true
        $installParameters.ProxyAddress = $ProxyAddress
        $installParameters.ProxyUseDefaultCredentials = $true
    }

    Invoke-WebRequest @downloadParameters
    & $dotnetInstallScript @installParameters

    if (-not (Test-Path -LiteralPath $msbuildPath)) {
        throw "The .NET SDK installation did not create the expected file: $msbuildPath"
    }

    Write-Output ".NET SDK $Version installed successfully."
} catch {
    Write-Error "Failed to install .NET SDK $Version. $($_.Exception.Message)"
    throw
} finally {
    if (Test-Path -LiteralPath $dotnetInstallScript) {
        Remove-Item -LiteralPath $dotnetInstallScript -Force
    }
}
