# OpenCode setup

Run the repository-root `Configure.ps1` to configure both AI hosts, or `AI/OpenCode/Configure.ps1` to register only OpenCode through `OPENCODE_CONFIG`.
Keep `MU88_DOTFILES` normalized to forward slashes using the root setup script.
Restart OpenCode after changing configuration, plugins, agents, or skills.

## Skills and updates

`Scripts/InstallDevelopmentEnvironment.ps1` installs public skills into `~/.config/opencode/skills` using `gh skill install --agent opencode --scope user`. Copilot retains its own installations. Personal skills shared by both tools belong in `~/.agents/skills`.

For intentional updates, evaluate the `$dotnetSkillPackages` list and run only the block labeled `OpenCode skills`, not the Copilot loop or the entire development setup. The block selects upstream `main` explicitly because the current `gh skill update` can prefer older release tags.

## Configuration

- The AI Loop & Merge agent uses `AI/Shared/mu88-ai-loop-and-merge.md`. Select it explicitly; it is not the default.
- Native LSP and Binlog MCP are enabled. They require a suitable .NET SDK and NuGet access; OpenCode can install Roslyn on first use.
- Keep credentials and machine-specific configuration in `~/.config/opencode/opencode.jsonc`.
- RTK includes a temporary Windows worker `Path` fallback. Replace it with the upstream fix when released: https://github.com/rtk-ai/rtk/issues/4625.

Check setup with `opencode debug skill`, `opencode debug agent mu88-ai-loop-and-merge`, and `opencode mcp list`.
