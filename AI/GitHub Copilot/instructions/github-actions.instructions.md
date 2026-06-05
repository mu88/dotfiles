---
applyTo: "**/.github/**/*.{yaml,yml}"
---
# GitHub Actions Guidelines

## Output and Summary

- Always use `>>` to append to `$env:GITHUB_OUTPUT` and `$env:GITHUB_STEP_SUMMARY`. Do not use `Add-Content` for these variables:
  ```powershell
  "key=value" >> $env:GITHUB_OUTPUT
  "## Summary" >> $env:GITHUB_STEP_SUMMARY
  ```
- For bash steps: `echo "key=value" >> "$GITHUB_OUTPUT"` and `echo "## Summary" >> "$GITHUB_STEP_SUMMARY"`.

## Annotations

- Emit annotations via `Write-Host` (PowerShell) or `echo` (bash):
  ```powershell
  Write-Host "::warning title=<title>::<message>"
  Write-Host "::error title=<title>::<message>"
  Write-Host "::notice title=<title>::<message>"
  ```
- Use `::group::`/`::endgroup::` to collapse noisy output (API responses, installs, loops):
  ```powershell
  Write-Host "::group::Fetching repo list"
  # ... verbose output ...
  Write-Host "::endgroup::"
  ```

## Action Pinning

- Pin ALL actions — including GitHub-owned (`actions/*`) — to a full commit SHA, not a mutable tag. The only exception is actions you own in the same repository:
  ```yaml
  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
  ```

## Testing Workflows on Feature Branches

- `workflow_dispatch` only works on the **default branch**. To test on a feature branch, add a temporary `push` trigger — **NEVER EVER** push to default branch without user consent (real notifications, prod deploys, etc.):
  ```yaml
  on:
    push:
      branches:
        - feature/my-branch  # temporary — remove before merging
    workflow_dispatch:
      # ...
  ```
- To avoid unintended side effects, detect push event and force safe defaults:
  ```powershell
  $dryRun = '${{ inputs.dry_run }}' -eq 'true' -or '${{ github.event_name }}' -eq 'push'
  ```
- Or skip jobs via YAML condition:
  ```yaml
  if: github.event_name != 'push' && inputs.dry_run != true
  ```
- Remove the `push` trigger and push-specific overrides before merging.
