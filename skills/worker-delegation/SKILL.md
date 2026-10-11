---
name: worker-delegation
description: "Worker delegation protocol for dispatching work to sub-agents/workers, harness-agnostically. Invoke BEFORE any dispatch, wait, or recovery: the SDLC skills (plan-feature, implement-ticket) require invoking it at every delegated step, and it is invoked directly when the user asks for a handoff or to spawn/delegate a worker. Detects the current harness (Orca, Paseo, or a harness with native sub-agents) and applies the harness-specific recipe from its harness/ directory. If it cannot be invoked, stop and ask the user — never dispatch from memory."
---

# Worker Delegation Protocol

This skill is the single delegation authority for this repository. The
invoking skill owns the **WHAT** (which ticket, which steps, which roles,
which gates); this skill owns the **HOW** (harness detection, worker
dispatch, waiting, harvesting, recovery, completion proof, and the PR body
contract). When an invoking skill and this skill both describe delegation
mechanics, this skill wins.

An invoking skill's reference to this protocol means: invoke this skill
now, through the harness's skill-invocation mechanism, and follow it —
never apply it from memory or from the invoking skill's summary. If this
skill cannot be invoked, stop and ask the user. "Sub-agent" and "worker"
are interchangeable in this protocol; the harness may use either term.

## 1. Authority and harness resolution

- Resolve harness-specific mechanics from the harness file for the detected
  harness: [harness/orca.md](harness/orca.md),
  [harness/paseo.md](harness/paseo.md), or
  [harness/native.md](harness/native.md). Each harness file declares its own
  **detection predicate** (how to tell it is the current harness) and its
  **capabilities** (see below). The harness file is authoritative for
  commands, flags, and tool names; never copy or reconstruct harness command
  syntax from memory or from invoking skills.
- **Detection precedence: Orca → Paseo → native.** Evaluate each harness
  file's detection predicate in that order and use the first positive match.
  If evidence is ambiguous (two harnesses plausibly match, or the expected
  evidence is missing exactly when it matters), stop and ask the user — never
  silently guess.
