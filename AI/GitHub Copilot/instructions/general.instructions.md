---
applyTo: "**"
---
# General Instructions

## Mandatory Instructions
- **NEVER touch the Git config** (globally or per-repo) without explicit user consent. This includes `user.name`, `user.email`, `core.sshCommand`, credential helpers, and `gpg` settings.
- **NEVER commit to or push `main`/`master` directly.** Always work on a feature branch.
- **NEVER install tools or plugins without explicit user consent.** This includes linters, formatters, Python, PowerShell, Node.js, .NET, and any extensions. Always ask first.
- **During interactive sessions:** leave changes uncommitted for user review unless explicitly asked to commit.
- **On `feature/ai-*` branches (autonomous work):** always use a dedicated Git worktree for your work and clean it up (i.e. remove) after you're done. Commit with `--no-gpg-sign` (these branches are exempt from the signed-commits policy; signing will fail without a configured key). Amend/force-push commits when a change belongs to a previous commit semantically. Squash to clean, semantic commits before handing off for review.
- Commit messages follow **Conventional Commits**. The body MUST EXPLAIN **why** — the diff shows what and how. Body: 2–3 lines max, no bullet lists, no file inventories. If the "why" is unclear, ask rather than pad the message. The same rules MUST be followed for PR descriptions.

## Workspace & Tools
- When it comes to Git commit signing, Bitwarden's SSH agent is the only supported option.
- Before concluding that `gh` cannot perform a GitHub operation, check whether `gh api` with the appropriate REST endpoint or GraphQL mutation can achieve it. `gh <command>` covers only common operations; the full API surface is accessible via `gh api`.
  - Example: `gh pr comment` only creates top-level PR comments. Replying to a review thread requires `gh api .../pulls/comments/{id}/replies`; resolving a thread requires a GraphQL mutation (`resolveReviewThread`).

Always check whether a Git repo already exists locally before cloning. If it does, use the existing local copy instead of cloning again and pull the latest changes.

When working with Git worktrees, you MUST make sure to place them in the separate directory `__worktrees__` under the Git root directory (e.g. `D:\work\GitHubEnterprise\__worktrees__`) to avoid messing with the Git root directory specific Git configuration. For example, `D:\work\GitHubEnterprise` uses a different Git account than `D:\work\GitHub`, so worktrees for GitHub repos MUST NOT be created under `D:\work\GitHubEnterprise` to avoid accidentally inheriting the wrong Git configuration. Always check for existing worktrees before creating a new one, and always clean up (i.e. remove) worktrees after you're done with them.

### Pull Requests & Code Reviews
- When filing PRs, also check for existing PR templates and incorporate them if present, together with the above rules. Also ensure that the PR descriptions are properly formatted, e.g. contain no escaping issues. After filing the PR, verify that the description appears as intended on GitHub and edit if necessary to fix formatting issues.
- As long as your filed PRs are still in draft status, always make sure that you're up to date with the base branch (e.g. `main`) by regularly rebasing on the latest commits from the base branch.
- Do not mention edited files in the PR description if they are not relevant to the reviewer's focus - the diff itself shows what files are changed.
- **Markdown bodies for `gh` commands (PR/issue descriptions, comments):** ALWAYS write the body to a temp file and pass it via `--body-file`. Never pass Markdown directly as a string argument — backticks, newlines, and special characters in Markdown routinely cause silent corruption in PowerShell string handling. Pattern:
  ```powershell
  $body = @'
  ...markdown content...
  '@   # ALWAYS use single-quoted @'...'@ — double-quoted @"..."@ interprets backticks as
       # escape sequences (`r → CR, `n → LF), which corrupts triple backticks in code fences.

  $bodyFile = [System.IO.Path]::GetTempFileName()
  try {
      Set-Content -Path $bodyFile -Value $body -Encoding utf8NoBOM
      gh pr create --body-file $bodyFile ...
  } finally {
      Remove-Item -Path $bodyFile -ErrorAction SilentlyContinue
  }
  ```
  This applies to `gh pr create`, `gh pr edit`, `gh issue create`, `gh issue edit`, `gh pr comment`, `gh issue comment`, and any other `gh` command that accepts a body/message.
