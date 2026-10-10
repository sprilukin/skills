---
name: implement-ticket
description: "Use when the user wants to implement a GitHub ticket in normal, user-gated mode through mandatory Orca-supervised delegation. Triggers: 'work on ticket via orca', 'implement ticket with orca', 'orca implementation'. Use only for direct ticket implementation, not planning or autonomous epic sub-tickets."
---

# Implement Ticket

Implement one GitHub ticket in **direct mode only**. Pick a ticket by
description, or from the latest five open issues, and execute its plan. This
skill never operates as an autonomous epic sub-ticket worker. Once the
implementation, local verification, and review pass, commit the intended
changes, push the branch, create a pull request, and monitor its CI to success.
Do not merge the pull request or close the issue.

## Non-negotiable delegation contract

Every `implementer`, `explore`, and `reviewer` step is dispatched to a fresh,
supervised Orca worker. Delegation is mandatory and has no inline fallback.
The coordinator may discover context, parse plans, run read-only checks, and
summarize results, but must never implement, explore, fix, or review delegated
work inline.

Load and follow the global `orca-cli` skill for executable resolution and the
live CLI guide, then the global `orchestration` skill for Run, Task, Dispatch,
worker lifecycle, waiting, replies, and completion verification. Those guides
own the exact commands and flags; never copy Orca command syntax into this
skill or invent a substitute.

If Orca, orchestration, the selected provider, or provider authentication is
unavailable, stop and tell the user what must be fixed. Never fall back to a
generic subagent, bare shell, direct terminal prompt, or inline work.

### Required worker rules

- Use the repository default worker agent `pi` unless the user explicitly
  selects another supported Orca TUI agent. There are two readiness regimes:
  **local TUI agents** (`pi`, `opencode`, `omp`, `gemini`, `grok`, `aider`, …)
  are validated only with `command -v <agent>` and `<agent> --version` — never
  run `orca account list` for these, since `orca account` manages only Claude
  and Codex accounts; **managed-account agents** (`claude`, `codex` only) must
  additionally show a signed-in managed account via `orca account list --json`.
  Missing Claude/Codex managed accounts is never a blocker for a `pi`/`opencode`
  session.
- Create or bind one Run for the session and reuse it for every dispatch.
  Confirm it with the orchestration guide before starting workers.
- Pass `TIMEOUT_MS=900000` to every worker start.
- Direct-mode workers use the active/current shared worktree. Never create or
  delete worktrees in this skill, and stop if the current branch is `main`.
- Reviewer and explorer workers receive `MAY modify files: no`; only
  implementers may modify files.
- A code-changing plan step with no role is an `implementer` step. Every
  implementation, exploration, review, and verification-failure fix must be
  dispatched. Generated-code regeneration belongs in an implementer task.
- Require both a succeeded `worker_done` result and Dispatch status
  `completed`; terminal output alone is not completion proof.
- On a failed worker, surface the failure and dispatch a new implementer fix,
  or ask the user how to proceed. Never fix it inline.
- After each implementer, run `git diff --name-only` and compare it with the
  declared expected files.

## Task specification

Build each dispatched task from this template and pass it to the
orchestration skill's supervised dispatch recipe:

```text
## Task: <plan step title>
## Ticket: #<number>
## Plan step: <number and description>
## Role: <implementer|explore|reviewer>

## Context
<relevant ticket and repository context>

## Constraints
<ticket decisions, best practices, AGENTS.md conventions, and testing rules>

## Files in scope
<files the worker may inspect or modify>

## You MAY modify files: <yes|no>

## Expected output
<implementation or read-only report>

## Acceptance criteria
<specific behavior and checks; include regeneration commands when needed>

## Completion
Follow the injected lifecycle preamble as authoritative for worker_done,
ask, and heartbeat. Send worker_done exactly once with succeeded or failed and
modified files, then end the turn. Do not substitute IDs manually.
```

Use readable kebab-case slugs such as `fix-form-validation-error` or
`review-<capability>-diff`, never generic worker/task slugs. Batch only genuinely
simple ordered steps; dispatch hard steps alone and independent disjoint steps
in parallel according to the orchestration guide.

## Workflow

### Phase 0 — discover context

Read root `AGENTS.md`, `.agents/project.yaml` (authoritative for paths and
commands), applicable nested instructions, `README.md`, relevant `docs/`,
functional requirements, manifests, testing guidance, and migration or
generated-code guidance. Run `gh repo view --json nameWithOwner,defaultBranchRef,description`
and inspect the repository layout. Never read `.env*` files except
`.env.example`. If repository or GitHub discovery fails, stop and ask.

### Phase 1 — select and parse the ticket

For a description, run `gh issue list --state open --limit 30 --search
"<description>"`, show the top matches, and ask the user to select one. With
no description, list five open issues and ask for a selection. Fetch the full
issue using `gh issue view <number> --json number,title,body,labels,url`.

