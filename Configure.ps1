#!/usr/bin/pwsh

<#
.SYNOPSIS
    Configures the dotfiles checkout.
.DESCRIPTION
    Registers the checkout and runs each available setup script.
.EXAMPLE
    ./Configure.ps1 -WhatIf
.EXAMPLE
    ./Configure.ps1
.OUTPUTS
    None.
.NOTES
    WhatIf previews changes without modifying the user environment.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$dotfilesDirectory = $PSScriptRoot.Replace('\', '/')
$originalDotfiles = $env:MU88_DOTFILES

if ($PSCmdlet.ShouldProcess('User environment: MU88_DOTFILES', "Set to $dotfilesDirectory")) {
    [Environment]::SetEnvironmentVariable('MU88_DOTFILES', $dotfilesDirectory, 'User')
}
try {
    $env:MU88_DOTFILES = $dotfilesDirectory
    foreach ($directory in Get-ChildItem -LiteralPath $dotfilesDirectory -Directory) {
        Write-Host "Switching to $($directory.FullName)"
        Push-Location $directory.FullName
        try {
            if (Test-Path -Path "Configure.ps1") {
                Write-Host "Running local Configure.ps1"
                ./Configure.ps1 -WhatIf:$WhatIfPreference
            }
        } finally {
            Pop-Location
        }
    }
} finally {
    if ($WhatIfPreference) { $env:MU88_DOTFILES = $originalDotfiles }
}
