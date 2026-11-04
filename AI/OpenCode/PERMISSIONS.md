# Low-noise approvals for OpenCode V2

The shared `opencode.json` starts with **ask for every action** and adds a small,
explicit allowlist. Use `session.permissions: "prompt"` in the user's `cli.json`;
`autoaccept` or `--auto` automatically answers asks and defeats this distinction.

## Allowed without a prompt

- Built-in read, glob and grep tools for routine investigation. Recognizable sensitive
  read paths (environment files, keys, credential files and appsettings) ask again;
  `.env.example` is an explicit exception.
- Questions, skill loading and AI todo updates.
- Only the exact shell command forms in the shared config, including selected Git
  status/branch/root queries, version queries, and diffs with external diff/textconv
  helpers disabled. RTK equivalents are listed separately, never as `rtk *`.

Prefer the listed forms instead of asking for slightly different spellings or flags.
For example, use `git status --short` and `git diff --no-ext-diff --no-textconv --stat`.
Adding path arguments or other flags deliberately requires another review. The shell
scanner may normalize a resource differently; do not broaden patterns just to silence it.

## Still asks

- Every other shell command, including builds, tests, installation, Git mutations,
  container commands, process termination and arbitrary PowerShell scripts.
- File edits, access outside the active location/project boundary, delegation, network
  tools, Code Mode orchestration and MCP operations unless a narrower rule is added later.
- Unknown tools default to ask; no tool-name wildcard grants them future access.

This is intended for trusted local development repositories, not hostile repositories
or executables. Even Git inspection can invoke repository-configured helpers such as
filesystem monitors. These rules are not an OS sandbox or a data-loss-prevention system.

**Sensitive-read caveat:** the `read` exceptions do not censor grep results, Git diffs,
or secrets embedded in normal source files. Searching a trusted working directory can
still reveal sensitive content. Shell directory inference is best effort. Do not treat
an allowed command as proof that its output is safe to publish.

## Layers, saved approvals and updates

- Later matching permission rules win; agent/session rules, system policies and saved
  project approvals also affect the final decision. Explicit denies cannot be lifted
  by saved approvals. This config sets asks, not hard-deny policies.
- `Allow always` saves project-scoped patterns; review the proposed breadth before
  accepting. A saved approval can bypass an ask later. No saved approvals were present
  in the current work setup when this policy was introduced; other machines/projects
  may differ. The policy does not delete existing approvals.
- Keep machine-specific allowances outside this shared baseline. Add project-specific
  build/test recipes only after reviewing their scripts and external effects.
- If a prompt is redundant, inspect the action/resource that was checked and add only
  the smallest useful exception. Avoid `git *`, `gh api *`, `pwsh *`, `dotnet *` and
  `rtk *`. Changes apply live; no service restart is needed.

## Verification

Run `node AI/OpenCode/tests/permissions.test.mjs` with the same Node installation used
for the indicator tests. It uses unchanged matching/evaluation function excerpts from
OpenCode V2.2.1, with upstream license/provenance under `tests/fixtures/`.

The offline checks classify resources; **none of the sample commands executes**.
They cover exact allows, RTK equivalents, mutations, extra flags/redirection, sensitive
read paths, default asks, Windows normalization and ordered overrides. They are not an
end-to-end shell-parser test or a model of every plugin/system/session rule. On OpenCode
upgrades, review matching/parser changes rather than assuming this pinned reference is current.

Additionally, permission-only requests against the running V2.2.1 server confirmed
allow for ordinary reads and raw/RTK Git status, and ask for an unlisted option, a file
edit and `.env`. These requests did not execute a shell command or modify the test file.

AI-assisted with OpenCode.
