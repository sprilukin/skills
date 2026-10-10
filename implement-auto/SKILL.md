---
name: implement-auto
description: "Use when implementing a validated GitHub Epic sub-ticket in autonomous mode through Orca-supervised delegation. This skill is invoked only by implement-epic; it commits, pushes, and creates the authorized child PR without user confirmation."
---

# Implement Auto

Implement exactly one validated native sub-ticket delegated by `implement-epic`.
This skill is autonomous mode only; it must never be used for ordinary direct
ticket implementation.

## Required autonomous gate

The invoking spec MUST contain exactly one literal `AUTONOMOUS_EPIC_SUBTICKET`
marker and exactly one `PARENT_EPIC=<GitHub epic issue number or URL>` plus
exactly one `SUBTICKET=<GitHub sub-ticket issue number or URL>`. Missing,
duplicated, ambiguous, or malformed values are a hard failure; do not infer
them from context. Report failure through the worker lifecycle.

The coordinator supplies the child branch/worktree based on the integration
branch. Preserve it across resume; never create a second branch or worktree.
The parent/sub-ticket relationship must be preserved in branch, PR, and
completion metadata.

The supplied worktree is also a mandatory Orca UI-group boundary. Work only in
the exact coordinator-supplied child worktree and its own Orca group. Never
fall back to `active`, `current`, the repository main worktree, or a terminal
in the main group. Before doing any work, verify the current absolute path,
Git branch, and Orca worktree/group identity against the injected contract. If
they do not match, stop and report a placement failure through the worker
lifecycle; do not edit files or create another worktree.

## Autonomous authorization and boundaries

The worker owns the complete autonomous child lifecycle without asking the user
for permission. The issue body's implementation plan is an input to this
lifecycle, not a stopping point. A successful worker must implement the plan,
verify it, perform the required delegated review, commit, push, create or
reconcile exactly one child PR, verify that PR, and then report completion.

The worker may commit, push, and create exactly one child PR without user
confirmation. The PR MUST target only the supplied integration branch, include
`Closes #<child>` and `Part of #<parent>`, use the comprehensive Phase 8
description contract, and be verified with `gh pr view` using the rendered body.
The worker must report a canonical URL and both identifiers in one successful
`worker_done` report.

Before modifying files, the worker must have and verify these concrete contract
values from the injected task specification:

```text
REPO=<repository name with owner>
WORKTREE_SELECTOR=<exact Orca selector>
WORKTREE_PATH=<absolute path>
CHILD_BRANCH=<exact child branch>
INTEGRATION_BRANCH=<exact integration branch>
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native child number or URL>
```

Before creating the PR, the worker must verify that `INTEGRATION_BRANCH` exists
on the expected GitHub remote and is the exact allowed PR base. A local-only or
ambiguous base branch is a blocking failure; the worker must report it and stop
rather than guessing, creating a new branch, or creating a PR against another
base.

This skill never merges a PR, closes an issue, deletes a worktree, repairs a PR
outside a dispatched implementer task, or performs delegated work inline.
Reconcile every existing PR claiming the child/parent or supplied branch:
exactly one canonical valid PR may exist. Invalid, duplicate, ambiguous, draft,
conflicting, incorrectly based, incorrectly linked, or failed-check candidates
are terminal failures; never create another PR.

A `worker_done --outcome succeeded` report is forbidden until all of these
proofs exist and are included in the report body:

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

Implementation-only, verification-only, or review-only completion is not
successful autonomous completion. If implementation succeeds but commit,
push, PR creation, PR verification, or any proof is missing, report
`worker_done --outcome failed` with the exact blocking reason. Do not leave the
worker at a supposed success state for the coordinator to finish manually.

If creation or verification fails, report failure and end the worker turn. Do
not retry inside the same Dispatch and do not create a second PR. Recovery is a
new coordinator-owned implementer Dispatch in the preserved worktree and
branch; an existing canonical PR must be repaired or reused rather than
replaced.

## Autonomous child lifecycle (mandatory)

The worker must follow this order unless the coordinator's recovery spec
explicitly identifies a later stage to resume:

1. Verify the Orca placement and all injected repository/branch/worktree values.
2. Reconcile existing child/parent PR candidates before making a new one.
3. Implement the complete child plan and any required tests or generated output.
4. Run the plan's verification commands and fix failures through fresh Orca
   implementer Dispatches as required by this skill.
5. Run the required read-only Orca reviewer and address blocking findings through
   a fresh implementer Dispatch.
6. Commit the final verified changes and push `CHILD_BRANCH`.
7. Reconcile or create exactly one canonical PR targeting `INTEGRATION_BRANCH`.
8. Verify the rendered PR body, metadata, branch, base, and required status.
9. Send exactly one worker_done result with the completion proof, then end the
   turn and idle.

## Non-negotiable delegation contract

Delegation in this skill is **mandatory, never optional**. If delegation is
mentioned anywhere in this skill, the ticket plan, or a delegated task spec,
it is a hard requirement: the work **MUST** be dispatched to a real worker
through Orca orchestration. If a plan step is assigned the role
`implementer`, `explore`, or `reviewer`, the coordinator **MUST dispatch that
step through Orca orchestration before executing the step**. Do not interpret
"delegate", "use Orca", or "via Orca" as a suggestion, permission, or optional
path.

The only permitted delegation path is:

1. Read/use the global `orca-cli` skill for Orca executable resolution and the
   live, version-matched CLI guide.
2. Read/use the global `orchestration` skill for the Run, Task, Dispatch,
   lifecycle, wait, ask/reply, and completion contract.

These skills own the exact shell commands. **Do not copy or reconstruct their
Orca command sequences in this skill.** If this project skill and the live,
version-matched orca guide disagree on mechanics, the live orca guide wins
(it is version-matched to the installed binary). This skill only owns the
WHAT: which step, which role, which spec content, which order.

### Mandatory rules

- **Never perform delegated work inline.** The coordinator may discover
  context, select a ticket, parse a plan, run read-only/check-mode
  verification commands, compare diffs, and summarize results. It must not
  implement, explore, fix, or review code that belongs to a delegated step.
- **Every implementation step is dispatched, but may be batched.** A
  plan step labeled `implementer` must go to an Orca worker (never done
  inline), even if it looks trivial. However, multiple steps may be combined
  into a single Orca dispatch according to the **Complexity assessment and
  batching** rules in Phase 4 — trivial/simple steps need not each get their
  own worker. The dispatch (not the inline execution) is what's mandatory.
