# Workstation setup

Windows and Linux Mint. `{checkout}` is the absolute path to the permanent dotfiles checkout, using forward slashes, no trailing slash and no commas.

## Environment

| Variable | Value |
| --- | --- |
| `MU88_DOTFILES` | `{checkout}` |
| `LOCAL_DEV_DIR` | Machine-specific development root for AI worktrees and shared skills |
| `OPENCODE_CONFIG_DIR` | `{checkout}/AI/OpenCode` |
| `OPENCODE_CONFIG` | Unset by default; optionally points to one additional machine-local OpenCode config file |
| `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | Include `{checkout}/AI/Shared/instructions` and `{checkout}/AI/Shared/RTK/instructions` exactly once; preserve other entries |
| `OPENCODE_CLI_CONFIG_CONTENT` | Inline JSON for machine-local CLI overrides, e.g. `{"session":{"permissions":"autoaccept"}}` |

Windows uses user environment variables; Mint uses `~/.profile`. Terminals launching non-login shells must supply these variables too. Running processes retain their environment.

## Git

Register through user Git config or equivalent `GIT_CONFIG_*` environment settings:

```gitconfig
[include]
    path = "{checkout}/Git/.gitconfig"
[core]
    hooksPath = "{checkout}/Git/hooks"
```

Personal identity applies below directories named `GitHub`; other identities need local conditional includes. Bitwarden's SSH agent supplies signing. Local `~/.gitconfig-mu88-local`:

```gitconfig
[gpg "ssh"]
    allowedSignersFile = "{checkout}/Git/.ssh/allowedSigners"
    defaultKeyCommand = pwsh -NoProfile -File \"{checkout}/Git/Get-GitSigningKey.ps1\"
```

Keep line-ending policy local. Git Credential Manager uses Secret Service on Linux (`credential.credentialStore=secretservice`). The `commit-msg` hook needs executable permission on Linux and LF endings.

## Copilot CLI

Paths are relative to `COPILOT_HOME`, or `~/.copilot` when unset:

- Link `agents` to `{checkout}/AI/GitHub Copilot/agents` (Windows junction / Linux symlink).
- File-symlink `hooks/rtk-rewrite.json` to `{checkout}/AI/GitHub Copilot/RTK/hooks/rtk-rewrite.json`; RTK must be on `PATH`.
- Register shared skills: `copilot skill add "{checkout}/AI/Shared/skills"`.

## OpenCode V2

The environment selects `AI/OpenCode`; no links are needed. Local CLI overrides use inline JSON, not another file. RTK must be on `PATH`; Binlog MCP requires .NET and NuGet access. Credentials and runtime data remain local.

## Shared AI skills

Common third-party skills directory: `$env:LOCAL_DEV_DIR/AI/skills`.

- **OpenCode**: Configured via the `skills` entry in `AI/OpenCode/opencode.json`.
- **Copilot CLI**: Register via `copilot skill add "$env:LOCAL_DEV_DIR/AI/skills"`. To let shared skills take precedence over bundled plugin copies without disabling plugin agents, MCP servers, or LSP, exclude plugin skill discovery:
  ```powershell
  $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
  copilot config ignoredSkillsLocations (Join-Path $copilotHome 'installed-plugins/dotnet-agent-skills')
  ```
  Other marketplaces can be excluded analogously.
- **Updates**: Follow `main`, not tagged releases. Re-run only the shared skill installation block in `Scripts/InstallDevelopmentEnvironment.ps1`, with its shared-directory and package-list declarations; do not run the complete workstation installer to update skills. For an individual skill, use `gh skill install` with its repository path suffixed by `@main`, `--dir "$env:LOCAL_DEV_DIR/AI/skills"`, and `--force`. An unqualified `gh skill update` can select an older tagged release.

## PowerShell and Windows Terminal

Requires PowerShell 7, `posh-git`, `PSReadLine`, `Terminal-Icons`, native Oh My Posh and a Nerd Font. Add to `$PROFILE`:

```powershell
if ($env:MU88_DOTFILES) {
    & (Join-Path $env:MU88_DOTFILES 'PowerShell/Microsoft.PowerShell_profile.ps1')
}
```

The profile runs in interactive terminals; on Windows it requires Windows Terminal or WezTerm. Use `WindowsTerminal/settings.json` for personal profiles. Windows with PSMux sets `PSMUX_CONFIG_FILE` to `{checkout}/WindowsTerminal/psmux.conf`.

WezTerm loads `{checkout}/WezTerm/wezterm.lua`; `WEZTERM_JSON_PROFILE_SOURCES` lists JSON profile files separated by semicolons. See [WezTerm/README.md](WezTerm/README.md).

## SOFA

Credential setup and use: [AI/Shared/skills/sofa/SKILL.md](AI/Shared/skills/sofa/SKILL.md).

## Checks

- Git: `git config --show-origin --get-regexp '^(include|core.hooksPath|user\.|gpg\.)'` inside a personal repository.
- Copilot: `copilot instruction list --json` and `copilot skill list --json`.
- OpenCode: `opencode debug paths config`, `/models` and `/mcps` (use the verified V2 executable).
