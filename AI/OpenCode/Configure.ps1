# Link OpenCode configuration to this dotfiles repo so there is a single source of truth.
$dotfilesRoot = $env:MU88_DOTFILES
if (-not $dotfilesRoot) {
    Write-Error "MU88_DOTFILES environment variable is not set. Aborting."
    exit 1
}

[Environment]::SetEnvironmentVariable("OPENCODE_CONFIG", (Join-Path $dotfilesRoot "AI/OpenCode/opencode.json"), "User")