- **Every exploration step is dispatched.** For an unstructured ticket, the
  required repository exploration must be an Orca `explore` dispatch before a
  plan is proposed.
- **Every fix is dispatched.** A failed verification or blocking review
  finding requires a new Orca `implementer` dispatch. Never apply the fix in
  the coordinator terminal.
- **The code review is dispatched.** The pre-commit review must be an Orca
  `reviewer` dispatch; it is not an inline review and is not optional.
- **No substitute delegation.** Do not use a generic subagent API, OpenCode
  spawn, chat-only worker, ad-hoc PTY, or direct `terminal send` as a
  replacement for the supervised Orca dispatch contract.
- **No inline fallback.** If Orca is unavailable, cannot be started, or
  orchestration is disabled, stop and tell the user. Ask whether to abort or
  enable Orca. Do not proceed inline. Never ask permission to proceed inline.
- **No unvalidated provider fallback.** Before dispatch, validate `AGENT` as
  required by the Worker provider and readiness preflight. If it is missing,
  unauthenticated, or cannot start, stop; do not substitute another provider,
  launch a bare shell, or retry the same failed start without changing the
  diagnosed cause.
- **Reviewer and explorer workers must not modify files.** A `reviewer`
  worker reports findings only; an `explore` worker produces a report only.
  Only `implementer` workers may change code. Set `MAY modify files: no` in
  reviewer/explorer task specs.
- **Unassigned code-changing steps default to `implementer`.** If a plan
  step changes code but names no role, classify it as an `implementer` step
  and dispatch it.
- **Generated-code regeneration is a dispatched task.** If a step changes
  schema, migrations, or generated artifacts (types, ORM clients, SDKs),
  either include the regeneration in the same `implementer` task's acceptance
  criteria or dispatch a new `implementer` task for it. Never regenerate by
  making an unassigned code change in the coordinator.
- **Completion is proven by Orca.** Do not declare a worker step complete
  from terminal output alone. Require the `worker_done` result AND the
  orchestration skill's completion verification (dispatch status `completed`) for
  that Task/Dispatch.
- **Handle `worker_done --outcome failed` explicitly.** If a delegated
  implementer/reviewer/explorer step fails, report the failure through the
  active Dispatch lifecycle and let the coordinator decide whether to create a
  fresh recovery Dispatch. Do not declare the step done and do not fix it
  inline or silently retry it.
- **Preserve ownership boundaries.** The coordinator routes work and
  supervises; it does not edit delegated code. An `implementer` worker owns
  code fixes. A `reviewer` worker reports findings.

### What this skill keeps vs. delegates

| Owned by                  | Decisions                                                                                                                                                                                                                                                                                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This skill (the WHAT)     | Which ticket, which plan steps, step role, the Task Spec content, expected files, validated worker provider, explicit timeout, sequential vs. parallel order, shared-infrastructure coordination, verification order, review/commit/PR/close gating.                                                          |
| The orca skills (the HOW) | ORCA resolution; verifying Orca is running; creating/binding the session Run; the per-step dispatch sequence (worker readiness, `dispatch --inject`, `worker-start`); waiting on `worker_done`/`escalation`/`question`; replying; `dispatch-show` verification; parallel dispatch; terminal/worktree cleanup. |

### Delegation rules (mandatory — not optional)

- **Never run `orca ...` commands from memory or from this file.** This file
  intentionally does NOT inline orca command syntax (no `run-create` flags, no
  `worker-start` flags, no `check --wait` flags, and no `--run` assumptions).
  Resolve ORCA, load the guides named above, and use the exact flags they
  print for the installed Orca version. Inlining here would drift the moment
  Orca ships a new grammar.
- **"Delegate to the orca skills" means: load the named skill, read it, and
  follow its recipe exactly.** It does NOT mean "you may optionally consult
  it" or "use it as inspiration." Some harnesses treat "delegate to X" as a
  soft suggestion — it is not.
- **Do not improvise a recipe.** The loaded orca guide is authoritative for
  the HOW. This skill only owns the WHAT.

## Session setup — delegate to the orca skills (run once per session)

Before the first delegated step, do this ONCE. The exact commands live in the
orca skills — load them and follow their syntax (do NOT copy flags from here,
and do NOT assume specific flag names such as `--run`):

1. **Resolve ORCA and confirm the app is running** (`orca-cli` skill: `status`,
   `open` if needed).
2. **Create or bind the session Run once** (`orchestration` skill: `run-create`
   with the ticket title as the objective). Reuse its Run id for every task in
   this session. Do NOT recreate the Run per step.
3. **Confirm orchestration is functional** (`orchestration` skill: `task-list`,
   scoped to the Run you just created). A `run_required` response is a
   **setup-order issue** (the Run is not yet bound), not proof that
   orchestration is disabled — bind/reuse the Run and retry. Only if
   orchestration commands are entirely unavailable (a non-`run_required`
   failure) is orchestration disabled: tell the user to enable it in Orca
   Settings > Experimental and **stop**. Do not proceed inline.

Do NOT inline the `run-create` / `task-list` flags here.

### Worker provider and readiness preflight — mandatory

Before the first `worker-start`, choose and validate the worker provider once for
this session. The repository's default provider is **`pi`**; use it unless the
user explicitly requests another provider. Do not copy `codex` (or another
provider) from an Orca guide example without checking this host first.

There are two readiness regimes. Run only the checks for the selected agent's
regime; never run the other regime's checks.

- **Local TUI agents** (`pi`, `opencode`, `omp`, `gemini`, `grok`, `aider`, …
  — any agent Orca launches as a local executable): validate only with
  `command -v <agent>` and `<agent> --version`. Do NOT run `orca account list`
  or any managed-account diagnostic for these. `orca account` manages only
  Claude and Codex accounts, so missing Claude/Codex managed accounts must
  never block a `pi`/`opencode`/etc. session.
- **Managed-account agents** (`claude`, `codex` only): in addition to the
  executable check, run `orca account list --json` and require at least one
  signed-in managed account of that type before dispatch. Never print
  credentials, tokens, or secret configuration.

The coordinator MUST:

1. Confirm that the selected agent's executable is present on `PATH` and can
   report its version without prompting for credentials. For the repository
   default, this means `command -v pi` and `pi --version`.
