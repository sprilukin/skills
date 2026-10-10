---
name: implement-ticket
description: "Implement GitHub tickets or epics through mandatory sub-agent delegation, harness-agnostically. Triggers: 'implement ticket', 'work on issue', 'implement epic #N'. Mode routing: plain invocation implements one ticket (direct, user-gated mode); an epic number/URL runs the epic coordinator (epic.md); a task spec containing the AUTONOMOUS_EPIC_SUBTICKET gate runs the autonomous sub-ticket worker (autonomous.md). Never used for planning."
---

# Implement Ticket

Implement GitHub tickets and epics through mandatory sub-agent delegation.
This skill owns the **WHAT**: ticket/epic selection, plan parsing, phase
order, gates, and role assignments. The **worker-delegation** skill owns the
**HOW**: harness detection, dispatch mechanics, provider preflight, the
wait/harvest discipline, recovery, completion proof, the PR description
contract, and testing obligations. Load and follow `worker-delegation`
whenever this skill says to dispatch, wait for, or recover a sub-agent; when
this skill and `worker-delegation` disagree on mechanics, `worker-delegation`
wins.

The coordinator (this skill's agent, in direct or epic mode) may discover
context, parse plans, run read-only checks, and summarize results, but must
never implement, explore, fix, or review delegated work inline. If the
detected harness, its daemon/app, the selected provider, or provider
authentication is unavailable, stop and tell the user what must be fixed.
Never fall back to a generic subagent substitute, bare shell, raw terminal
input, or inline work.

## Mode routing (resolve once, at load)

Exactly one mode applies. Resolve it from the invocation — never from
ambient context or user phrasing alone:

| Situation                                                                    | Mode to run                        |
| ---------------------------------------------------------------------------- | ---------------------------------- |
| User wants one ticket implemented and is present to confirm decisions        | **Direct mode** — this file.       |
| User wants a validated epic run autonomously (given an epic number/URL)      | **Epic coordinator** — [epic.md](epic.md). |
| This agent is a dispatched worker whose task spec contains the `AUTONOMOUS_EPIC_SUBTICKET` gate | **Autonomous sub-ticket worker** — [autonomous.md](autonomous.md). |

Mode exclusions are hard: direct mode is never an epic sub-ticket worker;
the autonomous worker is never used for direct mode; a dispatched worker
never switches to a different mode's skill mid-run. A dispatched worker
follows this skill (the routed mode file) plus the `worker-delegation`
contract **only** — never load another mode's skill.

## Delegation contract (all modes, mandatory, never optional)

- A code-changing plan step with no role is an `implementer` step. Every
  implementation, exploration, review, and verification-failure fix must be
  dispatched. Generated-code regeneration belongs in an implementer task.
- **Reviewer and explorer workers receive `MAY modify files: no`**; only
  implementers may modify files. A reviewer/explorer may report only.
- Every dispatched task is built from the task-spec template and passed
  through the `worker-delegation` contract (dispatch inputs, batching,
  parallel rules, readable kebab-case slugs, wait/harvest discipline,
  recovery).
- Require both a succeeded worker report (with any required completion
  proof) and the harness's dispatch/terminal verification; terminal output
  alone is not completion proof.
- On a failed worker, surface the failure and dispatch a new implementer
  fix per `worker-delegation` recovery, or ask the user how to proceed.
  Never fix it inline.
- After each implementer step, run `git diff --name-only` and compare it
  with the declared expected files; flag divergence to the user.
- Include project testing obligations in every implementer task per the
  `worker-delegation` testing section, and the per-stack skill declared by
  the profile's `stack` section (e.g. the installed `supabase` skill) in
  constraints when the step touches DB/auth/RLS and the skill is installed.

If the ticket lacks a **Decision completeness** declaration, or contains
unresolved questions, `TBD` values, pending choices, or user-directed
decisions, stop and ask the user to resolve them before dispatching. Do not
dispatch implementation work around an unresolved product or technical
decision.

## Direct mode — implement one ticket (user-gated)

Implement one GitHub ticket in direct mode. Pick a ticket by description,
or from the latest open issues, and execute its plan. This mode never
operates as an autonomous epic sub-ticket worker. Once the implementation,
local verification, and review pass, commit the intended changes, push the
branch, create a pull request, and monitor its CI to success. Do not merge
the pull request or close the issue.

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
no description, list five open issues and ask for a selection. Fetch the
full issue with `gh issue view <number> --json number,title,body,labels,url`.

For a structured `plan-feature` ticket, check if an OpenSpec change is
referenced (e.g. `openspec/changes/<change-name>/` or an active change
directory):

- If an OpenSpec change is present, inspect it with
  `openspec instructions apply --change "<change-name>" --json` to retrieve
  the task list, delta specs, design decisions, and context files.
- Parse `tasks.md` and delta specs (`specs/<capability>/spec.md`) to build
  the ordered implementation steps, verification requirements, and
  constraints for worker dispatches.
- If no OpenSpec change exists, extract the ordered implementation and
  verification plans directly from the issue body. Every `implementer`,
  `explore`, or `reviewer` assignment is a mandatory dispatch.
- If the ticket is unstructured, dispatch a read-only `explore` worker
  first, then propose a plan and obtain explicit user confirmation before
  implementation. Stop when Decision completeness is absent or unresolved
  choices/TBDs remain.

### Phase 2 — Branch and shared services

Confirm `git branch --show-current`; stop on `main`. Work only in the
existing active checkout (the coordinator's own workspace — direct mode does
not use worktree workspaces). Never create, archive, or delete worktree
workspaces in this mode.

Before mutating shared infrastructure (databases, generated types, env),
check project guidance for coordination rules; if none, ask the user how to
coordinate.

### Phase 3 — Execute through delegated workers

Run the `worker-delegation` preflight for the detected harness, then
dispatch every plan step through the `worker-delegation` contract — task
spec template, batching, parallel rules, readable slugs, wait/harvest
discipline, and recovery — as follows:

- After every step: verify the worker's terminal state and completion
  report, run `git diff --name-only`, and compare with the declared expected
  files. Significant divergence from the plan requires user confirmation
  before dependent work.
- Answer worker questions through the `worker-delegation` question/reply
  channel when they can be resolved without the user; surface user-decision
  questions to the user and relay the answer.

### Phase 4 — Verify and review

Read the command slots from `.agents/project.yaml` and run the ticket's
verification commands, or the profile `commands` slots, in this order:
`lint`, `typecheck`, `format_check`, and `test`; include the `e2e` command
per the `test_layers` slot, respecting each layer's declared policy. The
coordinator may run these read-only/check-mode commands itself. A failure
requires a fresh implementer fix (per `worker-delegation` recovery) followed
by verification again. Do not commit with a failure.

Then dispatch a read-only `reviewer` worker against the full diff of changes
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

Create the PR using the **PR description contract from `worker-delegation`**
(standalone comprehensive body, real Markdown newlines, grep guard for
literal `\n`, `gh pr view --json body --jq .body` verification). The PR must
include `Closes #<number>`. Do not close the issue and do not merge the PR.

### Phase 6 — Monitor CI and resolve failures

After creating the PR, identify its checks with `gh pr checks <number>` and
monitor until every required check succeeds. Wait between polls rather than
busy-looping. A failure, cancelled check, timeout, or newly reported required
check must be investigated from its logs and treated as an implementation or
verification failure.

Every CI failure fix must be dispatched to a fresh supervised `implementer`
worker (per `worker-delegation` recovery); never fix it inline. Give the
worker the PR, failing check and log context, relevant files, and the
requirement to preserve the ticket's acceptance criteria. After each fix,
verify worker completion and modified-file scope, run the complete local
verification and reviewer loop from Phase 4, then commit and push the fix.
Re-monitor all PR checks from the beginning.

Stop only when all required PR checks are successful. If a check is flaky or
its required status cannot be determined, investigate and retry or dispatch
a fix; do not declare success based only on local checks. Do not merge the
PR. Report the PR URL, final commit, successful CI checks, and any
deviations.

## Rules (all modes)

- Never commit or push `main`; never create or delete worktrees in direct
  mode.
- Never perform delegated work inline or use a non-harness substitute;
  follow the `worker-delegation` recovery discipline on any failed worker.
- Never skip lint/typecheck/review, and never commit failing verification.
- Follow the `worker-delegation` contract when this document and it differ.
- Direct mode: user confirmation is required for ticket selection and any
  unresolved plan decisions; once the plan is authorized and
  implementation/review pass, commit, push, PR creation, and CI monitoring
  are automatic.
- Epic and autonomous modes: see [epic.md](epic.md) and
  [autonomous.md](autonomous.md) for their additional invariants; the rules
  in this section still apply.
