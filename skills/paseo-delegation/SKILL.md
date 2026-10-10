---
name: paseo-delegation
description: Shared delegation protocol for the *-paseo skills (plan-feature-paseo, implement-ticket-paseo, implement-epic-paseo, implement-auto-paseo). Loaded and followed by those skills; defines worker dispatch, wait/harvest discipline, completion proof, and PR description contracts. Never triggered on its own.
disable-model-invocation: true
---

# Paseo Delegation Protocol

This skill is the single protocol authority for supervised Paseo delegation in
this repository. The invoking skill owns the **WHAT** (which ticket, which
steps, which roles, which gates); this skill owns the **HOW** (dispatch
mechanics, waiting, harvesting, proof, PR body contract). When an invoking
skill and this skill both describe delegation mechanics, this skill wins.

Load and follow this skill whenever an invoking `*-paseo` skill tells you to
dispatch, supervise, or report on Paseo workers.

## 1. The delegation loop

Two roles exist. Every `*-paseo` skill participant is exactly one of them at
any moment:

- **Supervisor** — dispatches workers, verifies placement, waits, harvests
  results, cross-validates reports, schedules recovery. Never performs
  delegated work inline.
- **Worker** — receives exactly one task spec, executes it, reports the
  outcome **exactly once** in its final message, then ends its turn and idles.
  A worker that is also a coordinator (e.g. `implement-auto-paseo` supervising
  its own sub-workers) switches to the supervisor role for those dispatches.

Loop map (who calls whom):

```text
plan-feature-paseo   (main session; inline research; creates GitHub tickets)
  └─ Option D/E handoff → Paseo worktree workspace + default-provider worker
       ├─ single ticket → implement-ticket-paseo   (supervisor; direct mode)
       └─ epic          → implement-epic-paseo      (coordinator; merges child PRs)
            └─ per child → implement-auto-paseo      (worker; also supervises sub-workers)
```

Routing table (intent → entry point). Resolve your mode **once**, at load,
from this table — never from ambient context or user phrasing alone. Exactly
one entry applies per participant:

| Situation                                                                                 | Skill to load and follow                                                          |
| ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| User wants to plan a feature (no implementation)                                          | `plan-feature-paseo`                                                              |
| User wants one ticket implemented, is present to confirm decisions (direct mode)          | `implement-ticket-paseo`                                                          |
| User wants a validated epic run autonomously (user walking away)                          | `implement-epic-paseo`                                                            |
| You are a dispatched worker whose task spec contains the `AUTONOMOUS_EPIC_SUBTICKET` gate | `implement-auto-paseo`                                                            |
| You were dispatched by any of the above coordinators/supervisors                          | This contract plus your invoking skill **only** — never load another mode's skill |

Mode exclusions are hard: `implement-ticket-paseo` is never an epic
sub-ticket worker; `implement-auto-paseo` is never used for direct mode; a
dispatched worker never switches to a different mode's skill mid-run.

## 2. Authority: this contract vs the installed `paseo` skill

- Resolve Paseo mechanics from the **installed `paseo` skill** (version-matched
  to the daemon). If it is not installed, fall back to `paseo --help`,
  `paseo <command> --help`, and https://paseo.sh/docs/cli. Never run
  `paseo ...` commands from memory.
- **Prefer the Paseo MCP tools** over the CLI wherever an equivalent exists:
  `create_agent` (dispatch), `send_agent_prompt` (follow-ups and question
  answers), `list_agents`, `create_workspace`, `list_workspaces`,
  `list_providers`, `list_models`, `inspect_provider`, and `list_profiles`.
  Detect availability once per session: if your toolset does not list these
  tools, treat the MCP surface as unavailable and use the CLI fallbacks
  throughout. Also fall back to the CLI per call when no equivalent exists
  (notably logs harvesting, placement inspection, daemon status, provider
  diagnostic, and stop).
- The installed `paseo` skill's general guidance ("don't poll — the
  notification will tell you") targets single fire-and-forget agents. It does
  **not** fit a supervisor that must batch, parallel-dispatch, and reconcile
  multiple workers. For supervised delegation loops, the wait/harvest
  discipline in section 5 of this contract **overrides** that guidance.
