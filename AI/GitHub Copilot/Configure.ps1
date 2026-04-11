# Link ~/.copilot/instructions and ~/.copilot/agents to this dotfiles repo so there is a single source of truth.
# Re-run this script whenever a new subdirectory is added (e.g. skills).
# Workaround for https://github.com/github/copilot-cli/issues/1954 (XDG_CONFIG_HOME regression).
$dotfilesRoot = $env:MU88_DOTFILES
if (-not $dotfilesRoot) {
    Write-Error "MU88_DOTFILES environment variable is not set. Aborting."
    exit 1
}

$copilotHome  = "$env:USERPROFILE\.copilot"
$sourceBase   = "$dotfilesRoot\AI\GitHub Copilot"

foreach ($folder in @('instructions', 'agents')) {
    $target = "$copilotHome\$folder"
    $source = "$sourceBase\$folder"

    if (Test-Path $target) {
        $item = Get-Item $target
        if ($item.LinkType -eq 'Junction') {
            Write-Host "  ✓ $folder — junction already exists, skipping"
            continue
        }
        # Regular directory: remove it (files are already verified to be in the repo)
        Remove-Item $target -Recurse -Force
        Write-Host "  ✗ $folder — removed existing directory"
    }

    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "  ✓ $folder — junction created: $target → $source"
}

# Modernize .NET (based on https://devblogs.microsoft.com/dotnet/modernize-dotnet-anywhere-with-ghcp/)
copilot -i "/plugin marketplace add dotnet/modernize-dotnet"
copilot -i "/plugin install modernize-dotnet@modernize-dotnet-plugins"
