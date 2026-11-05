# Linux Mint setup and acceptance checklist

Use this checklist to set up and verify this branch on the actual Linux Mint machine. WSL results are useful background, not proof that Mint works. Complete the steps in order and record `PASS`, `FAIL`, `BLOCKED`, or `N/A` for each check; include the reason for anything other than `PASS`.

## Working agreement

- [ ] Verify that this is the intended dotfiles checkout and branch, `feature/ai-git-hook-linux`. Inspect `git status --short --branch` and the latest commit. If the branch is unavailable, stop and report that it must first be made available on this machine; do not silently use `main` or another checkout.
- [ ] Preserve existing work and configuration. Before changing the real Git or user configuration, inspect it and obtain explicit approval. Group required installation approvals rather than asking separately for every command. Do not install tools, change Git config, commit, or push without authorization.
- [ ] Do not print or log tokens, private keys, SOFA keys, session transcripts, or complete credential-bearing configuration. Never put secrets in command arguments or chat. Use temporary directories and dummy data for tests; delete only test data created for this checklist.
- [ ] Do not replace existing settings, links, hook paths, SSH-agent configuration, or keyring entries without reviewing the conflict with the user. Report a blocker rather than bypassing signing or permissions.

## 1. Machine and prerequisites

- [ ] Confirm the Mint version, desktop/session type, and chosen canonical dotfiles checkout. Confirm that Git and PowerShell 7 (`pwsh`) are available and that the checkout path contains no comma.
- [ ] Identify the actual executables and versions of Git Credential Manager (GCM), Bitwarden, Copilot CLI, OpenCode **V2**, and RTK. RTK must be on `PATH`: the AI setup intentionally stops when it is missing. Obtain approval before installing any missing tool; do not assume Windows installations are available on Mint.
- [ ] Verify that GNOME Keyring or another Secret Service provider is available in the user's session. For SOFA, also check whether `secret-tool` is available. Do not assume the WSL setup or its credentials exist on Mint.
- [ ] Determine the user's intended GitHub and, if used, Gitea repository locations and identities. The shared GitHub include matches paths under a directory named `GitHub`; Gitea requires an appropriate machine-local conditional include and identity. Do not guess or print personal identity details.

## 2. Inspect and preview

- [ ] Inspect existing Git includes, conditional includes, effective `core.hooksPath`, credential helpers, `GIT_CONFIG_GLOBAL`, and relevant `GIT_CONFIG_COUNT` entries. Check whether `~/.gitconfig-mu88-local` already exists. Preserve existing settings and resolve conflicts before proceeding.
- [ ] Inspect `~/.profile`, Copilot's existing home, agents, hooks, and settings, plus OpenCode's existing configuration and service. Check whether the desktop/session and intended login shells actually read `~/.profile`.
- [ ] From the canonical checkout, run `pwsh -NoProfile -File ./Configure.ps1 -WhatIf`. Verify that it previews the Git, AI, and Windows Terminal setup without creating or changing files or persistent settings. Missing RTK or a configuration conflict is a blocker, not a reason to bypass the checks.
- [ ] Review the preview and obtain approval for the real changes. Run `pwsh -NoProfile -File ./Configure.ps1` only after approval. Keep the checkout in place: the Git hooks, signing helper, AI settings, and agent links refer to it.
- [ ] Run the setup again and verify it preserves existing content, does not duplicate its profile blocks or includes, and leaves unrelated configuration intact. Review any warnings instead of assuming they are harmless.

## 3. Git credentials, identities, hook, and signing