- Allowed CLI verbs for this protocol (verified against the installed CLI;
  re-check flags with `paseo <verb> --help` when versions may have changed):
  `status`, `ls`, `run`, `wait`, `inspect`, `logs`, `send`, `stop`,
  `workspace ls|create|archive|rename`, `provider ls|diagnostic|models`.
  Do not invent other verbs or flags.
- If the daemon, the selected provider, or provider authentication is
  unavailable, **stop and tell the user what must be fixed.** Never fall back
  to a generic subagent, bare shell, raw terminal input, or inline work.

## 3. Provider preflight (run once per session, before the first dispatch)

The repository default worker provider is **`pi`**. Use it unless the user
explicitly selects another supported provider; never silently switch providers.

1. `paseo status` — confirm the daemon is running. If not, start it per the
   installed `paseo` skill; stop if that fails.
2. Confirm you are running inside Paseo when the invoking skill requires it
   (its task spec says so): `PASEO_AGENT_ID` is set and `paseo ls` shows your
   own agent. Outside Paseo, stop and tell the user.
3. Provider availability — use the `list_providers` MCP tool (CLI fallback:
   `paseo provider ls`); require the selected provider present with status
   `available` and enabled.
4. `paseo provider diagnostic <provider>` — require the daemon-resolved
   binary, version, and model list to be healthy. Never print credentials,
   tokens, or secret configuration.
5. `command -v <agent>` and `<agent> --version` — executable present on PATH
   and able to report its version without prompting.
6. **Profiles:** if agent profiles are configured, consult them via the
   `list_profiles` MCP tool (CLI fallback: the installed `paseo` skill's
   profile discovery) and pick one the user requested or one whose notes
   match the work; otherwise launch with the validated default provider.
7. **Model-default gate.** Worker dispatches omit an explicit model, so every
   dispatched worker resolves to the selected provider's configured default
   in the Paseo daemon config. Before the first dispatch, verify that default
   against the invoking coordinator's own model:
   - Read `${PASEO_HOME:-$HOME/.paseo}/config.json` and resolve the selected
     provider's execution default: the entry with `"isDefault": true` under
     `agents.providers.<provider>.additionalModels` (for the default `pi`
     provider: `agents.providers.pi.additionalModels`). If no entry has
     `"isDefault": true`, the effective worker default is unverifiable —
     treat the gate as failed.
   - Compare that id with the coordinator's own model, which pi exposes as
     `PI_MODEL` (bare id) and `PI_PROVIDER` (provider prefix) on every
     spawned command, re-resolved at each command start. The gate passes when
     the config id equals `${PI_PROVIDER}/${PI_MODEL}` or the bare
     `PI_MODEL`; unset `PI_MODEL`/`PI_PROVIDER` (coordinator not running
     under pi) is a gate failure.
   - **On mismatch, stop before the first dispatch** and before any other
     side effect. Report the coordinator model and the config default
     verbatim, and tell the user to set `isDefault: true` on the intended
     entry in Paseo's provider settings (or `~/.paseo/config.json`) and run
     `paseo reload`, then re-invoke the skill. Never edit
     `~/.paseo/config.json` autonomously, never proceed on mismatch, never
     switch providers, and never fall back to inline work.
8. **Pinned model (`REQUIRED_MODEL`).** When the invocation prompt or task
   spec carries a `REQUIRED_MODEL=<full model id>` line (written by
   `plan-feature-paseo` Option E), the coordinator pins its checks to that
   id: its own model must equal `REQUIRED_MODEL`, and the step-7 config
   default must equal `REQUIRED_MODEL` as well. Either mismatch stops the
   run with the step-7 report-and-reload instructions before any dispatch or
   side effect; the pin never replaces the config-default check.

If a provider is `available` but a specific model fails authentication at
runtime, do not blindly retry: diagnose with `paseo provider diagnostic`,
select a working `provider/model` pair explicitly, re-validate, and tell the
user which model failed and what replaced it.

Stop before the first dispatch if the provider is absent or `unavailable`, the
diagnostic fails, or the first worker cannot start. Tell the user exactly what
must be installed, configured, or signed in.

## 4. Dispatching workers

### Dispatch tool (MCP-first)

Dispatch each worker with the `create_agent` MCP tool: `provider` set to the
validated provider (repository default `pi`), `title` set to the kebab-case
SLUG, `initialPrompt` set to the full task-spec text below, `workspaceId` set
to the supplied worktree workspace when the dispatch is anchored to one, and
`notifyOnFinish` left enabled (the agent-scoped default) so the completion
notification arrives without polling. Fall back to the `paseo run` CLI when
the MCP tool surface is unavailable; the installed `paseo` skill owns its
flags.

