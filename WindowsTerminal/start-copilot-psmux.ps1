#!/usr/bin/pwsh

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

& "$PSScriptRoot\start-tool-psmux.ps1" `
    -ToolName 'copilot' `
    -Executable 'copilot' `
    -Arguments @('--no-auto-update')
exit $LASTEXITCODE