- **Universal rejected evidence.** The following are never harness-detection
  evidence for any harness: a CLI binary on `PATH` or a successful
  `<app> status` of an app or daemon (they prove software is installed or
  running on this machine, not that this session lives in it), endpoint or
  config files on disk, and skills merely visible in this session's skill
  list (another harness's skills can be installed here). The only detection
  evidence is the positive predicate the harness file itself declares.
  Harness files may add harness-specific rejected evidence; they never
  relax this rule.
- If the detected harness, its daemon/app, the selected provider, or provider
  authentication is unavailable, **stop and tell the user what must be
  fixed.** Never fall back to a bare shell, raw terminal input, or inline
  work, and never substitute a different mechanism than the detected harness
  recipe prescribes.

### Capability flags

Each harness file declares which capabilities it supports. Invoking skills
must not assume a capability the harness does not declare:

| Capability           | Meaning                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| `placement`          | Workers can be anchored to a dedicated worktree/workspace and branch — supervisor-created, or prompt-directed (the worker creates/enters it and checks out the branch itself) per the harness file. |
| `question-channel`   | A worker can ask the supervisor a question and resume after a reply.           |
| `async-notification` | Worker completion is delivered as a notification (no polling required). Applies to background-spawned workers; a mechanism that returns results synchronously does not have it. |
| `model-pinning`      | A specific model can be verified or pinned for the coordinator and its workers.|

## 2. Roles

Every participant is exactly one of these at any moment:

- **Supervisor** — dispatches workers, verifies placement, waits, harvests
  results, cross-validates reports, schedules recovery. Never performs
  delegated work inline. The supervisor may discover context, parse plans,
  run read-only/check-mode verification commands, compare diffs, and
  summarize results.
- **Worker** — receives exactly one task spec, executes it, reports the
  outcome **exactly once** in its final message, then ends its turn and
  idles. A worker that also dispatches its own finer-grained sub-workers
  (e.g. an autonomous sub-ticket coordinator) acts as the supervisor for
  those dispatches.

**Never perform delegated work inline.** If a plan step is assigned the role
`implementer`, `explore`, or `reviewer`, that step **MUST** be dispatched to
a real worker before it executes. Delegation is a hard requirement, never a
suggestion. Batching several steps into one dispatch is allowed (see §5);
the dispatch itself is what is mandatory.

## 3. Interaction patterns

Three patterns exist. The invoking skill names which one applies:

1. **Fire-and-forget handoff** — the supervisor establishes the placement
   (harness-created, or worker-self-placed per the harness file), launches
   exactly one worker with an initial prompt, verifies acceptance
   once (the worker loaded its skill / started its turn), reports the worker
   handle to the user, and **stops supervising**. The new worker owns the
   work from there and becomes the supervisor of any further delegation.
   Never re-send the prompt (re-sending queues a duplicate follow-up in the
   worker's queue), never monitor, and never also run the delegated skill in
   the original session. On harnesses with `async-notification`, the worker
   may be spawned in the background so the session stays free; a completion
   notification arriving later is logged to the user and never resumes
   supervision — pattern 1 ended at acceptance. A harness that can only run
   workers synchronously (the supervisor blocks until the result returns)
   cannot honor pattern 1: stop and report that to the user instead of
   silently supervising to completion.
2. **Supervised dispatch loop** — dispatch → wait → harvest → cross-validate
   → recover (§4–§7). Used for every step the supervisor remains
   accountable for.
3. **Question/reply channel** (requires `question-channel`) — a worker
   needing a decision ends with an explicit QUESTION section and idles; the
   supervisor reads the question, answers through the harness reply
   mechanism (or escalates to the user first), and the worker resumes in its
   existing conversation. Never run the step yourself while the worker is
   active.

## 4. Dispatching workers

### Dispatch inputs

Every dispatch carries these inputs (the harness file maps them to its
actual tool/flags):

- `ROLE` — `implementer` | `explore` | `reviewer`
- `SLUG` — a readable, descriptive kebab-case identifier that tells the user
  from the worker list what the worker is doing: `add-export-filter-button`,
  `fix-form-validation-error`, `explore-auth-middleware`,
  `review-<capability>-diff`. Never `step-1`, `task-3`, `worker-42`, or bare
  `implement`. When batching, pick a slug that summarizes the batch (e.g.
  `add-column-and-regen-types`).
- `TITLE` — human-readable worker title where the harness supports one.
- `SPEC` — the full task-spec text (§4.1).
- `TIMEOUT` — explicit wait timeout passed to every worker start; default
  `900000` ms unless the invoking skill says otherwise. Do not rely on a
  shorter harness default. On mechanisms without a timeout knob, `TIMEOUT`
  instead bounds the supervisor's own checkpoints (e.g. how long it waits on
  a completion notification before inspecting).
- `PLACEMENT` — only when the dispatch carries a placement (capability
  `placement`): the exact branch, plus the workspace id and absolute
  worktree path when the supervisor pre-creates them. When the worker
  self-places (prompt-directed placement), `CHILD_BRANCH` is the invariant
  and the worker resolves and verifies its own worktree path.
- `EXPECTED_FILES` — the files the step is expected to touch (union when
  batching).
- `MAY_MODIFY` — `yes` for `implementer`; `no` for `reviewer` and `explore`.
- `SKILL_COMMAND` — the command the worker must invoke to run the delegated
  skill. Written in the canonical `/skill:<name> <arg>` form; on harnesses
  where workers invoke skills through a tool, the **worker** translates it
  to the equivalent invocation — the skill name and argument are invariant.

### Task spec template

Build every dispatched task from this template and pass it as the worker's
initial prompt. It is self-contained — the worker receives no other preamble
and must be able to discover nothing from ambient context.

```text
## Task: <title>
## Ticket: #<number>
## Plan step: <number and description>
## Role: <implementer|explore|reviewer>

## Placement contract (include only when the dispatch carries a placement)
WORKSPACE_ID=<exact worktree workspace id, when the harness has workspaces>
WORKTREE_PATH=<absolute worktree path>
CHILD_BRANCH=<exact branch, when this dispatch works on a dedicated branch>
<Verify with: pwd, git branch --show-current, git rev-parse --show-toplevel.
If any value does not match, stop and report a placement failure; do not edit
files.>

## Context
<relevant ticket and repository background>

## Constraints
<ticket decisions, best practices, AGENTS.md conventions, testing rules
(see §10), per-stack skill guidance when applicable>

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
see §8.>
```

### Placement verification (capability `placement`)

When a dispatch is anchored to a supplied worktree/workspace: after the
worker starts, verify — using the harness file's inspection mechanism — that
the worker's working directory equals `WORKTREE_PATH`, that its branch
matches `CHILD_BRANCH`, and that it is parented to the supervisor (or an
explicitly accepted host session). A worker that landed in the supervisor's
workspace, the main checkout, or another worker's workspace is a placement
failure: stop it, do not let it modify files, re-dispatch correctly.

When placement is prompt-directed (the worker self-places), the placement
contract in the task spec makes the worker perform the same checks itself:
after creating or entering its workspace, it must run `pwd`,
`git branch --show-current`, and `git rev-parse --show-toplevel`, compare
them against `WORKTREE_PATH`/`CHILD_BRANCH`, and report a placement failure
instead of editing files on mismatch. The supervisor cross-validates the
placement from the worker's first output before relying on any further
work.

### Preflight

Run the harness file's preflight once per session, before the first
dispatch. This includes daemon/app status, provider availability and
diagnostics, and — when the harness declares `model-pinning` — the
model-default gate (the coordinator's own model must match the configured
sub-agent default). Never print credentials, tokens, or secret configuration. Stop
before the first dispatch on any preflight failure with a precise report of
what must be installed, configured, or signed in. If a provider is available
but a specific model fails authentication at runtime, do not blindly retry:
diagnose per the harness file, select a working `provider/model` pair
explicitly, re-validate, and tell the user which model failed and what
replaced it.

## 5. Batching and parallel dispatch

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
  batches reviewable — if the combined diff would be hard to review, split
  it.
- **A medium step may batch with up to two simple steps.** Never two medium
  steps together.
- **When in doubt, don't batch.**
- A batched spec must enumerate every bundled step (own Files in scope and
  Acceptance criteria subsections); `EXPECTED_FILES` is the union; verify
  each step's criteria individually after completion. Record the
  classification rationale in one line per step so the user can audit it.

Dispatch independent steps concurrently only when all of these hold:

- **Disjoint files** — no two parallel workers edit the same file.
- **No shared mutable state** — steps mutating the same DB/migration state,
  generated artifacts, or `.env`/config are serialized. Before mutating
  shared infrastructure (databases, generated types, env), check project
  guidance for coordination rules; if none, ask the user how to coordinate.
- **No ordering dependency** — if B reads A's output, they are not
  independent.
- **Resource sanity** — keep the number of parallel workers small and
  observable.

Create all workers first — do not wait between dispatches. With
`async-notification`, each worker's completion notification arrives on its
own; never busy-poll the worker list to "check on" a running worker.
When in doubt, run sequentially. Parallel dispatch is an optimization, not a
requirement.

## 6. Wait and result-harvest discipline (mandatory)

A worker's completion contract is a **one-shot**: it reports once in its
final message, ends its turn, and idles. The completion surface is the
terminal state, harvested per the harness file.

1. **Inspect before waiting.** Use the harness file's inspection mechanism.
   Wait only when the worker is actually running (or a question is pending a
   reply). An already-idle, errored, or archived worker is not a waitable
   condition.
2. **Rely on the completion notification when available** (`async-notification`);
   move on to other work or reconcile state until then, and never busy-poll.
   Otherwise wait on the worker with the explicit `TIMEOUT`. A timeout is a
   checkpoint, not a verdict: inspect the real status before deciding
   anything.
3. **Never unbounded-wait a terminal worker.** Terminal states are idle,
   error, and archived. Harvest; never re-wait expecting resumption, and
   never send follow-up messages to a terminal worker expecting it to
   resume.
4. **Harvest from terminal state.** Read the final report from the harness
   file's log/state mechanism. This is a first-class capture path,
   equivalent to catching completion live.
5. **Cross-validate every result.** Independently validate the worker
   identity, the reported outcome, and the observed status against each
   other. A completed wait alone is never semantic completion: an idle
   worker whose report lacks required proof, or claims failure, is not a
   success.
6. **No active worker ⇒ no unbounded wait.** If no worker is running and no
   pending question requires a reply, reconcile state, harvest terminal
   outcomes, schedule a valid recovery dispatch, or stop with a precise
   report. Never sit in a wait with nothing waitable.

Terminal-state matrix:

| Worker state                   | Supervisor action                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------ |
| running                        | Await the completion notification (or wait with `TIMEOUT`); inspect liveness; answer pending questions. |
| idle with valid proof/report   | Harvest from logs/state; reconcile files/GitHub; continue. Do not retry.                               |
| idle without required proof    | Record protocol-invalid completion; schedule a fresh recovery dispatch in the preserved workspace/branch.|
| error                          | Diagnose via the harness inspection mechanism; schedule a fresh recovery dispatch.                     |
| archived / terminal            | Treat as history; reconcile via files/GitHub; never re-wait, never resume.                             |

Questions and escalations (capability `question-channel`): a worker needing
a decision ends with a QUESTION section and idles. The supervisor reads it
from the harvested output, answers through the harness reply mechanism (or
escalates to the user first), and resumes waiting. Never run the step
yourself while the worker is active.

## 7. Recovery

- A failed, protocol-invalid, or interrupted worker is **never** fixed inline
  and **never** resumed by sending it follow-up work. Recovery is a **fresh**
  dispatch, into the preserved workspace/branch, with full context of what
  exists (files changed so far, existing PRs to repair rather than replace).
- An existing canonical artifact (branch, PR) must be repaired or reused,
  never duplicated. Never create a second PR to fix the first.
- Healing budgets (how many recovery attempts are allowed before a work item
  is terminal) are owned by the invoking skill (e.g. the epic coordinator's
  two-attempts-per-child bound). This contract only mandates that fresh
  dispatches — not retries — are the recovery mechanism.

## 8. Completion proof

**Autonomous child workers** (a worker authorized to commit, push, and create
one PR without user confirmation) must include this block in their single
final success report. A success report without it is protocol-invalid:

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
changed, verification commands run and their outcomes, and any deviations
from the plan.

Implementation-only, verification-only, or review-only completion is never
successful autonomous completion. If any proof element is missing, the
worker reports failure with the exact blocking reason instead of a false
success.

After every implementer step the supervisor also runs `git diff --name-only`
and compares it to the declared expected files, flagging divergence.

## 9. PR description contract (canonical)

Every PR created under this protocol — a direct-mode ticket PR or an
autonomous child PR — must have a standalone comprehensive body. A reviewer
must be able to understand rationale, scope, approach, and key behavior
without opening the ticket. The ticket and plan are inputs, not substitutes
for documenting what the implementation actually did.

Compose the description **only after** implementation, verification, and
review, gathering facts from: the ticket/plan (problem, rationale, acceptance
criteria), the final diff (`git diff <base>...HEAD`), implementer reports and
verification output, and reviewer findings. Required sections, in this order
— write `None` / `Not applicable` rather than omitting:

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

<Known risks, migration/deployment considerations, deferred work. `None`
when there are none.>
```

Formatting and creation rules:

- Write real Markdown newlines — never literal `\n` sequences, JSON-escaped
  strings, or shell substitution that mangles line breaks. One blank line
  between blocks; use headings, bullets, and fenced code for commands.
- Prefer concrete file/module names and behavior over generic claims. Do not
  paste the entire diff. Call out breaking changes, security/auth
  implications, schema changes, and migrations explicitly when relevant.
- Before creating the PR, inspect the body file: `grep -nF '\n' "$PR_BODY"`
  must find nothing (literal escaped newlines), else rewrite the body.
- Create with
  `gh pr create --title "[#<number>] <commit subject>" --body-file "$PR_BODY"`
  — `<number>` is the linked ticket number (a sub-ticket's own number for
  epic child PRs, the epic number for the final epic PR) and
  `<commit subject>` is the short imperative subject of the primary commit.
  Then verify the rendered body with
  `gh pr view <url> --json body --jq .body` (rendered, not raw JSON). Repair
  with `gh pr edit` and re-verify if sections are missing or newlines were
  mangled.
- Autonomous workers never merge PRs and never close issues — unless the
  invoking skill explicitly grants that authority to a named role (only the
  epic coordinator currently has it).

## 10. Testing obligations for implementer specs

Every `implementer` task spec whose step changes code carries these
obligations, adjusted to what project discovery found:

- **Colocated unit/integration tests** for new pure functions, schemas,
  hooks when the project declares a colocated test layer (e.g. profile
  `test_layers`).
- **Component interaction tests** for new UI behaviors when the project's
  testing conventions declare component-level interaction tests (e.g. via a
  component workbench with `play` functions) — especially for stateful
  client components.
- **E2E tests** for user-facing flows when the project declares an e2e test
  layer (e.g. profile `test_layers`) and the flow is user-facing (check the
  project's testing docs for the golden path).
- **Skip only when justified:** the plan explicitly says no tests are needed
  AND the change is purely presentational with no new logic. Otherwise
  default to adding tests.
- Consult the project's testing docs for frameworks, mocking patterns, and
  assertion styles; follow existing test files as exemplars.

If a worker omits required tests, the supervisor dispatches a follow-up
`implementer` task to add them — never adds them inline.

### E2E browser verification (conditional)

Apply this section only when **both** hold; skip it entirely otherwise:

- the project declares an e2e test layer (e.g. profile `test_layers`), and
- the session exposes a browser tool (e.g. Playwright MCP or an equivalent).

The e2e layer may provide a persisted authenticated storage state for manual
browser verification of the golden path. To use it:

1. Resolve the e2e layer's location and config from the profile's
   `test_layers` slot (probe and announce the assumption if absent).
2. Ensure global setup has run so the storage state exists (consult the
   project's testing docs for the exact command).
3. After the e2e tests pass, use the browser tool to navigate the app and
   manually verify the flow — the session is authenticated automatically
   when the storage state exists. This is supervisor-side verification;
   record browser findings in the verification record.
4. To verify anonymous behavior, clear cookies or use an incognito context.

Never paste storage-state contents or session values into worker prompts;
see the project's testing docs for the full storageState details.