- **Angle brackets in Markdown bodies:** GitHub's API strips `<word>` patterns (e.g. `<sha>`, `<tag>`) even inside fenced code blocks. Use `&lt;` / `&gt;` for literal angle brackets, or avoid `<placeholder>` style entirely and use `{placeholder}` instead.
- **Dynamic content in bodies:** `@'...'@` does not expand variables. If the body needs dynamic content, build it via string concatenation — do NOT switch to `@"..."@` just to get variable expansion, as that re-introduces the backtick corruption problem.
  ```powershell
  $body = @'
  PR for branch: '@ + $branchName + @'
  See: '@ + $url
  ```

## Communication
- Communicate with the user in **German** — explanations, questions, summaries, all in German.
- All **code** (comments, identifiers, commit messages, documentation, log messages) MUST be in **English**. No German in code, ever.
- Be concise in explanations. Prefer code over prose.
- Stay humble: don't present answers with false confidence. Before responding, critically re-examine your own reasoning — if unsure, say so explicitly rather than guessing confidently. Prefer "I believe …" or "most likely …" over definitive claims when certainty is low.
- When reviewing code: verify claims about existing code (config values, replica counts, feature flags, etc.) by loading the relevant files before raising concerns. "Typically" or "usually" is not a valid source — check the actual state.

## Code Quality
- Use descriptive names for lambda parameters (`article`, `preference`, `unit`), never single-letter (`x`, `a`, `p`).
- Prefer the simplest solution that correctly solves the problem — avoid over-engineering and unnecessary abstractions.
- No git commits during implementation sessions — leave changes uncommitted for review.
- NEVER commit to or push the default branch directly — all autonomous work happens on feature branches only.
- NEVER modify git configuration (`git config`, `.gitconfig`, `gpg` settings, etc.) without the user's explicit confirmation.
- When making commits autonomously on `feature/ai-*` branches, always pass `--no-gpg-sign` to `git commit` — these branches are exempt from the signed-commits branch protection rule, and signing will fail without a configured key.
- Commit messages follow **Conventional Commits**. The body explains **why** the change was made, not how — the diff speaks for itself. Keep the body short (2–3 lines max), no essays.

## Architecture
- **Clean Code:** Every function/method does one thing (Single Responsibility). Functions that grow beyond ~20 lines are a signal to extract. Avoid side effects in query methods (Command-Query Separation).
- **Layered Architecture (Dependency Rule):** Dependencies always point inward — domain/business logic has zero dependencies on infrastructure (databases, HTTP clients, file system, etc.). Infrastructure depends on domain, never the reverse.
- **Feature Slices:** Within each architectural layer or project, organize code by feature/use case (e.g. `Orders/`, `Shopping/`), not by technical role (e.g. `Repositories/`, `Services/`). A developer working on a feature should find all related code in one place.
- **GoF Design Patterns:** Apply GoF patterns when they solve a concrete problem naturally — don't apply them speculatively. Name the pattern in a comment when it is non-obvious. Prefer patterns that reduce coupling (Strategy, Decorator, Factory, Observer) over patterns that add structure for its own sake.

## Quality Philosophy
- Practice TDD: write a failing test first, implement the minimum to make it pass, then refactor (red-green-refactor).
- When fixing bugs: always write a failing test that reproduces the bug before touching the implementation.
- High test coverage is a first-class goal, not an afterthought — untested code is unfinished code.

## Autonomous Work Ethic
- When asked to fix all issues of a category (coverage gaps, Sonar issues, failing tests): fix one batch, re-run the check, then continue until the output is genuinely clean. Never stop after a single pass if issues remain, and never summarize as "done" while known issues are still open.
- After completing a task, always re-run the relevant verification (tests, coverage, Sonar, build) and report the result. If not yet satisfactory, continue without waiting to be asked.
