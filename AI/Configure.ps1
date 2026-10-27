$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'GitHub Copilot/Configure.ps1')
& (Join-Path $PSScriptRoot 'OpenCode/Configure.ps1')