### Task spec template

Build every dispatched task from this template and pass it as the worker's
initial prompt. It is self-contained — the worker receives no other preamble
and must be able to discover nothing from ambient context.

```text
## Task: <title>
## Ticket: #<number>
## Plan step: <number and description>
## Role: <implementer|explore|reviewer>

## Placement contract (include only when the supervisor supplies a workspace)
WORKSPACE_ID=<exact Paseo worktree workspace id>
WORKTREE_PATH=<absolute worktree path>
CHILD_BRANCH=<exact branch, when this dispatch works on a dedicated branch>
<Verify with: pwd, git branch --show-current, git rev-parse --show-toplevel.
If any value does not match, stop and report a placement failure; do not edit
files.>

## Context
<relevant ticket and repository background>

## Constraints
<ticket decisions, best practices, AGENTS.md conventions, testing rules
(see section 9), platform-skill guidance when applicable>

## Files in scope
<files and directories this worker may inspect or modify>

## You MAY modify files: <yes|no>
(yes for implementer; no for reviewer and explore)

## Expected output
<implementation or read-only report>

## Acceptance criteria
<specific behavior and checks; include regeneration commands when generated
artifacts are affected>

## Completion contract
Report the outcome EXACTLY ONCE in your final message with succeeded or
failed, then end your turn and idle. Report failure with the exact blocking
reason. If a supervisor decision is required before you can continue, end
with an explicit QUESTION section and idle — the supervisor will reply via a
follow-up message.
<When the invoking skill requires a completion proof block, name it here —
see section 7.>
```

### Placement verification (supervisor side)

When a dispatch is anchored to a supplied worktree workspace: after the worker
starts, `paseo inspect <worker-id>` must show `Cwd` = `WORKTREE_PATH` (and
`ParentAgentId` = the supervisor, or an explicitly accepted host session;
`list_workspaces` can map the supplied `workspaceId` to the expected path), and
the worker's report must confirm its branch. A worker that landed in the
supervisor's workspace, the main checkout, or another worker's workspace is a
placement failure: stop it, do not let it modify files, re-dispatch correctly.

### Titles (SLUG)

Every dispatched worker gets a readable, descriptive kebab-case `--title` that
tells the user from the agent list what the worker is doing:
`add-export-filter-button`, `fix-form-validation-error`,
`explore-auth-middleware`, `review-<capability>-diff`. Never `step-1`,
`task-3`, `worker-42`, or bare `implement`. When batching multiple steps,
pick a slug summarizing the batch (e.g. `add-column-and-regen-types`).

### Batching

Batching is a scheduling optimization — the work is still dispatched to a
worker (never done inline); multiple steps just share one worker. Classify
each step:

- **simple** — small, isolated, low-risk: pure-function or type-only change,
  one-file rename, copy/config tweak, trivial presentational tweak.
- **medium** — a few files or one non-trivial component: new small feature,
  server action + call site, migration + the code reading the new column.
- **hard** — large, cross-cutting, high-risk: multi-file feature work,
  auth/session, RLS, schema + types + app code + tests together, non-obvious
  failure modes.

Rules:

- **Hard steps are always dispatched alone.**
- **Simple steps may batch together** when execution order allows. Keep
  batches reviewable — if the combined diff would be hard to review, split it.
- **A medium step may batch with up to two simple steps.** Never two medium
  steps together.
- **When in doubt, don't batch.**
- A batched spec must enumerate every bundled step (own Files in scope and
  Acceptance criteria subsections); `EXPECTED_FILES` is the union; verify each
  step's criteria individually after completion. Record the classification
  rationale in one line per step so the user can audit it.

### Parallel dispatch

Dispatch independent steps concurrently only when all of these hold:

- **Disjoint files** — no two parallel workers edit the same file.
- **No shared mutable state** — steps mutating the same DB/migration state,
  generated artifacts, or `.env`/config are serialized. Before mutating
  shared infrastructure (databases, generated types, env), check
  project guidance for coordination rules; if none, ask the user how to
  coordinate.
- **No ordering dependency** — if B reads A's output, they are not independent.
- **Resource sanity** — keep the number of parallel workers small and observable.

