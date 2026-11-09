# Workstation desired-state checklist

Personal configuration for Windows and Linux Mint. `{checkout}` means the absolute path to the permanent dotfiles checkout. Existing settings remain valid; no setup orchestration script is needed.

## Working rule

- Read applicable repository instructions first. Inspect the machine; leave matching settings alone and correct only approved differences. Preserve unrelated settings; ask about ambiguities instead of inventing values.
- Obtain approval for installations, configuration changes, and service restarts. Never expose credentials, grant blanket test permissions, or commit/push without an explicit request.
- Report `MATCH`, `DIFFERENCE`, `BLOCKED`, or justified `N/A` in the session, not as permanent checkmarks here. Update this document when the desired configuration changes.

**Validation:** an inventory needs only read-only checks, without starting services or installing dependencies. After a change, check the affected setting. On first setup or integration changes, also test the affected path end to end: a signed dummy Git commit and invalid-message rejection; a safe model-driven command and automatic RTK rewriting; or the actual terminal behavior. Use real registry/runtime evidence, not just model claims. Test credential changes with an approved read-only authenticated request. Use temporary fixtures, never push test commits, and do not run the AI Loop & Merge workflow as a smoke test.

## 1. Checkout and tools

- Use one permanent checkout. Its path uses forward slashes, no trailing slash, and no commas (Copilot's directory-list separator).
- For components in use, resolve executables and versions: PowerShell 7, Git, GCM, Bitwarden with SSH agent, GitHub CLI, Copilot CLI, OpenCode V2, RTK. Verify V2 rather than assuming `opencode2` (Windows) or `opencode` (Linux) identifies it.
- `LOCAL_DEV_DIR` identifies the machine's development root for AI-created worktrees, not necessarily the checkout's parent.
- `Scripts/InstallDevelopmentEnvironment.ps1` and `Scripts/InstallDotNet.ps1` are separate Windows-only installation helpers; do not run them on Linux.

## 2. User environment

| Setting | Desired value |
| --- | --- |
| `MU88_DOTFILES` | `{checkout}` |
| `OPENCODE_CONFIG` | `{checkout}/AI/OpenCode/opencode.json` |
| `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | Include `{checkout}/AI/Shared/instructions` and `{checkout}/AI/Shared/RTK/instructions` exactly once; preserve other entries |
| `OPENCODE_CLI_CONFIG_CONTENT` | JSON contents of `AI/OpenCode/cli.json`; compare parsed JSON and review intentional overrides |

Windows persists user environment variables; Mint exports them from the login environment, currently `~/.profile`. Compare persisted and process values. Existing processes retain snapshots; refresh inline CLI JSON after source changes. Verify new shell/desktop launches after environment changes. Ordinary OpenCode config-file edits reload without restarting its service.

## 3. Git

| Desired state | Check |
| --- | --- |
| Shared configuration includes `{checkout}/Git/.gitconfig` | Inspect effective values and origins inside an intended repository |
| `core.hooksPath` points to `{checkout}/Git/hooks` | Resolve the hook; `commit-msg` must be executable on Linux and use LF |
| Personal GitHub identity comes from `Git/.gitconfig-github` under a directory named `GitHub` | Check identity/signing there; other roots need their approved machine-local conditional includes |
| Signing uses `~/.gitconfig-mu88-local` as below | Check effective `gpg.ssh.allowedSignersFile` and `gpg.ssh.defaultKeyCommand` |
| Bitwarden's native SSH agent is reachable | Check the socket and Git's selected SSH/signing executable according to Bitwarden's current documentation |
| GCM is in the helper chain; Linux uses `credential.credentialStore=secretservice` | Inspect helpers/store before configuring GCM; do not reset the chain blindly |
| Line-ending policy is machine-local | Inspect `core.autocrlf`; do not introduce a shared `core.autocrlf=true` |

Inspect `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n` too: existing Windows environment registrations remain valid. New machines can use normal user Git includes and hook settings instead. The shared GitHub include loads the local signing file; other identities must load the signing settings they need.

### Local signing file examples

Contents of `~/.gitconfig-mu88-local`, not shell commands. Replace the example paths and merge with existing content. Windows backslashes before quotes are intentional: the helper-path quotes must survive Git's config parser.

**Windows:**

```gitconfig
[gpg "ssh"]
    allowedSignersFile = "D:/path with spaces/dotfiles/Git/.ssh/allowedSigners"
    defaultKeyCommand = pwsh -NoProfile -File \"D:/path with spaces/dotfiles/Git/Get-GitSigningKey.ps1\"
```

**Linux:**

```gitconfig
[gpg "ssh"]
    allowedSignersFile = "/absolute/path with spaces/dotfiles/Git/.ssh/allowedSigners"
    defaultKeyCommand = pwsh -NoProfile -File '/absolute/path with spaces/dotfiles/Git/Get-GitSigningKey.ps1'
```

## 4. Copilot CLI

Paths below are relative to `COPILOT_HOME`, or `~/.copilot` when unset.

| Desired state | Check |
| --- | --- |
| Shared instructions from section 2, including `rtk.instructions.md`, are enabled | `copilot instruction list --json`: inspect sources and disabled status |
| `agents` links to `{checkout}/AI/GitHub Copilot/agents` (Windows junction / Linux symlink) | Resolve the link and check the actual agent selection |
| `hooks/rtk-rewrite.json` is a file symlink to `{checkout}/AI/GitHub Copilot/RTK/hooks/rtk-rewrite.json` | Resolve the link and read its hook command |
| `{checkout}/AI/Shared/skills` is registered and enabled | `copilot skill list --json`; use `copilot skill add` only for a missing registration |

Preserve personal instructions, agents, skills, and hooks; review existing directories before replacing them with links.

## 5. OpenCode V2

| Desired state | Check |
| --- | --- |
| Shared `opencode.json` supplies instructions, skills, the custom agent, RTK, quota, and Binlog MCP | Inspect config sources and actual registries/status; do not duplicate definitions locally |
| Machine-specific settings stay in the user config directory (`~/.config/opencode` or the existing `XDG_CONFIG_HOME` location) | Inspect relevant settings; use supported credential storage for credentials |
| Windows Terminal's local `cli.json` registers `{checkout}/AI/OpenCode/plugins/status-indicator` and sets `terminal.title` to `false` | Inspect these fields; verify the real TUI title after changes |

Binlog MCP needs a suitable .NET SDK and NuGet access. Inline CLI JSON merges over local settings without replacing the local plugin list. See [OpenCode operation](AI/OpenCode/README.md) for runtime details.

## 6. PowerShell and Windows Terminal

| Desired state | Check |
| --- | --- |
| PowerShell 7 `$PROFILE` loads the shared profile; `posh-git`, `PSReadLine`, `Terminal-Icons`, and native Oh My Posh are available | Inspect the profile entry and dependencies on each platform; add the snippet below once |
| The profile runs in interactive terminals: Windows Terminal on Windows, normal terminals on Linux | Verify a fresh terminal; redirected and `-NonInteractive` calls skip customization |
| The terminal uses a Nerd Font for prompt and file icons | Check actual rendering; installed modules alone do not prove terminal compatibility |
| Windows with PSMux sets `PSMUX_CONFIG_FILE` to `{checkout}/WindowsTerminal/psmux.conf` | Compare the variable/path; review `WindowsTerminal/settings.json` rather than replacing local settings wholesale |

PowerShell profile entry on either platform:

```powershell
if ($env:MU88_DOTFILES) {
    & (Join-Path $env:MU88_DOTFILES 'PowerShell/Microsoft.PowerShell_profile.ps1')
}
```

## 7. SOFA credentials

| Desired state | Check |
| --- | --- |
| Windows uses PowerShell 7, `CredentialManager`, and an entry named `SOFA_API_KEY` | Check availability/entry metadata without exposing the secret |
| Linux uses `secret-tool` (`libsecret-tools`), an unlocked Secret Service keyring, and attributes `application sofa credential api-key` | Check tools/service and entry metadata, not secret values |

For approved Linux key storage, run this in a terminal and enter the key at its password prompt. A matching entry is replaced; review existing metadata first. Onboarding requires approval.

```sh
secret-tool store --label='SOFA API key' application sofa credential api-key
```

Follow `AI/Shared/skills/sofa/SKILL.md` for credential use; keep lookup and request in the same process without logging the key. Inventories need no secret lookup or authenticated request.
