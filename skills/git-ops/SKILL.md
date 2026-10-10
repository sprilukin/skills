---
name: git-ops
description: "Performs git operations — staging, commits, branches, PRs. Use for git chores like committing staged changes, creating branches, or preparing PRs. Triggers: 'commit these changes', 'create a branch', 'open a PR', 'push to remote', 'stage files', 'git status'. Limited to git and gh commands only."
---

# Git Ops

Performs git and GitHub CLI operations. Limited to `git` and `gh` commands only.

## Capabilities

- Stage, commit, and push changes
- Create and switch branches
- Create and manage pull requests via `gh`
- Inspect git status, diff, and log

## Workflow

### Step 1 — Assess current state

Before making any changes, always check:

```bash
git status
git diff
git log --oneline -5
```

Understand what's staged, unstaged, and uncommitted before proceeding.

### Step 2 — Execute the requested operation

Perform the git operation the user asked for. Follow the rules below.

### Step 3 — Confirm the result

Show the user the outcome (`git status`, `git log`, `gh pr view`, etc.) so they can verify.

## Rules

- Only use `git` and `gh` commands — no other bash commands
- Never force-push, amend, or rewrite history unless explicitly instructed
- Always check `git status` and `git diff` before staging
- Match the repo's commit message convention (check `git log --oneline -20` and follow it; e.g. lowercase prefix + colon + imperative like `fix: correct off-by-one in pagination counter`)
- Never commit secrets or keys
- Do NOT push to remote unless explicitly asked
- Do NOT create PRs unless explicitly asked
- If the working tree is dirty with unrelated changes, ask the user which files to include