2. Only when the selected agent is `claude` or `codex`, also confirm a
   signed-in managed account via `orca account list --json`. Do not run this
   check for `pi`, `opencode`, or any other local TUI agent; a missing
   Claude/Codex managed account is not a failure for those agents.
3. Stop before creating implementation dispatches if the executable is absent,
   the selected agent is `claude`/`codex` and no managed account is signed in,
   or `worker-start --agent <agent>` fails. Tell the user exactly which agent
   is unavailable and what must be installed, configured, or signed in. Do not
   silently switch agents, dispatch a bare shell, or retry blindly.

Use the validated agent as `AGENT` for every worker in this session unless
the user explicitly changes the agent and the replacement passes the same
preflight. Pass `TIMEOUT_MS=900000` explicitly to every worker start; do not
rely on Orca's shorter CLI default of 60000 ms.

### Per-step dispatch — delegate the mechanics

For every step this skill tells you to dispatch, run this delegation (the
mechanics live in the orca skills):

1. Build the Task Spec content from the **Task Spec Template** below (the
   WHAT).
2. Follow the orchestration skill's "Preferred Supervised Worker Loop" using
   the coordinator-supplied Orca-managed child branch/worktree. Preserve it on
   resume and never create another one. The `--worktree` input must be the
   exact existing child-worktree selector/path, not `current` or `active`.
   Orca must create the delegated terminal in that child worktree's own UI
   group; verify the worker-start receipt and terminal listing before allowing
   the worker to proceed. If the terminal is in the main group or a different
   worktree, stop and report a placement failure.