- [ ] Inspect the effective credential-helper chain before configuring GCM. Set up GCM with the Secret Service credential store for this Linux user only after approval; do not blindly run a command that resets existing helpers. Verify access to a user-approved **private** GitHub repository over HTTPS without printing credentials or embedding them in the URL. Confirm a subsequent access uses the stored credential; verify persistence after a user-approved keyring/session restart.
- [ ] Verify that the GitHub identity and SSH-signing settings are effective in a repository beneath `GitHub`. If Gitea is used, separately verify its machine-local include and intended identity. In an isolated temporary Git configuration with no name or email, check that `user.useConfigOnly` prevents a commit; do not change the real identity or disable that safeguard.
- [ ] Configure and unlock the **native Linux Bitwarden SSH agent** according to Bitwarden's current documentation. Verify that the active session exposes its socket and the expected public signing identity without displaying private material. The temporary Windows-to-WSL bridge is not a Mint setup.
- [ ] In a newly created disposable repository beneath a temporary `GitHub` directory, create a local Conventional Commit using the configured identity and agent. Confirm Bitwarden approval if requested and verify the resulting signature locally with `git verify-commit` and `%G?` (`G` means valid and trusted). A local verification does not by itself prove GitHub will show `Verified`.
- [ ] In the same disposable repository, attempt an invalid commit message and confirm the commit-message hook rejects it without creating a commit. Do not bypass the hook. Do not push the test repository.

## 4. Login environment and AI tools

- [ ] Coordinate a fresh login session with the user so active work is not interrupted. From PowerShell and at least one other intended shell, verify that `MU88_DOTFILES`, `OPENCODE_CONFIG`, and `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` point to the canonical checkout and include the shared and RTK instruction directories without duplicates. Verify a graphical terminal or desktop launch separately; a successful login-shell test does not prove desktop inheritance.
- [ ] Use the real Copilot CLI to verify that shared instructions, `rtk.instructions.md`, shared skills, and the custom agent are discovered from the intended checkout. Confirm existing personal instructions remain available. A successful setup command alone is not evidence that the CLI loaded the files.
- [ ] Verify the installed Copilot RTK hook points to this checkout. Test `rtk hook copilot` with synthetic non-secret input, then confirm a real Copilot session invokes the hook and rewrites a safe command. Distinguish a direct hook test from end-to-end agent behavior; do not run the AI Loop & Merge workflow or push anything as a smoke test.
- [ ] Verify OpenCode V2 loads the intended configuration, shared instructions, shared skills, custom agent, and local RTK plugin. Confirm an actual session invokes the RTK integration for a safe command. Check the managed service's environment: an already-running service may retain old variables. Do not stop or restart an active service without the user's approval.
- [ ] Check the configured quota plugin and Binlog MCP with the real environment. Obtain approval before any automatic or manual plugin/tool installation; record missing dependencies or unavailable network access as `BLOCKED`, not as a pass. Do not claim a plugin or MCP was tested if it was disabled in a fixture.
- [ ] Exercise the `resume-session-finder` against a user-approved local session without revealing transcript contents. Verify it respects `COPILOT_HOME` and resolves the actual OpenCode V2 executable when applicable.

## 5. SOFA Secret Service

- [ ] Check that `secret-tool` and an unlocked Secret Service keyring are available. If absent, report the prerequisite and obtain approval before installation or configuration.
- [ ] Check for an existing SOFA keyring entry before storing anything. With explicit user approval, follow the interactive `secret-tool store` instructions in `AI/README.md`; the user enters the key at the terminal prompt, never in chat or command arguments. The documented attributes can replace a matching entry.
- [ ] Test the SOFA skill with a read-only authenticated request. Perform the key lookup and request in the same process, without exposing the key in command output, logs, arguments, or files. If credentials, network access, or approval are missing, mark this `BLOCKED`.

## Acceptance

- [ ] Report results for each section, including tool versions, what was actually tested, and any `FAIL`, `BLOCKED`, or user-approved `N/A` items. Distinguish isolated tests from real-session and graphical-session evidence.
- [ ] Classify the requested setup as **works** only when every applicable check passes. If the user excludes a component, name that exclusion explicitly; never turn an untested component into a pass.
- [ ] Remove temporary test repositories and files created for this checklist. Do not alter unrelated work, commit, push, or discard anything without explicit authorization.
