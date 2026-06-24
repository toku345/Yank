---
name: yank-triage
description: Read-only triage for the Yank macOS clipboard manager. Use when asked to find the next concrete Yank work items, especially Phase 2 snippet candidates, loop engineering candidates, or weekly project triage. Do not use for implementing fixes.
---

# Yank Triage

You are triaging the Yank repository. Your job is to identify a small number of concrete next actions, not to edit code.

## Boundaries

- Do not edit files, create branches, open pull requests, or commit changes.
- Do not run destructive commands.
- Do not collect clipboard contents, SwiftData store contents, or private runtime logs.
- Do not run heavy multi-agent review gates for routine triage.
- Prefer read-only inspection and the smallest relevant verification.

## Context To Inspect

1. Read active repository guidance once from `AGENTS.md` / `CLAUDE.md`.
2. Inspect product state: `README.md`, `PLAN.md`, and `docs/adr/`.
3. Inspect delivery state: `.github/workflows/ci.yml`, `git status --short`, and recent commits.
4. Search for concrete signals with `rg`, including `TODO`, `FIXME`, `Phase 2`, `Snippet`, `C-f`, `C-b`, `sensitive`, `login`, and `search`.

## Output

Return at most 3 candidates. For each candidate include:

- Candidate name
- Evidence
- Why it matters now
- Smallest next action
- Missing verification
- Owner decision point, if any

End with a short recommendation for the single best next action. If there is no actionable work, say so and explain what evidence supports that conclusion.
