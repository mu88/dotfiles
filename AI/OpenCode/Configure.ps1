# Link OpenCode configuration to this dotfiles repo so there is a single source of truth.
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$dotfilesRoot = $env:MU88_DOTFILES
if (-not $dotfilesRoot) {
    Write-Error "MU88_DOTFILES environment variable is not set. Aborting."
    exit 1
}

$cliPath = Join-Path $dotfilesRoot 'AI/OpenCode/cli.json'
$cliContent = Get-Content -LiteralPath $cliPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
$existingCliContent = [Environment]::GetEnvironmentVariable('OPENCODE_CLI_CONFIG_CONTENT', 'User')
if ($existingCliContent -and $existingCliContent -ne $cliContent) {
    throw 'Existing OPENCODE_CLI_CONFIG_CONTENT differs from the shared configuration. Review it before running setup.'
}

if ($PSCmdlet.ShouldProcess('User environment: OPENCODE_CONFIG', 'Register OpenCode configuration')) {
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG", (Join-Path $dotfilesRoot "AI/OpenCode/opencode.json"), "User")
}
if ($PSCmdlet.ShouldProcess('User environment: OPENCODE_CLI_CONFIG_CONTENT', 'Register shared OpenCode CLI configuration')) {
    [Environment]::SetEnvironmentVariable('OPENCODE_CLI_CONFIG_CONTENT', $cliContent, 'User')
}
