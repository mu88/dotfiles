# OpenCode setup

For OpenCode V2, run `AI/OpenCode/Configure.ps1` to register `opencode-v2.json` through `OPENCODE_CONFIG`. The repository-root setup also calls it; do not run the entire development-environment installer merely to migrate OpenCode.
Keep `MU88_DOTFILES` normalized to forward slashes using the root setup script.
V2 watches configuration and plugins; use `/reload` if necessary. Restart the shared service only to change its inherited environment or diagnose an unhealthy service.

## Windows Terminal and installation

- The normal profile uses `pwsh.exe -NoExit -Command opencode`. No OpenCode launcher script or PSMux is needed.
- PowerShell loads the existing profile, including optional GitHub MCP token initialization, before starting OpenCode.
- Until Chocolatey packages V2, set only the actual machine's WT command line to a direct invocation of its portable V2 executable. Do not copy a machine-specific executable path into this shared settings template.
- Standard config/data/state/cache directories are independent of how the executable is installed. Do not use `--standalone` for normal operation: clients share the built-in service.
- When changing installations, stop the old V2 service first, install the agreed V2 package, verify its executable version, then switch WT's invocation to the package's command. Keep user storage unchanged.
- A V1 Chocolatey shim may still precede the portable binary in PATH. Until it is replaced, do not invoke bare `opencode` against migrated V2 storage; use the explicit portable path.
- `opencode.json` is retained as the old V1 configuration. The V2 setup uses `opencode-v2.json`; do not point V1 at the latter.

## Skills and updates

`Scripts/InstallDevelopmentEnvironment.ps1` installs public skills into `~/.config/opencode/skills` using `gh skill install --agent opencode --scope user`. Copilot retains its own installations. Personal skills shared by both tools belong in `~/.agents/skills`.

For intentional updates, evaluate the `$dotnetSkillPackages` list and run only the block labeled `OpenCode skills`, not the Copilot loop or the entire development setup. The block selects upstream `main` explicitly because the current `gh skill update` can prefer older release tags.

## Configuration

- Copilot CLI and OpenCode share instructions from `AI/Shared/instructions` and RTK guidance from `AI/Shared/RTK/instructions`.
- The AI Loop & Merge agent uses `AI/Shared/mu88-ai-loop-and-merge.md`. Select it explicitly; it is not the default.
- Binlog MCP requires a suitable .NET SDK and NuGet access. V2 does not run LSP servers; `lsp: true` in the old V1 configuration is not an active V2 feature.
- Keep credentials and machine-specific configuration in `~/.config/opencode/opencode.jsonc`.
- RTK includes a temporary Windows worker `Path` fallback. Replace it with the upstream fix when released: https://github.com/rtk-ai/rtk/issues/4625.
- V2 loads RTK through `plugins/rtk/index.ts`, reusing the existing dual-V1/V2 implementation rather than duplicating it.
- The quota plugin is an npm reference; update through OpenCode's plugin management. Its machine-local display settings belong in `~/.config/opencode/opencode-quota/settings.jsonc`.
- The local native WT indicator belongs only in `~/.config/opencode/cli.json`'s `plugins` list; reference the directory `AI/OpenCode/plugins/status-indicator` in this checkout and set `terminal.title: false`. Its source/license/provenance are tracked here pending an upstream contribution.
- To use Windows Terminal tabs rather than OpenCode's inner session tabs, set `tabs.mode: "off"` in that same machine-local `cli.json`.

Check setup through `/models`, `/mcps`, `/quota_status` and the selected agent. Use the same V2 executable/environment as WT for CLI diagnostics; API/session commands may start a shared service.

## Local indicator checks

With Node.js 23.8+ available, run `node AI/OpenCode/tests/status-indicator.test.mjs` from the repository root. The offline checks use Node's built-in TypeScript stripping and synthetic events/timers; they never start OpenCode or access credentials. They do not replace the live Windows Terminal visual check.