Create all workers first — do not wait between dispatches. With
`notifyOnFinish` enabled (the `create_agent` default) each worker's completion
notification arrives on its own; never busy-poll between dispatches. When a
notification arrives, inspect that worker's state and harvest its terminal
outcome from `paseo logs` instead of waiting live. CLI-only fallback: wait on
each worker with a timeout after creating all of them. When in doubt, run
sequentially. Parallel dispatch is an optimization, not a requirement.

## 5. Wait and result-harvest discipline (mandatory)

A worker's completion contract is a **one-shot**: it reports once in its final
message, ends its turn, and idles. The completion surface is the terminal
state, harvested from `paseo logs`.

1. **Inspect before waiting.** `paseo inspect <id>` (or `paseo ls`). Wait
   only when the agent is `running`. An already-`idle`, `error`, or archived
   agent is not a waitable condition.
2. **Rely on the completion notification, not polling.** With the MCP tools,
   `create_agent` and background `send_agent_prompt` leave `notifyOnFinish`
   enabled: the notification arrives on its own when the worker finishes,
   errors, or needs permission — move on to other work or reconcile state
   until then, and never busy-poll `list_agents`/`paseo ls` to "check on" a
   running worker. CLI-only fallback: `paseo wait <id> --timeout 900` (the
   `WORKER_WAIT_TIMEOUT` default, passed explicitly). A timeout is a
   checkpoint, not a verdict: inspect `paseo inspect <id>` for the real
   status before deciding anything.
3. **Never unbounded-wait a terminal worker.** Terminal states are `idle`,
   `error`, and archived. Harvest; never re-wait expecting resumption.
4. **Harvest from terminal state.** Read the final report from `paseo logs
<id>` (last assistant message) and the state from `paseo inspect`. This is a
   first-class capture path, equivalent to catching completion live.
5. **Cross-validate every result.** Independently validate the agent ID, the
   reported outcome, and the observed status against each other. A completed
   wait alone is never semantic completion: an `idle` agent whose report lacks
   required proof, or claims failure, is not a success.
6. **No active worker ⇒ no unbounded wait.** If no worker is `running` and no
   pending question requires a reply, reconcile state, harvest terminal
   outcomes, schedule a valid recovery dispatch, or stop with a precise
   report. Never sit in a wait with nothing waitable.

Terminal-state matrix:

| Worker state                   | Supervisor action                                                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `running`                      | Await the completion notification; CLI fallback `paseo wait --timeout 900`; inspect liveness; answer questions via `send_agent_prompt`. |
| `idle` with valid proof/report | Harvest from `paseo logs`; reconcile files/GitHub; continue. Do not retry.                                                              |
| `idle` without required proof  | Record protocol-invalid completion; schedule a fresh recovery dispatch in the preserved workspace/branch.                               |
| `error`                        | Diagnose via `paseo inspect`/`paseo logs`; schedule a fresh recovery dispatch in the preserved workspace/branch.                        |
| archived / terminal            | Treat as history; reconcile via files/GitHub; never re-wait, never resume.                                                              |

Questions and escalations: a worker needing a decision ends with a QUESTION
section and idles. The supervisor reads it from `paseo logs`, answers with
`send_agent_prompt { agentId, prompt }` (CLI fallback:
`paseo send <id> "<answer>"`; the worker resumes in its existing
conversation), and resumes waiting. Questions needing the user go to the user first. Never run the step
yourself while the worker is active.

## 6. Recovery

- A failed, protocol-invalid, or interrupted worker is **never** fixed inline
  and **never** resumed by sending it follow-up work. Recovery is a **fresh**
  dispatch, into the preserved workspace/branch, with full context of what
  exists (files changed so far, existing PRs to repair rather than replace).
- An existing canonical artifact (branch, PR) must be repaired or reused, never
  duplicated. Never create a second PR to fix the first.
- Healing budgets (how many recovery attempts are allowed before a work item
  is terminal) are owned by the invoking skill (e.g. `implement-epic-paseo`'s
  two-attempts-per-child bound). This contract only mandates that fresh
  dispatches — not retries — are the recovery mechanism.

## 7. Completion proof

**Autonomous child workers** (a worker authorized to commit, push, and create
one PR — the `implement-auto-paseo` case) must include this block in their
single final success report. A success report without it is protocol-invalid:

