# Skills

A collection of [Agent Skills](https://agentskills.io) — reusable instruction
packages that teach coding agents (Claude Code, Codex, Cursor, OpenCode, pi,
and [75+ more](https://github.com/vercel-labs/skills#supported-agents)) how to
perform specific workflows.

## Install

```bash
# Install all skills from this repo (interactive picker)
npx skills add sprilukin/skills

# Install a specific skill
npx skills add sprilukin/skills --skill git-ops

# Install everything, non-interactive, globally
npx skills add sprilukin/skills --all -g -y
```

Browse at [skills.sh/sprilukin/skills](https://skills.sh/sprilukin/skills).

## Skills

| Skill | Description |
| ----- | ----------- |
| [git-ops](skills/git-ops/) | Git & GitHub CLI operations — commits, branches, PRs. |
| [plan-feature](skills/plan-feature/) | Plan a feature and produce a GitHub ticket (not implement it). |
| [implement-ticket](skills/implement-ticket/) | Implement a GitHub ticket in user-gated mode via supervised delegation. |
| [implement-epic](skills/implement-epic/) | Implement a GitHub Epic via autonomous delegation of its sub-issues. |
| [implement-auto](skills/implement-auto/) | Autonomous worker for an Epic sub-ticket; commits, pushes, opens child PR. |
| [reviewer](skills/reviewer/) | Code review for bugs, security, performance, maintainability. Read-only. |
| [summarizer](skills/summarizer/) | Summarize file contents, diffs, or changes. Read-only. |
| [playwright-browser](skills/playwright-browser/) | Control and inspect browsers with the Playwright CLI. |

### Paseo editions

The `-paseo` variants of the planning/implementation skills are adapted for
[Paseo](https://paseo.app)-supervised delegation and require a running Paseo
workspace:

| Skill | Description |
| ----- | ----------- |
| [paseo-delegation](skills/paseo-delegation/) | Shared delegation protocol used by the `-paseo` skills. Not triggered directly. |
| [plan-feature-paseo](skills/plan-feature-paseo/) | Plan a feature and produce a GitHub ticket (Paseo edition). |
| [implement-ticket-paseo](skills/implement-ticket-paseo/) | Implement a GitHub ticket via Paseo-supervised delegation. |
| [implement-epic-paseo](skills/implement-epic-paseo/) | Implement a GitHub Epic via autonomous Paseo-supervised delegation. |
| [implement-auto-paseo](skills/implement-auto-paseo/) | Autonomous worker for an Epic sub-ticket (Paseo edition). |

## Layout

Each skill lives in its own directory under [`skills/`](skills/), containing a
`SKILL.md` with `name` / `description` frontmatter (the
[standard skill format](https://agentskills.io)). CI validates every skill on
push.