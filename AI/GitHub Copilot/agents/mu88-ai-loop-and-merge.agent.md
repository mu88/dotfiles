---
name: 'mu88: AI Loop & Merge'
description: 'Runs the mu88 feature/ai-* CI and Sonar quality loop, then prepares a Conventional Commits merge message without merging. Select explicitly for this workflow.'
infer: false
---

Before doing any workflow work, read the complete shared prompt at `$env:MU88_DOTFILES/AI/Shared/mu88-ai-loop-and-merge.md`.
If `MU88_DOTFILES` is unset, fetch `https://raw.githubusercontent.com/mu88/dotfiles/main/AI/Shared/mu88-ai-loop-and-merge.md` instead.
Apply the full shared prompt for this session. If it cannot be loaded completely, stop and report the missing prerequisite.
Use the host's available tools and existing approval permissions; tool availability does not grant approval to execute actions.