```text
COMPLETION_PROOF
OUTCOME=succeeded
COMMIT_SHA=<commit on CHILD_BRANCH>
PUSHED_BRANCH=<CHILD_BRANCH>
PR_URL=<canonical URL>
PR_NUMBER=<number>
PR_BASE=<INTEGRATION_BRANCH>
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native child number or URL>
PR_METADATA_VERIFIED=true
```

**Direct-mode steps** (supervisor dispatches inside one ticket's workflow) do
not produce child PRs; their success reports must instead include: files
changed, verification commands run and their outcomes, and any deviations from
the plan.

Implementation-only, verification-only, or review-only completion is never
successful autonomous completion. If any proof element is missing, the worker
reports failure with the exact blocking reason instead of a false success.

After every implementer step the supervisor also runs `git diff --name-only`
and compares it to the declared expected files, flagging divergence.

## 8. PR description contract (canonical)

Every PR created under this protocol — a direct-mode ticket PR or an
autonomous child PR — must have a standalone comprehensive body. A reviewer
must be able to understand rationale, scope, approach, and key behavior
without opening the ticket. The ticket and plan are inputs, not substitutes
for documenting what the implementation actually did.

Compose the description **only after** implementation, verification, and
review, gathering facts from: the ticket/plan (problem, rationale, acceptance
criteria), the final diff (`git diff <base>...HEAD`), implementer reports and
verification output, and reviewer findings. Required sections, in this order —
write `None` / `Not applicable` rather than omitting:

```markdown
Closes #<number>
<in autonomous epic mode, `Part of #<parent-epic>` immediately below>

## Why

<The problem, user need, or technical reason. Why existing behavior was
insufficient and what outcome this PR provides.>

## What changed

<Concise overview, then bullets of externally meaningful changes.>

## Implementation details

<Low-level detail a reviewer can follow without the ticket: files/modules,
state transitions, data flow, validation and error handling, persistence/API
changes, trade-offs.>

## User-visible behavior

<Before/after behavior, affected screens or flows, edge cases. For non-UI
work, the observable system or developer-facing behavior.>

## Verification

<Exact checks that ran and their outcomes. Never claim a check ran if it did
not.>

## Deviations from the ticket

<`None` when the implementation matches; otherwise what was requested, what
was implemented, why, and the impact.>

## Risks and follow-up

<Known risks, migration/deployment considerations, deferred work. `None` when
there are none.>
```

Formatting and creation rules:

- Write real Markdown newlines — never literal `\n` sequences, JSON-escaped
  strings, or shell substitution that mangles line breaks. One blank line
  between blocks; use headings, bullets, and fenced code for commands.
- Prefer concrete file/module names and behavior over generic claims. Do not
  paste the entire diff. Call out breaking changes, security/auth implications,
  schema changes, and migrations explicitly when relevant.
- Before creating the PR, inspect the body file: `grep -nF '\n' "$PR_BODY"`
  must find nothing (literal escaped newlines), else rewrite the body.
- Create with `gh pr create --title ... --body-file "$PR_BODY"`, then verify
  the rendered body with `gh pr view <url> --json body --jq .body` (rendered,
  not raw JSON). Repair with `gh pr edit` and re-verify if sections are
  missing or newlines were mangled.
- Autonomous workers never merge PRs and never close issues — unless the
  invoking skill explicitly grants that authority to a named role (only
  `implement-epic-paseo`'s coordinator currently has it).

## 9. Testing obligations for implementer specs

Every `implementer` task spec whose step changes code carries these
obligations, adjusted to what project discovery found:

- **Colocated unit/integration tests** for new pure functions, schemas, hooks
  when the project declares a colocated test layer (e.g. profile
  `test_layers`).
- **Component interaction tests** for new UI behaviors when the project's
  testing conventions declare component-level interaction tests (e.g. via a
  component workbench with `play` functions) — especially for stateful
  client components.
- **E2E tests** for user-facing flows when the project declares an e2e test
  layer (e.g. profile `test_layers`) and the flow is user-facing (check the
  project's testing docs for the golden path).
- **Skip only when justified:** the plan explicitly says no tests are needed
  AND the change is purely presentational with no new logic. Otherwise default
  to adding tests.
- Consult the project's testing docs for frameworks, mocking patterns, and
  assertion styles; follow existing test files as exemplars.

If a worker omits required tests, the supervisor dispatches a follow-up
`implementer` task to add them — never adds them inline.