For a structured `plan-feature` ticket, check if an OpenSpec change is referenced
(e.g., `openspec/changes/<change-name>/` or an active change directory):

- If an OpenSpec change is present, inspect it with `openspec instructions apply --change "<change-name>" --json` to retrieve the task list, delta specs, design decisions, and context files.
- Parse `tasks.md` and delta specs (`specs/<capability>/spec.md`) to build the ordered implementation steps, verification requirements, and constraints for worker dispatches.
- If no OpenSpec change exists, extract the ordered implementation and verification plans directly from the issue body. Every `implementer`, `explore`, or `reviewer` assignment is a mandatory dispatch.
- If the ticket is unstructured, dispatch a read-only `explore` worker first, then propose a plan and obtain explicit user confirmation before implementation.
  Stop when Decision completeness is absent or unresolved choices/TBDs remain.

### Phase 2 — branch and shared services

Confirm `git branch --show-current`; stop on `main`. Work only in the existing
active worktree. Before mutating shared infrastructure
(databases, generated types, env), check project guidance for coordination
rules; if none, ask the user how to coordinate.

### Phase 3 — execute through Orca

Create/bind the Run once, validate the selected worker agent's readiness
(`pi` by default — `command -v pi` and `pi --version`; only `claude`/`codex`
need `orca account list --json`), and dispatch every plan step through the
orchestration guide. Include project testing obligations in
every implementer task: colocated tests for new pure logic, interaction tests
where the repository uses them, and e2e coverage for applicable user flows.
Run independent safe steps in parallel only when files, generated artifacts,
DB state, and ordering do not overlap.

After every step, verify the dispatch status, worker result, modified-file
scope, and acceptance criteria. Significant divergence from the plan requires
user confirmation before dependent work. A reviewer/explorer may report only;
never allow them to edit files.

### Phase 4 — verify and review

Read the command slots from `.agents/project.yaml` and run the ticket's
verification commands, or the profile `commands` slots, in this order: `lint`,
`typecheck`, `format_check`, and `test`; include the `e2e` command per the
`test_layers` slot, respecting each layer's declared policy. A failure
requires a fresh Orca implementer fix followed by verification again. Do not
commit with a failure.

Then dispatch a read-only Orca `reviewer` against the full diff. Include the
ticket constraints and project conventions. Blocking findings require a fresh
implementer dispatch, followed by the complete verification and review loop.
Non-blocking findings require the user's explicit decision before deferral.

### Phase 5 — commit, push, and create the pull request

If an OpenSpec change was implemented, ensure all tasks in `tasks.md` are marked complete (`- [x]`), then run:

```bash
openspec archive "<change-name>" --yes
```

This merges the delta specifications into canonical `openspec/specs/` and archives the change.

Show `git status --short`, exact verification outcomes, review results,
rollback guidance, and a ticket-linked commit message. Stage only intended
files (including archived `openspec/` artifacts) and commit automatically after all local verification and review pass.
Push the current branch and create the pull request automatically; do not ask
for confirmation. Never commit or push `main`.

After committing, use the question tool for push/PR choices, preselecting
Create a PR. A PR must have a standalone body with these sections, based on
the final diff and actual checks: `Closes #<number>`, Why, What changed,
Implementation details, User-visible behavior, Verification, Deviations from
the ticket, and Risks and follow-up. Write the body with real Markdown
newlines, verify it with `gh pr view --json body --jq .body`, and never claim
checks or PR creation that did not occur. Do not close the issue and do not
merge the PR.

### Phase 6 — monitor CI and resolve failures

After creating the PR, identify its checks with `gh pr checks <number>` and
monitor until every required check succeeds. Wait between polls rather than
busy-looping. A failure, cancelled check, timeout, or newly reported required
check must be investigated from its logs and treated as an implementation or
verification failure.

Every CI failure fix must be dispatched to a fresh supervised Orca
`implementer`; never fix it inline. Give the worker the PR, failing check and
log context, relevant files, and the requirement to preserve the ticket's
acceptance criteria. After each fix, verify worker completion and modified-file
scope, run the complete local verification and reviewer loop from Phase 4,
then commit and push the fix. Re-monitor all PR checks from the beginning.

Stop only when all required PR checks are successful. If a check is flaky or
its required status cannot be determined, investigate and retry or dispatch a
fix; do not declare success based only on local checks. Do not merge the PR.
Report the PR URL, final commit, successful CI checks, and any deviations.

## Rules

- This is direct mode only. Do not perform autonomous epic-sub-ticket work.
  User confirmation is still required for ticket selection and any unresolved
  plan decisions, but once the plan is authorized and implementation/review
  pass, commit, push, PR creation, and CI monitoring are automatic.
- Never commit or push `main`; never create/delete worktrees.
- Never perform delegated work inline or use a non-Orca substitute.
- Never skip lint/typecheck/review, and never commit failing verification.
- Follow the live Orca guides when this document and the installed CLI differ.