3. Pass these inputs (the `orchestration` skill's dispatch inputs): `STEP_N`, `SLUG`,
   `ROLE` (`implementer`|`explore`|`reviewer`), `TITLE`, `SPEC` (from the
   template), `AGENT` (the validated session provider, `pi` by default),
   `TIMEOUT_MS` (explicitly `900000` by default), `WORKTREE` (the supplied
   child worktree), and `EXPECTED_FILES` (the step's "Files affected" list). For `reviewer` and
   `explore` steps, set `MAY modify files: no`.

   **`SLUG` must be a readable, descriptive kebab-case identifier** that
   conveys the purpose of the dispatched sub-agent — not a generic
   `worker-task_<n>`-style slug. Make it short but understandable enough
   that the user can tell from the terminal/task display what this worker is
   doing. Examples: `add-export-filter-button`,
   `fix-form-validation-error`, `explore-auth-middleware`,
   `review-<capability>-diff`. Avoid slugs like `step-1`, `task-3`,
   `worker-42`, or `implement`. If batching multiple steps into one
   dispatch, pick a slug that summarizes the batch
   (e.g. `add-column-and-regen-types`).

4. Let the orca skills own the wait → handle result → verify sequence
   (`check --wait` on `worker_done`/`escalation`/`question`, `reply` for
   escalations/questions, `dispatch-show` status `completed`), **subject to the
   Sub-Dispatch wait and result-harvest discipline below.** A sub-worker's
   `worker_done` is a one-shot: it sends it once, ends its turn, and idles, and
   the Dispatch then auto-transitions to terminal. Do not declare the step done
   until the orca skill's verification passes AND the discipline's
   terminal-state checks pass.
5. **On `worker_done --outcome failed`:** report the failure through the
   active Dispatch lifecycle and let the coordinator decide whether to create
   a fresh recovery implementer Dispatch. Do not declare the step done, fix it
   inline, or silently retry it.
6. After completion, run `git diff --name-only` and compare to
   `EXPECTED_FILES`; flag any divergence to the user.

### Sub-Dispatch wait and result-harvest discipline (mandatory)

This skill is both a worker (in its parent epic's Run) and a coordinator of its
own finer-grained sub-Dispatches (implementer/reviewer/explore workers in this
session's Run). The sub-worker completion contract is a **one-shot**: each
sub-worker sends `worker_done` exactly once, ends its turn, and idles, and the
Orca Dispatch then auto-transitions to a terminal state (`completed` on
succeeded or failed). The `worker_done` message is a transient lifecycle event;
if this skill is not waiting at the exact moment it fires, `check --wait` will
miss it and then block forever on a Dispatch that will never emit another
lifecycle message. The defenses below are mandatory whenever this skill waits
on a sub-Dispatch. They mirror the parent epic coordinator's discipline but
apply to _this_ skill's own sub-dispatches.

1. **Inspect before every wait.** Before issuing `check --wait` on a
   sub-Dispatch, query its state with `task-list` (scoped to this session Run)
   or `dispatch-show`. Wait only when the target Dispatch is still `ready` or
   `dispatched`, or when a worker `ask`/`escalation` is explicitly pending a
   reply. A visible or idle terminal is not a waitable condition.
2. **Never unbounded-wait on a terminal sub-Dispatch.** If the sub-Dispatch is
   already `completed`, `failed`, `stopped`, or `outcome_unknown` when you
   inspect, do NOT call `check --wait` on it and do NOT send it follow-up mail
   expecting it to resume — it is terminal and will never emit another
   lifecycle message. Treat its terminal as an idle surface, not an active
   worker.
3. **Harvest the outcome from terminal state.** When a sub-Dispatch is already
   terminal (the one-shot `worker_done` fired before you waited), read the
   `outcome`, `filesModified`, and any completion proof directly from the
   Dispatch's terminal state via `dispatch-show`. This harvest path is a
   first-class result-capture method, equivalent to catching `worker_done`
   live via `check --wait`. Do not treat a missed one-shot as a hung step.
4. **Cross-validate every result.** After every captured `worker_done` (live
   via `check --wait`) **or** every terminal-state observation (harvested via
   `dispatch-show`), independently validate the Task/Dispatch IDs, the worker
   `outcome`, and the Dispatch status against each other. Orca lifecycle
   completion alone is never semantic step completion: a `completed` Dispatch
   with a `failed` outcome, or with `outcome_unknown`, is not a success.
5. **Act on the terminal-state matrix for sub-Dispatches:**

   | Sub-Dispatch state                                        | Coordinator (this skill) action                                                                                                   |
   | --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
   | `ready` or `dispatched`                                   | `check --wait`; inspect liveness; answer a pending `ask`/`escalation`.                                                            |
   | `completed` with valid `worker_done` proof                | Harvest proof from state; reconcile files; continue. Do not retry.                                                                |
   | `completed` without required proof (or `outcome_unknown`) | Record protocol-invalid completion; create a fresh recovery `implementer` Dispatch in the preserved worktree/branch.              |
   | `failed` or `stopped`                                     | Use the live orca guide's retry path only when it explicitly allows it; otherwise create a fresh recovery `implementer` Dispatch. |
   | terminal (any of the above terminal states)               | Never re-wait, never mail it expecting resumption, never treat the idle terminal as an active worker.                             |

6. **No active sub-Dispatch ⇒ no unbounded wait.** If no sub-Dispatch is
   `ready`/`dispatched` and no pending `ask`/`escalation` requires a reply, do
   not enter an unbounded wait. Reconcile Run/Task/Dispatch state, harvest any
   terminal outcome, schedule a valid recovery Dispatch, or stop this skill's
   own `worker_done` with a precise `--outcome failed` report. Never sit in
   `check --wait` with nothing waitable.

This discipline does not change the sub-worker's one-shot contract — it changes
_this_ skill's consumption of it. The sub-worker still sends `worker_done`
exactly once and idles; this skill must be prepared to harvest that result from
terminal state instead of assuming it will always catch it live.

### Task Spec Template — the WHAT for every delegated step

Build the spec from this template and pass it as the SPEC input to the
orchestration skill's dispatch recipe (the orca skills handle `task-create` / `dispatch
--inject`). Copy and fill in:

```
## Task: <title from plan step>
## Ticket: #<number>
## Plan step: <step number and description>
## Role: <implementer|explore|reviewer>

## Context
<relevant background — what the feature does, what exists already>

## Constraints
<from "Best practices researched" in the ticket>
<project conventions from AGENTS.md that apply>

## Files in scope
<list files and directories this step may touch>

## You MAY modify files: <yes|no>
(yes for implementer; no for reviewer and explore)

## Expected output
<what the worker should produce — new files, modified files, a report>

## Acceptance criteria
<how to verify the work is correct — specific checks>
<if this step regenerates generated artifacts, state the regen command here>

## Completion
Follow the injected lifecycle preamble (provided by `--inject` per the
orchestration skill) as AUTHORITATIVE for `worker_done`, `ask`, and
`heartbeat` — it supplies the exact command syntax, task/dispatch IDs, and
coordinator identity. As a reminder of the contract (not the syntax): send
`worker_done` exactly once and then end your turn and idle. Use
`--outcome succeeded` only after the complete autonomous child lifecycle and
all `COMPLETION_PROOF` fields above have been satisfied. Use
`--outcome failed` for any implementation, verification, review, commit, push,
PR, base-branch, or metadata failure, and include the exact blocking reason.
If blocked before completion and a coordinator decision is required, use
`ask` (it defaults to your owning Run, so omit the recipient). Do NOT
substitute IDs manually — the preamble provides them. Do not send a success
report that says the coordinator still needs to commit, push, or create the PR.
```

The `--inject` flag (orca skills) fills in the task/dispatch IDs and
coordinator identity from the dispatch context. You do NOT substitute them
manually in the spec.

---

## Workflow

### Phase 0 — Discover project context (run once, reuse throughout)

**Resolve every project fact through the resolution ladder:** (1) read the
`.agents/project.yaml` profile slot when present (authoritative for facts);
(2) if the slot is absent or stale, probe generically and announce the
assumption; (3) if ambiguous, stop and ask the user — never silently guess.

Run these in parallel:

1. **Repo info** (uses the logged-in `gh` CLI):
   ```
   gh repo view --json nameWithOwner,defaultBranchRef,description
   ```
2. **Project guidance:** read the root `AGENTS.md` first — it documents
   project conventions, nested AGENTS.md locations, and non-obvious
   gotchas — plus nested `AGENTS.md` files (locations declared by project
   guidance, else probe), `README.md`, and docs from the profile's
   `layout.docs` slot (else probe). Read `openspec/specs/` if the ticket
   touches a capability area. These document project conventions — treat
   them as authoritative.
3. **Workspaces, manifests, and commands:** map workspaces and config
   files. Use the profile's `layout.workspaces` slot when present (else
   probe manifests and package configuration, and announce the
   assumption). Read the manifests/config files that exist (package
   manifests, tsconfig, test-runner and lint/format configs) to detect
   language/toolchain; record available lint, typecheck, test, format,
   and build commands from the profile's `commands` section (else from
   manifest scripts).
4. **Migrations and generated code:** read the profile's
   `layout.migrations_dir` and `layout.generated_files` slots (probe and
   announce the assumption if absent or stale). Each generated file
   regenerates via its declared `regenerate_command`, run from its
   declared `regenerate_cwd`.
5. **Test layers:** read the profile's `test_layers` slot (probe test
   configs and announce the assumption if absent) to learn which test
   layers exist, where they live, and their CI policy.
6. **In-repo platform docs:** note documentation paths from the profile's
   `layout.docs` and `layout.vendored_platform_docs` slots (probe
   references in project guidance and announce the assumption if absent)
   for reference during implementation.

Cache everything from Phase 0. Reference it in all later phases. If any
discovery step fails (e.g. `gh` not authenticated), surface the error and ask
the user how to proceed before continuing.

### Phase 1 — Pick the ticket

**If the user gave a rough description:**

```
gh issue list --state open --limit 30 --search "<description>"
```

Show the top 3–5 matches (number, title, labels). Ask the user which one is
the target. Do not assume.

**If the user gave no description:**

```
gh issue list --state open --limit 5
```

Show the 5 tickets (number, title, labels, first 200 chars of body). Ask the
user which one to work on.

After selection, fetch the full body:

```
gh issue view <number> --json number,title,body,labels,url
```

### Phase 2 — Parse the plan

If the body follows the `plan-feature` template (Context, Best practices
researched, Dependencies, Implementation decisions, Implementation plan,
Verification plan, Rollback plan, Decision completeness):

- Extract the **Implementation plan** steps and their subagent assignments.
  Treat every `implementer`, `explore`, or `reviewer` assignment as a
  **mandatory Orca dispatch**, not an instruction the coordinator may
  perform.
- Extract the **Verification plan** commands. If any command is listed as
  `n/a` or missing, fall back to the corresponding command discovered in
  Phase 0.
- Keep the **Rollback plan** handy in case something breaks.

If the body is NOT a structured plan (e.g., a free-form issue):

- Summarize what it asks for.
- **MUST dispatch an Orca `explore` worker** via the orca skills (Per-step
  dispatch section above) to identify affected files and existing patterns
  (use the same research rules as `plan-feature` — read instruction files,
  in-repo platform docs, manifests; web-search only when local patterns are
  missing). The explorer must not modify files.
- Use the verified exploration report to propose a step-by-step plan to the
  user. **Get explicit confirmation before implementing.**

If the ticket lacks a **Decision completeness** section, or contains unresolved
questions, `TBD` values, pending choices, or user-directed decisions, stop and
ask the user to resolve them before continuing. Do not dispatch implementation
work around an unresolved product or technical decision.

### Phase 3 — Confirm branch and shared services

Use only the coordinator-supplied child worktree and branch. Never create or
delete worktrees.
Orca-managed child branch/worktree based on the supplied integration branch.
Preserve that branch/worktree across resume and never create a second one.

Before mutating shared infrastructure (databases, generated types, env) —
including starting or resetting shared local service instances — check
project guidance for coordination rules; if none, ask the user how to
coordinate.

### Phase 4 — Execute via Orca orchestration (delegate the mechanics)

Before the first step that mutates shared infrastructure (databases,
generated types, env) — including starting or resetting shared local
service instances — check project guidance for coordination rules; if none,
ask the user how to coordinate. Never let two workers mutate shared
infrastructure concurrently.

For each step in the Implementation plan, **delegate via the orca skills**
(Per-step dispatch section above). Use the Task Spec Template for the spec
content. If a plan step changes code but names no role, classify it as an
`implementer` step and dispatch it.

#### Complexity assessment and batching

Before dispatching, the coordinator assesses the **complexity** of each
plan step and decides whether steps are dispatched individually or batched
into a single Orca worker. Batching is a scheduling optimization — the work
is still dispatched to an Orca worker (never done inline); multiple steps
just share one worker/dispatch.

Classify each step as **simple**, **medium**, or **hard**:

- **simple** — small, isolated, low-risk: e.g. a single pure-function or
  type-only change, a one-file rename, a small copy/config tweak, adding a
  missing import, or a trivial presentational tweak.
- **medium** — moderate scope touching a few files or one non-trivial
  component: e.g. a new small feature, a server action + its call site, a
  migration + the code that reads the new column, or a component with state.
- **hard** — large, cross-cutting, high-risk, or architecturally
  significant: e.g. multi-file feature work, auth/session changes, RLS
  policy work, refactors across modules, anything requiring schema + types +
  app code + tests together, or anything with non-obvious failure modes.

Batching rules (governed by execution order — only batch steps whose order
allows them to run together in one worker without depending on a later
step's output first):

- **Hard steps are always dispatched alone** as a single Orca worker. Never
  batch a hard step with anything else.
- **Simple steps may be batched** together into one Orca worker when their
  execution order allows (no dependency forcing them apart). There is no
  fixed cap, but keep batches reviewable — if the combined diff would be hard
  to review, split it.
- **A medium step may be batched with up to two simple steps** in one Orca
  worker, again only when execution order allows it. Do not batch two medium
  steps together.
- **Independent steps that can run in parallel should be dispatched in
  parallel** rather than batched sequentially — see "Parallel steps" below.
  Batching is for steps that must run sequentially in one worker; parallel
  dispatch is for steps that can run concurrently in separate workers.
- **When in doubt, don't batch.** A hard step or a step with non-obvious
  acceptance criteria is always safer alone. Batching is an optimization for
  genuinely trivial, ordered work.

When batching, the Task Spec must enumerate every bundled step clearly
(each with its own Files in scope and Acceptance criteria subsections), the
combined `EXPECTED_FILES` is the union of all bundled steps' files, and the
`SLUG` summarizes the batch (see the SLUG guidance above). Verify each
bundled step's acceptance criteria individually after the worker completes.

Classification is the coordinator's judgment call — record the rationale
briefly (one line per step is enough) so the user can audit the batching
decision. If the user asks to keep a step separate, honor it without
argument.

#### 4a. Delegate the step

Dispatch the step following the `orchestration` skill's supervised worker
loop, with these role-specific
spec contents:

- For `implementer` steps: pass the constraints from "Best practices
  researched" and the "Files affected" list in the task spec.
- For `reviewer` steps: pass the current diff (`git diff`), the ticket
  constraints, and project conventions. Set `MAY modify files: no` — the
  reviewer reports findings only and must not edit the implementation. Use
  the active/current worktree.
- For `explore` steps: pass the question to investigate and the relevant
  files/directories. Set `MAY modify files: no` — the explorer produces a
  report only.

#### 4b. Collect and parse results

Capture the `worker_done` payload by whichever path the Sub-Dispatch wait and
result-harvest discipline permits: live via `check --wait` when you caught the
one-shot, or harvested from the terminal Dispatch via `dispatch-show` when the
Dispatch was already `completed`/`failed`/`stopped` by the time you inspected.
Never re-`check --wait` a terminal sub-Dispatch.

From the `worker_done` payload (the orca skills surface this from
`check --wait` / `dispatch-show`), extract:

- `outcome` — `succeeded` or `failed`
- `filesModified` — list of files the worker changed
- Summary — what was done

**If `outcome` is `failed`:** report the failure through the active Dispatch
lifecycle and let the coordinator decide whether to create a fresh recovery
implementer Dispatch. Do not declare the step done, fix it inline, or silently
retry it.

If the worker reported a block via `escalation` or `question`, answer or ask
the user, then continue the orca skills' wait/reply loop. Do not run the
step yourself while the worker is active.

#### 4c. Verify files

After each `implementer` step, run:

```bash
git diff --name-only
```

Compare against the step's "Files affected" list. Flag any divergence to the
user.

#### 4d. Post-step tasks

- If a step modifies database schema/migrations or generated code (types,
  ORM clients, SDKs), the regeneration MUST be a dispatched task: either
  include the regen command (resolved via the profile's
  `layout.generated_files` `regenerate_command`) in the same
  `implementer` task's acceptance criteria, or dispatch a new `implementer`
  task to regenerate. Never regenerate by making an unassigned code change in
  the coordinator.
- If implementation diverges significantly from the plan (new files,
  different approach), STOP and confirm with the user before dispatching
  dependent work.

If the feature touches DB/auth/RLS, include the per-stack skill declared by
the profile's `stack` section (e.g. the installed `supabase` skill) in the
worker's constraints for best-practice guidance. The per-stack skill does
NOT replace Orca dispatch — the worker still MUST run through the orca
skills. Only invoke a per-stack skill if it is actually installed.

#### Testing during implementation

Include testing obligations in every implementer task specification. Check
the project's testing conventions — the profile's `test_layers` slot plus
project testing docs (discovered in Phase 0) — and require tests
accordingly:

- **Colocated unit/integration tests** — if the project declares a colocated
  unit/integration test layer in `test_layers`, require tests for new pure
  functions, schemas, or hooks introduced by the step.
- **Component interaction tests** — if the project's testing conventions
  declare component-level interaction tests (e.g. via a component workbench
  with `play` functions), require interaction tests for new UI behaviors
  (e.g. optimistic updates, form validation, error states). These are
  especially valuable for stateful client components that can't be
  unit-tested in isolation.
- **E2E tests** — if the profile's `test_layers` includes an e2e layer and
  the feature is a user-facing flow, consider an e2e test. Check the
  project's testing docs for the golden path.
- **Skip tests only when justified** — if the ticket plan explicitly says
  "no tests needed" AND the change is purely presentational with no new
  logic, skip. Otherwise, default to adding tests.

If a worker omits required tests, dispatch a follow-up `implementer` task
(via the orca skills) to add them. Do not add them inline. Consult the
project's testing documentation (e.g. `docs/testing.md`, `AGENTS.md` testing
section) for conventions on test frameworks, mocking patterns, and assertion
styles, and follow existing test files as exemplars.

#### E2E browser verification (conditional on `test_layers`)

Apply this section only if the profile's `test_layers` includes an e2e layer
(or a generic probe discovers one and you announced the assumption); skip it
entirely otherwise.

The e2e layer may provide a persisted authenticated storage state for manual
browser verification (e.g. via Playwright MCP or an equivalent browser
tool). To use it:

1. Resolve the e2e layer's location and config from the profile's
   `test_layers` slot (probe and announce the assumption if absent).
2. Ensure global setup has run so the storage state exists (consult the
   project's testing docs for the exact command).
3. Use the browser tool to navigate the app — the session is authenticated
   automatically when the storage state exists.
4. To test anonymous behavior, clear cookies or use an incognito context.

See the project's testing docs for the full storageState details.

#### Parallel steps — delegate per the orca skills

When the plan has multiple **independent** steps (no dependencies between
them), dispatch them concurrently instead of sequentially — batching is for
ordered work; parallel dispatch is for concurrent work. Delegate the
parallel mechanics to the orca skills: create all tasks on the session Run
first, then start all independent workers (`worker-start`), then wait on
completions with `check --wait` — do NOT wait between dispatches. Apply the
Sub-Dispatch wait and result-harvest discipline to each parallel sub-Dispatch:
a sub-Dispatch may have auto-completed while you were starting its siblings,
so inspect each one's state before waiting and harvest any terminal outcome
instead of unbounded-waiting. See the
`orchestration` skill's supervised loop for the exact sequence. Do not use generic parallel
subagents or direct terminal prompts.

**Parallel workers must not interfere with each other.** Before dispatching a
set in parallel, confirm the steps are safe to run concurrently:

- **Disjoint files.** No two parallel workers should edit the same file, or
  you'll get merge conflicts / clobbered diffs in the shared worktree. If
  steps touch overlapping files, run them sequentially (or batch them in one
  worker) instead.
- **No shared mutable state.** Steps that mutate the same DB/migration
  state, the same generated artifacts, or the same `.env`/config are not
  safe in parallel — serialize them. Before mutating shared infrastructure
  (databases, generated types, env), check project guidance for
  coordination rules; if none, ask the user how to coordinate.
- **No ordering dependency.** If step B reads or builds on step A's output,
  they are NOT independent — run A first, then B. Parallel is only for truly
  independent steps.
- **Resource limits.** Don't spin up more parallel workers than the machine /
  Orca session can handle sanely. Keep batches small and observable.

When in doubt, run sequentially. Parallel dispatch is an optimization, not
a requirement.

Monitor progress at any time via the orchestration skill's `task-list`.

### Phase 5 — Verify (stop on first failure, fix via Orca, re-run)

Determine the commands to run from the plan's Verification section first; fall
back to commands discovered in Phase 0 if the plan says `n/a` or omits one.
Run in this order:

1. Lint
2. Typecheck (skip if the language has no separate typecheck step)
3. Format check
4. Tests (if any — use the plan's test command, or the manifest's test
   command, or "no test changes" if neither applies)

The coordinator may run these read-only/check-mode verification commands. If
any step fails, **MUST dispatch an `implementer` step via the orca skills**
(Per-step dispatch section above) to fix it, then re-run verification. Do NOT
skip. Do NOT fix failures inline. Do NOT commit with failing lint/typecheck.

### Phase 6 — Code review via Orca (delegate the reviewer)

After verification passes and before proposing a commit, run a code review on
the full diff of changes made in this session.

1. Generate the diff:

   ```bash
   DIFF=$(git diff HEAD 2>/dev/null || git diff)
   ```

2. **MUST dispatch a `reviewer` step via the orca skills** (Per-step dispatch
   section). Review is mandatory; it is not an optional handoff and must not
   be performed inline. Use the active/current shared worktree in autonomous mode,
   or the coordinator-supplied child worktree in autonomous epic sub-ticket
   mode (the reviewer needs the current diff). Set `MAY modify files: no`. In
   the task spec, include:
   - The diff content (or instruct the worker to run `git diff` in the
     worktree)
   - The ticket's "Best practices researched" constraints
   - Project conventions from Phase 0
   - Review focus: bugs and logic errors, security issues (secrets,
     injection, auth bypass, missing validation), performance problems
     (N+1 queries, unnecessary rerenders), maintainability (naming,
     complexity, duplication, error handling), and adherence to project
     conventions + the ticket's acceptance criteria

3. Surface the review findings to the user. If the reviewer reports any
   blocking issues (bugs, security, broken conventions), **MUST dispatch an
   `implementer` step via the orca skills** to address them, then re-run
   Phase 5 (Verify) + Phase 6 (Review) until clean. Do not let the reviewer
   edit the implementation. Non-blocking suggestions may be deferred only
   with the user's explicit decision — ask which to address now.

4. Do NOT proceed to the commit summary until either the review is clean or
   the user explicitly accepts the remaining findings.

### Phase 7 — autonomous commit and child PR

This mode is not user-gated. Do not ask for commit confirmation, push
confirmation, PR confirmation, or issue-closure confirmation. Do not stop at a
summary for the coordinator to finish. After verification and review are clean:

1. Commit the approved files with a ticket-linked message.
2. Push the supplied `CHILD_BRANCH`.
3. Reconcile every existing PR candidate claiming the child, parent, or supplied
   branch. If exactly one canonical PR exists, verify and reuse it. If none
   exists, create exactly one comprehensive child PR targeting
   `INTEGRATION_BRANCH`. If candidates are duplicate, ambiguous, invalid, or
   unsafe, report failure and stop without creating another PR.
4. Verify the rendered PR body, exact base, head branch, parent/child metadata,
   branch ancestry, draft state, conflict state, and required checks.
5. Send `worker_done --outcome succeeded` only with the complete
   `COMPLETION_PROOF` block.

The worker must not merge the PR or close the parent/child issues. The
coordinator owns child PR eligibility, squash merging, and issue completion.

### Phase 8 — Child PR description and verification

Every created child PR must have a standalone comprehensive body using the
contract below. A short ticket summary is not sufficient. The worker may not
report success until the PR has been verified with `gh pr view`, including the
rendered body, and the required metadata is present.

#### PR description contract

Every created PR must have a description that stands on its own. A reviewer
must be able to understand the rationale, scope, implementation approach, and
important low-level behavior without opening the original ticket. The ticket
and plan are inputs, not substitutes for documenting what the implementation
actually did.

Compose the description only after implementation, verification, and review so
it reflects the final code. Gather facts from:

- the ticket and implementation plan: requested problem, rationale, and
  acceptance criteria;
- the final diff (`git diff <base>...HEAD` or the equivalent commit diff): the
  actual files, control flow, data flow, APIs, schema, and user-visible
  behavior changed;
- implementer reports and verification output: notable decisions, tests, and
  commands that actually ran;
- reviewer findings: issues fixed, deferred, or confirmed as non-issues.

Use this structure, in this order. Write `None` or `Not applicable` rather
than silently omitting a section:

```markdown
Closes #<number>

## Why

<The problem, user need, or technical reason for this change. Explain why the
existing behavior was insufficient and what outcome this PR provides.>

## What changed

<Concise overview, followed by bullets of externally meaningful changes.>

- <specific implemented change>
- <specific implemented change>

## Implementation details

<Low-level details sufficient for a reviewer to follow the code without
opening the ticket: important files/modules, state transitions, data flow,
validation and error handling, persistence/API changes, and trade-offs.>

## User-visible behavior

<Describe the before/after behavior, affected screens or flows, and edge cases.
For non-UI work, describe the observable system or developer-facing behavior.>

## Verification

<List the exact checks that ran and their outcomes. Include lint, typecheck,
formatting, unit/integration/e2e tests, and manual verification when
applicable. Never claim a check ran if it did not.>

## Deviations from the ticket

<State `None` when implementation matches the ticket. Otherwise explain each
difference: what was requested, what was implemented instead, why, and the
impact on scope, behavior, or follow-up work.>

## Risks and follow-up

<List known risks, migration/deployment considerations, limitations, deferred
work, or monitoring needs. State `None` when there are no known items.>
```

Description quality and formatting rules:

- Use real Markdown line breaks in the body file. Never write literal escaped
  sequences such as `\n` or `\n\n`; do not construct the body through a
  JSON-escaped string, `echo`, or a shell command substitution that can turn
  line breaks into visible text.
- Keep exactly one blank line between paragraphs, headings, and lists; do not
  add repeated blank lines. Use descriptive headings, short paragraphs,
  bullets, nested bullets, numbered steps, and fenced code blocks for commands
  or snippets so the description is scannable.
- Prefer concrete file/module names, behavior, and reasons over generic claims
  such as “updated the feature.” Do not paste the entire diff.
- Separate requested behavior from implementation detail. Call out breaking
  changes, security/auth implications, schema changes, migrations, feature
  flags, and compatibility concerns explicitly when relevant.
- Keep `Closes #<number>` at the top so GitHub links and closes the ticket. In
  autonomous epic sub-ticket mode, also include `Part of #<parent-epic>`
  immediately below it.

Before creating the PR, inspect the actual body file. This must find nothing:

```bash
# Search for literal backslash-n sequences, not JSON escaping displayed by an API.
if grep -nF '\n' "$PR_BODY"; then
  echo "PR body contains literal escaped newlines; rewrite it with real Markdown newlines" >&2
  rm -f "$PR_BODY"
  exit 1
fi
```

After creation, verify the rendered body with `--jq .body` (not raw JSON,
where legitimate newlines are JSON-escaped):

```bash
gh pr view "$PR_URL" --json body --jq .body > "$PR_BODY_VERIFY"
```

If verification finds literal escaped newlines or a missing required section,
repair the body with `gh pr edit "$PR_URL" --body-file "$PR_BODY"` and verify
again. Do not leave a PR with a short placeholder description or claim success
until the final body has been checked.

When creating the authorized child PR, apply the PR description contract above.
Do not reuse a minimal ticket summary: reconstruct the body from the final
diff and actual verification results, and explicitly document any divergence
from the ticket.

Run the authorized child push and PR commands:

- **Create a PR:**

  Build a complete body following the PR description contract above. Write it
  to a temp file with a quoted heredoc (or another method that preserves real
  newlines), then pass it via `--body-file`. Do not use a short summary or
  shell-escaped `\n` sequences.

  ```bash
  PR_BODY=$(mktemp)
  cat > "$PR_BODY" <<'PRBODY'
  Closes #<number>

  ## Why
  <standalone rationale and problem statement>

  ## What changed
  - <specific implemented change>

  ## Implementation details
  - <files/modules, data flow, validation, and important decisions>

  ## User-visible behavior
  - <before/after behavior and edge cases>

  ## Verification
  - `<command>` — passed

  ## Deviations from the ticket
  None.

  ## Risks and follow-up
  None.
  PRBODY

  if grep -nF '\n' "$PR_BODY"; then
    echo "Refusing to create PR with literal escaped newlines" >&2
    rm -f "$PR_BODY"
    exit 1
  fi

  PR_URL=$(gh pr create \
    --title "[#<number>] <commit subject>" \
    --body-file "$PR_BODY")

  PR_BODY_VERIFY=$(mktemp)
  gh pr view "$PR_URL" --json body --jq .body > "$PR_BODY_VERIFY"
  if grep -nF '\n' "$PR_BODY_VERIFY"; then
    echo "PR body was not stored with real newlines; repair it before continuing" >&2
    gh pr edit "$PR_URL" --body-file "$PR_BODY"
    gh pr view "$PR_URL" --json body --jq .body > "$PR_BODY_VERIFY"
    grep -nF '\n' "$PR_BODY_VERIFY" && exit 1
  fi
  rm -f "$PR_BODY" "$PR_BODY_VERIFY"
  echo "$PR_URL"
  ```

  Confirm that all required sections are present and substantive before
  reporting the PR as created. Do not ask whether the ticket should be closed;
  autonomous workers never close issues. The coordinator owns issue completion.

Push the supplied child branch and create
exactly one PR targeting the supplied epic integration branch, linking
`SUBTICKET` and referencing `PARENT_EPIC`; do not close or merge either issue
or PR and do not delete the worktree. Verify the created PR with `gh pr view
<pr-number-or-url>`, confirm its base is the integration branch and its body
preserves both parent/child metadata, capture the canonical URL, and include
that URL plus `PARENT_EPIC` and `SUBTICKET` in the one `worker_done` report. If
push, PR creation, or verification fails, send `worker_done` with
`--outcome failed`; never retry by creating a second PR.

## Rules

- **MANDATORY delegation to the orca skills.** Loading and following
  `orca-cli` and `orchestration` is a hard requirement,
  not a suggestion. When this skill says to delegate, delegation is the only
  acceptable path. Never run `orca ...` commands from memory or from this
  file — resolve ORCA, load the guides, and use the exact flags they print.
- **Never improvise orchestration mechanics.** If a loaded orca guide and
  this skill disagree on the HOW, the loaded orca guide wins. This skill
  only owns the WHAT.
- **NEVER commit or push directly to `main`.** Always work in a feature
  branch. This skill runs inside an existing child worktree — do not create or
  delete worktrees. In autonomous epic mode, workers must use the exact
  coordinator-supplied child worktree and its own Orca UI group; never use the
  active/current worktree or a shared main-group terminal. The worker must
  verify placement before modifying files.
- **Autonomous mode is not direct mode.** The worker is authorized to commit,
  push, and create the one child PR without user confirmation. The worker must
  never ask for confirmation or claim success while leaving commit, push, PR
  creation, or PR verification for the coordinator.
- **A success report requires completion proof.** A `worker_done` success with
  no commit SHA, pushed branch, canonical PR URL/number, exact PR base, and
  verified parent/child metadata is invalid and must be reported as failed.
- **NEVER do delegated work inline.** Every step labeled `implementer`,
  `reviewer`, or `explore` in the plan MUST be dispatched via the orca
  skills' supervised worker loop. Steps may be **batched** into a single
  dispatch per the Complexity assessment and batching rules (Phase 4), but
  the dispatch itself is mandatory — batching never means "do it inline."
- **NEVER use a non-Orca substitute** for a required delegated step — no
  generic subagent API, OpenCode spawn, chat-only worker, ad-hoc PTY, or
  direct `terminal send`.
- **Give every dispatched worker a readable slug.** The `SLUG` input
  (passed to the orchestration skill's dispatch recipe) must be a short, descriptive
  kebab-case identifier that tells the user what the worker is doing — never
  `worker-task_<n>`, `step-<n>`, or `task-<n>` alone. See the SLUG guidance
  in Phase 4's Per-step dispatch section.
- **Classify each step simple/medium/hard and batch accordingly.** Hard
  steps dispatch alone; simple steps may batch together; a medium step may
  batch with up to two simple steps — all subject to execution-order
  feasibility. See Phase 4, "Complexity assessment and batching."
- **Dispatch independent steps in parallel** when they won't interfere
  (disjoint files, no shared mutable state, no ordering dependency). See
  Phase 4, "Parallel steps."
- **NEVER fall back inline** when Orca is unavailable, cannot be started, or
  orchestration is disabled. Stop and ask the user whether to abort or enable
  Orca. Do not ask permission to proceed inline.
- **NEVER declare a step done** without a valid `worker_done` result AND the
  orchestration skill's completion verification (dispatch status `completed`).
  Handle `worker_done --outcome failed` by re-dispatching an `implementer`
  task — never fix it inline.
- **Reviewer and explorer workers must not modify files.** Only
  `implementer` workers may change code.
- In autonomous epic mode, push the supplied child branch and create or
  reconcile exactly one child PR as authorized above. User confirmation is not
  required and must not be requested. Do not merge the PR or close issues.
- Every PR description must follow the standalone, comprehensive PR
  description contract in Phase 8; a few-line summary is not sufficient.
- Do NOT skip lint/typecheck — both must pass before committing
  (skip typecheck only if the language has no separate typecheck step).
- Do NOT commit if any verification step fails.
- Always reference the ticket number in the commit message.
- If the plan lacks a Decision completeness declaration or has unresolved
  questions, STOP and ask the user before implementing.
- If implementation diverges significantly from the plan, STOP and confirm
  with the user before dispatching dependent work.
- Never assume a specific platform, language, or framework. Always derive
  from Phase 0 discovery.
- Before mutating shared infrastructure (databases, generated types, env),
  check project guidance for coordination rules; if none, ask the user how
  to coordinate. Never let two workers mutate shared infrastructure
  concurrently.
- **Never unbounded-wait on a terminal sub-Dispatch.** Before every
  `check --wait` on a sub-Dispatch, inspect its state; wait only when it is
  `ready` or `dispatched` or a reply is pending. If it is already terminal,
  harvest the outcome from `dispatch-show` instead of waiting — a sub-worker's
  `worker_done` is a one-shot and a terminal Dispatch will never emit another
  lifecycle message. See "Sub-Dispatch wait and result-harvest discipline."
- Do not expose secrets from any `.env*` file. Read only `.env.example`.
