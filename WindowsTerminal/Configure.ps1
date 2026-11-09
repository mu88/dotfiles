# Link psmux configuration to this dotfiles repo so there is a single source of truth.
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$dotfilesRoot = $env:MU88_DOTFILES
if (-not $dotfilesRoot) {
    Write-Error "MU88_DOTFILES environment variable is not set. Aborting."
    exit 1
}

if ($PSCmdlet.ShouldProcess('User environment: PSMUX_CONFIG_FILE', 'Register psmux configuration')) {
    [Environment]::SetEnvironmentVariable("PSMUX_CONFIG_FILE", (Join-Path $dotfilesRoot "WindowsTerminal/psmux.conf"), "User")
}
