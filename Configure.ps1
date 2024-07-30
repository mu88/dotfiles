#!/usr/bin/pwsh

$dotfilesDirectory = $PSScriptRoot

Write-Host "Setting MU88_DOTFILES to $dotfilesDirectory"
[Environment]::SetEnvironmentVariable("MU88_DOTFILES", $dotfilesDirectory, "User")

Push-Location $dotfilesDirectory

# Get all child directories
$directories = Get-ChildItem -Directory

# iterate through each directory
foreach ($directory in $directories) {
    # Change to the directory
    Write-Host "Switching to $($directory.FullName)"
    Push-Location $directory.FullName

    if (Test-Path -Path "Configure.ps1") {
        Write-Host "Running local Configure.ps1"
        ./Configure.ps1
    }

    # Change back to the parent directory
    Pop-Location
}

# Change back to the directory where the script was started from
Pop-Location
