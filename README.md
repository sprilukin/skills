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
| [implement-ticket](skills/implement-ticket/) | Implement a GitHub ticket or epic via mandatory sub-agent delegation. Mode routing: direct mode (user-gated), epic coordinator ([epic.md](skills/implement-ticket/epic.md)), autonomous sub-ticket worker ([autonomous.md](skills/implement-ticket/autonomous.md)). |
| [worker-delegation](skills/worker-delegation/) | Harness-agnostic sub-agent delegation protocol invoked by the SDLC skills before any dispatch. Also invoked directly when the user asks for a handoff. |
| [reviewer](skills/reviewer/) | Code review for bugs, security, performance, maintainability. Read-only. |
| [summarizer](skills/summarizer/) | Summarize file contents, diffs, or changes. Read-only. |
| [playwright-browser](skills/playwright-browser/) | Control and inspect browsers with the Playwright CLI. |

### Harness-agnostic SDLC skills

`plan-feature` and `implement-ticket` are harness-agnostic: they contain no
harness-specific mechanics. All sub-agent spawning, waiting, harvesting, and
recovery goes through [worker-delegation](skills/worker-delegation/), which
detects the current harness and applies the matching recipe from its
`harness/` directory:

| Harness file | Environment |
| ------------ | ----------- |
| [harness/orca.md](skills/worker-delegation/harness/orca.md) | [Orca](https://orca-app.dev) app with the `orca` CLI and orchestration. |
| [harness/paseo.md](skills/worker-delegation/harness/paseo.md) | [Paseo](https://paseo.app) app with the Paseo MCP tools / `paseo` CLI. |
| [harness/native.md](skills/worker-delegation/harness/native.md) | Harnesses with first-class native sub-agents (e.g. Claude Code's Agent tool); worker self-places its branch. |

Adding a new harness means adding one file under
`skills/worker-delegation/harness/` — no changes to the SDLC skills.

## Layout

Each skill lives in its own directory under [`skills/`](skills/), containing a
`SKILL.md` with `name` / `description` frontmatter (the
[standard skill format](https://agentskills.io)). CI validates every skill on
push.