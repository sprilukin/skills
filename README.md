# Skills

A collection of [Agent Skills](https://agentskills.io) — reusable instruction
packages that teach coding agents (Claude Code, Codex, Cursor, OpenCode, pi,
and [75+ more](https://github.com/vercel-labs/skills#supported-agents)) how to
perform specific workflows.

## Install

```bash
# Install all skills from this repo (interactive picker)
npx skills add sprilukin/skills

# Install a specific skill by name
npx skills add sprilukin/skills --skill git-ops

# Install everything, non-interactive, globally
npx skills add sprilukin/skills --all -g -y

# Install only the general-purpose skills (full URL with subpath)
npx skills add https://github.com/sprilukin/skills/tree/main/skills/general-purpose

# Install only the SDLC skills (full URL with subpath)
npx skills add https://github.com/sprilukin/skills/tree/main/skills/agentic-sdlc

# Install a single skill from a category (direct path to the skill)
npx skills add https://github.com/sprilukin/skills/tree/main/skills/agentic-sdlc/plan-feature
```

Browse at [skills.sh/sprilukin/skills](https://skills.sh/sprilukin/skills).

Add `-g` to install globally (user directory instead of the current
project), and `-y` or `--all` to skip interactive prompts.

Note: subpath installs require the full `https://github.com/...` URL —
the `owner/repo` shorthand only supports the repo root.

## Skills

Skills are grouped into two categories:

**[`skills/general-purpose/`](skills/general-purpose/)** — everyday helpers:

| Skill | Description |
| ----- | ----------- |
| [git-ops](skills/general-purpose/git-ops/) | Git & GitHub CLI operations — commits, branches, PRs. |
| [reviewer](skills/general-purpose/reviewer/) | Code review for bugs, security, performance, maintainability. Read-only. |
| [summarizer](skills/general-purpose/summarizer/) | Summarize file contents, diffs, or changes. Read-only. |
| [playwright-browser](skills/general-purpose/playwright-browser/) | Control and inspect browsers with the Playwright CLI. |

**[`skills/agentic-sdlc/`](skills/agentic-sdlc/)** — SDLC workflows built on sub-agent delegation:

| Skill | Description |
| ----- | ----------- |
| [plan-feature](skills/agentic-sdlc/plan-feature/) | Plan a feature and produce a GitHub ticket (not implement it). |
| [implement-ticket](skills/agentic-sdlc/implement-ticket/) | Implement a GitHub ticket or epic via mandatory sub-agent delegation. Mode routing: direct mode (user-gated), epic coordinator ([epic.md](skills/agentic-sdlc/implement-ticket/epic.md)), autonomous sub-ticket worker ([autonomous.md](skills/agentic-sdlc/implement-ticket/autonomous.md)). |
| [worker-delegation](skills/agentic-sdlc/worker-delegation/) | Harness-agnostic sub-agent delegation protocol used by the SDLC skills. Not triggered directly. |

### Harness-agnostic SDLC skills

`plan-feature` and `implement-ticket` are harness-agnostic: they contain no
harness-specific mechanics. All sub-agent spawning, waiting, harvesting, and
recovery goes through [worker-delegation](skills/agentic-sdlc/worker-delegation/),
which detects the current harness and applies the matching recipe from its
`harness/` directory:

| Harness file | Environment |
| ------------ | ----------- |
| [harness/orca.md](skills/agentic-sdlc/worker-delegation/harness/orca.md) | [Orca](https://orca-app.dev) app with the `orca` CLI and orchestration. |
| [harness/paseo.md](skills/agentic-sdlc/worker-delegation/harness/paseo.md) | [Paseo](https://paseo.app) app with the Paseo MCP tools / `paseo` CLI. |
| [harness/native.md](skills/agentic-sdlc/worker-delegation/harness/native.md) | Harnesses with first-class native sub-agents (passthrough). |

Adding a new harness means adding one file under
`skills/agentic-sdlc/worker-delegation/harness/` — no changes to the SDLC
skills.

## Layout

Each skill lives in its own directory under a category folder in
[`skills/`](skills/), containing a `SKILL.md` with `name` / `description`
frontmatter (the [standard skill format](https://agentskills.io)). The
`skills` CLI discovers skills recursively, so the category nesting is
invisible when installing. CI validates every skill on push.