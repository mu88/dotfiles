#!/usr/bin/pwsh

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

& "$PSScriptRoot\start-tool-psmux.ps1" `
    -ToolName 'opencode' `
    -Executable 'opencode' `
    -EnvPrefix 'OPENCODE_'
exit $LASTEXITCODE
