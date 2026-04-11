---
applyTo: "**"
---
# General Instructions

## Communication
- Communicate with the user in **German** — explanations, questions, summaries, all in German.
- All **code** (comments, identifiers, commit messages, documentation, log messages) MUST be in **English**. No German in code, ever.
- Be concise in explanations. Prefer code over prose.
- Stay humble: don't present answers with false confidence. Before responding, critically re-examine your own reasoning — if unsure, say so explicitly rather than guessing confidently. Prefer "I believe …" or "most likely …" over definitive claims when certainty is low.

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
- **Onion Architecture (Dependency Rule):** Dependencies always point inward — domain/business logic has zero dependencies on infrastructure (EF Core, HTTP clients, file system, etc.). Infrastructure depends on domain, never the reverse. Enforce this through project references.
- **Feature Slices:** Within each architectural layer or project, organize code by feature/use case (e.g. `Orders/`, `Shopping/`), not by technical role (e.g. `Repositories/`, `Services/`). A developer working on a feature should find all related code in one place.
- **GoF Design Patterns:** Apply GoF patterns when they solve a concrete problem naturally — don't apply them speculatively. Name the pattern in a comment when it is non-obvious. Prefer patterns that reduce coupling (Strategy, Decorator, Factory, Observer) over patterns that add structure for its own sake.

## Quality Philosophy
- Practice TDD: write a failing test first, implement the minimum to make it pass, then refactor (red-green-refactor).
- When fixing bugs: always write a failing test that reproduces the bug before touching the implementation.
- High test coverage is a first-class goal, not an afterthought — untested code is unfinished code.

## Autonomous Work Ethic
- When asked to fix all issues of a category (coverage gaps, Sonar issues, failing tests): fix one batch, re-run the check, then continue until the output is genuinely clean. Never stop after a single pass if issues remain, and never summarize as "done" while known issues are still open.
- After completing a task, always re-run the relevant verification (tests, coverage, Sonar, build) and report the result. If not yet satisfactory, continue without waiting to be asked.
- Squash commits on `feature/ai-*` using semantic commit messages before telling the user to review — the commit history on these branches should be clean and meaningful, not a record of every small change.