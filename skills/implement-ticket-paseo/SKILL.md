---
name: implement-ticket-paseo
description: "Use when the user wants to implement a GitHub ticket in normal, user-gated mode through mandatory Paseo-supervised delegation. Triggers: 'work on ticket via paseo', 'implement ticket with paseo', 'paseo implementation'. Use only for direct mode; never as an autonomous epic sub-ticket worker."
---

# Implement Ticket (Paseo edition)

Implement one GitHub ticket in **direct mode**. Pick a ticket by description
or from the latest open issues, execute its plan, and — once implementation,
verification, and review pass — commit, push the branch, create a PR, and
monitor its CI to success. Do not merge the PR or close the issue.

**Delegation protocol:** load and follow the `paseo-delegation` skill. It
owns dispatch mechanics, worker preflight, the wait/harvest discipline,
recovery, completion evidence, the PR description contract, and testing
obligations. This skill owns the WHAT: ticket selection, plan parsing, phase
order, and gates. In this skill the **coordinator is the supervisor role** of
that contract; it may run read-only checks and summarize, but must never
implement, explore, fix, or review delegated work inline.

If the Paseo daemon, the selected provider, or provider authentication is
unavailable, stop and tell the user what must be fixed. Never fall back to a
generic subagent, bare shell, raw terminal input, or inline work.

## Workflow

### Phase 0 — Discover project context

Read root `AGENTS.md`, `.agents/project.yaml` (authoritative for paths and
commands), applicable nested instructions, `README.md`, relevant `docs/`,
functional requirements (`openspec/specs/` when the ticket touches a
capability area), manifests, testing guidance, and migration/generated-code
guidance. Run `gh repo view --json nameWithOwner,defaultBranchRef,description`
and inspect the repository layout. Never read `.env*` files except
`.env.example`. If repository or GitHub discovery fails, stop and ask.

### Phase 1 — Select and parse the ticket

For a description, run `gh issue list --state open --limit 30 --search
"<description>"`, show the top matches, and ask the user to select one. With
no description, list five open issues and ask for a selection. Fetch the full
issue with `gh issue view <number> --json number,title,body,labels,url`.

For a structured `plan-feature` ticket, check if an OpenSpec change is
referenced (e.g. `openspec/changes/<change-name>/` or an active change
directory):

- If an OpenSpec change is present, inspect it with
  `openspec instructions apply --change "<change-name>" --json` to retrieve
  the task list, delta specs, design decisions, and context files.
- Parse `tasks.md` and delta specs (`specs/<capability>/spec.md`) to build the
  ordered implementation steps, verification requirements, and constraints for
  worker dispatches.
- If no OpenSpec change exists, extract the ordered implementation and
  verification plans directly from the issue body. Every `implementer`,
  `explore`, or `reviewer` assignment is a mandatory dispatch.
- If the ticket is unstructured, dispatch a read-only `explore` worker first,
  then propose a plan and obtain explicit user confirmation before
  implementation. Stop when Decision completeness is absent or unresolved
  choices/TBDs remain.

If the ticket lacks a **Decision completeness** declaration, or contains
unresolved questions, `TBD` values, pending choices, or user-directed
decisions, stop and ask the user to resolve them before continuing. Do not
dispatch implementation work around an unresolved product or technical
decision.

### Phase 2 — Branch and shared services

Confirm `git branch --show-current`; stop on `main`. Work only in the
existing active checkout (the coordinator's own workspace — direct mode does
not use worktree workspaces). Never create, archive, or delete worktree
workspaces in this skill, and stop if the current branch is `main`.

Before mutating shared infrastructure (databases, generated types, env),
check project guidance for coordination rules; if none, ask the user how to
coordinate.

### Phase 3 — Execute through Paseo

Confirm the daemon (`paseo status` — implicit when the Paseo MCP tools
respond) and run the provider preflight from the
`paseo-delegation` skill (default provider `pi`, unless the user explicitly
selects another). The preflight includes the **model-default gate**: if the
coordinator's own model does not match the configured sub-agent default in
`~/.paseo/config.json` (including a `REQUIRED_MODEL` pin when the invocation
prompt carries one), stop before proceeding with the next steps — dispatched
workers would otherwise resolve to that config default. Then dispatch every
plan step through the
`paseo-delegation` contract — MCP-first dispatch via `create_agent`, task
spec template, batching, parallel rules,
titles, wait/harvest discipline, recovery — as follows:

- A code-changing plan step with no role is an `implementer` step. Every
  implementation, exploration, review, and verification-failure fix must be
  dispatched.
- **Reviewer and explorer workers receive `MAY modify files: no`**; only
  implementers may modify files.
- Include project testing obligations in every implementer task per the
  `paseo-delegation` testing section.
- Run independent safe steps in parallel only when files, generated artifacts,
  DB state, and ordering do not overlap.

After every step: verify the worker's terminal state and completion report,
run `git diff --name-only`, and compare with the declared expected files.
Significant divergence from the plan requires user confirmation before
dependent work. Answer worker questions with `send_agent_prompt` (CLI
fallback `paseo send <id>`) when they can
be resolved without the user; surface user-decision questions to the user and
relay the answer.

### Phase 4 — Verify and review

Read the command slots from `.agents/project.yaml` and run the ticket's
verification commands, or the profile `commands` slots, in this order:
`lint`, `typecheck`, `format_check`, and `test`; include the `e2e` command
per the `test_layers` slot, respecting each layer's declared policy. The
coordinator may run these read-only/check-mode commands itself. A failure
requires a fresh Paseo implementer fix (per `paseo-delegation` recovery)
followed by verification again. Do not commit with a failure.

Then dispatch a read-only Paseo `reviewer` against the full diff of changes
made in this session. Include the ticket constraints and project conventions
in the task spec, plus review focus: bugs and logic errors, security issues
(secrets, injection, auth bypass, missing validation), performance problems,
maintainability, and adherence to project conventions + the ticket's
acceptance criteria. Blocking findings require a fresh implementer dispatch,
followed by the complete verification and review loop. Non-blocking findings
require the user's explicit decision before deferral. The reviewer reports
only; never let it edit files.

### Phase 5 — Commit, push, and create the pull request

If an OpenSpec change was implemented, ensure all tasks in `tasks.md` are
marked complete (`- [x]`), then run:

```bash
openspec archive "<change-name>" --yes
```

This merges the delta specifications into canonical `openspec/specs/` and
archives the change. Stage only intended files (including archived
`openspec/` artifacts); never stage unrelated working tree changes or env
files. The project's declared format command and pre-commit hook (see
`.agents/project.yaml` `commands`) may reformat; that is expected.

Show `git status --short`, exact verification outcomes, review results, and
rollback guidance. Stage only intended files and **commit, push, and create
the PR automatically** after all local verification and review pass — do not
ask for confirmation. Use a ticket-linked commit message. Never commit or
push `main`.

Create the PR using the **PR description contract from `paseo-delegation`**
(standalone comprehensive body, real Markdown newlines, grep guard for literal
`\n`, `gh pr view --json body --jq .body` verification). The PR must include
`Closes #<number>`. Do not close the issue and do not merge the PR.

### Phase 6 — Monitor CI and resolve failures

After creating the PR, identify its checks with `gh pr checks <number>` and
monitor until every required check succeeds. Wait between polls rather than
busy-looping. A failure, cancelled check, timeout, or newly reported required
check must be investigated from its logs and treated as an implementation or
verification failure.

Every CI failure fix must be dispatched to a fresh supervised Paseo
`implementer` (per `paseo-delegation` recovery); never fix it inline. Give
the worker the PR, failing check and log context, relevant files, and the
requirement to preserve the ticket's acceptance criteria. After each fix,
verify worker completion and modified-file scope, run the complete local
verification and reviewer loop from Phase 4, then commit and push the fix.
Re-monitor all PR checks from the beginning.

Stop only when all required PR checks are successful. If a check is flaky or
its required status cannot be determined, investigate and retry or dispatch a
fix; do not declare success based only on local checks. Do not merge the PR.
Report the PR URL, final commit, successful CI checks, and any deviations.

## Rules

- This is direct mode only. Do not perform autonomous epic-sub-ticket work.
  User confirmation is required for ticket selection and any unresolved plan
  decisions; once the plan is authorized and implementation/review pass,
  commit, push, PR creation, and CI monitoring are automatic.
- Never commit or push `main`; never create, archive, or delete worktree
  workspaces.
- Never perform delegated work inline or use a non-Paseo substitute; follow
  the `paseo-delegation` recovery discipline on any failed worker.
- Never skip lint/typecheck/review, and never commit failing verification.
- Follow the installed `paseo` skill and the `paseo-delegation` contract when
  this document and either of them differ.
