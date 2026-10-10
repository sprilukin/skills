# Autonomous sub-ticket worker mode

Implement exactly one validated native sub-ticket delegated by the epic
coordinator (`epic.md`). This mode is autonomous only; it must never be used
for ordinary direct ticket implementation (that is the direct mode of
`SKILL.md`).

This file is part of the `implement-ticket` skill. The `worker-delegation`
contract applies throughout: it owns dispatch mechanics for this worker's
own sub-workers, the wait/harvest discipline, recovery rules, the
completion-proof block, the PR description contract, and testing
obligations. This mode owns the WHAT: which steps, which roles, which
gates, and the autonomous authorization below. When this file and
`worker-delegation` disagree on mechanics, `worker-delegation` wins.

In `worker-delegation` terms, this agent plays **both roles**: it is the
autonomous _worker_ of the epic coordinator, and the _supervisor_ of its own
finer-grained sub-workers (implementer/explore/reviewer).

## Autonomous gate (hard failure without it)

The invoking spec MUST contain exactly one literal `AUTONOMOUS_EPIC_SUBTICKET`
marker and exactly one `PARENT_EPIC=<GitHub epic issue number or URL>` plus
exactly one `SUBTICKET=<GitHub sub-ticket issue number or URL>`. Missing,
duplicated, ambiguous, or malformed values are a hard failure; do not infer
them from context. Report failure through the worker lifecycle.

## Placement contract (mandatory when a placement is supplied)

The coordinator supplies the child branch and worktree placement based on
the integration branch. Preserve it across resume; never create a second
branch or worktree. The supplied placement is a mandatory boundary: work
only in the exact coordinator-supplied worktree. Never fall back to the
coordinator's own workspace, the repository main checkout, or a workspace
belonging to another child.

Before doing any work, verify the current absolute path, Git branch, and
workspace identity against the injected contract (per the
`worker-delegation` placement-verification rules and the harness file's
inspection mechanism). If they do not match the contract, stop and report a
placement failure through the worker lifecycle; do not edit files and do not
create another worktree.

## Autonomous authorization and boundaries

The worker owns the complete autonomous child lifecycle without asking the
user for permission. The issue body's implementation plan is an input to
this lifecycle, not a stopping point. A successful worker must implement the
plan, verify it, perform the required delegated review, commit, push, create
or reconcile exactly one child PR, verify that PR, and then report
completion.

The worker may commit, push, and create exactly one child PR without user
confirmation. The PR MUST target only the supplied integration branch,
include `Closes #<child>` and `Part of #<parent>`, and follow the
`worker-delegation` PR description contract (verified with `gh pr view`
using the rendered body). The worker must report a canonical URL and both
identifiers in exactly one final completion report with the completion-proof
block.

Before modifying files, the worker must have and verify these concrete
contract values from the injected task specification:

```text
REPO=<repository name with owner>
WORKTREE_PATH=<absolute worktree path>
CHILD_BRANCH=<exact child branch>
INTEGRATION_BRANCH=<exact integration branch>
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native child number or URL>
```

Before creating the PR, verify that `INTEGRATION_BRANCH` exists on the
expected GitHub remote and is the exact allowed PR base. A local-only or
ambiguous base branch is a blocking failure; report it and stop rather than
guessing, creating a new branch, or creating a PR against another base.

## One-PR reconciliation invariant

Reconcile every existing PR claiming this child, parent, or supplied branch
**before** creating a new one: exactly one canonical valid PR may exist. If
exactly one exists, verify and reuse or repair it — never replace it.
Invalid, duplicate, ambiguous, draft, conflicting, incorrectly based,
incorrectly linked, or failed-check candidates are terminal failures; never
create another PR.

This mode never merges a PR, closes an issue, archives a workspace, deletes
a worktree, repairs a PR outside a dispatched implementer task, or performs
delegated work inline. Recovery is a new coordinator-owned implementer
dispatch in the preserved worktree and branch (see Recovery below).

## Autonomous child lifecycle (mandatory order)

Follow this order unless the coordinator's recovery spec explicitly
identifies a later stage to resume:

1. Verify the placement and all injected repository/branch/worktree values.
2. Reconcile existing child/parent PR candidates before making a new one.
3. Implement the complete child plan and any required tests or generated
   output — every implementation, exploration, and review step dispatched
   per the delegation contract below (batching per `worker-delegation`).
4. Run the plan's verification commands; fix failures through fresh
   implementer dispatches.
5. Run the required read-only reviewer and address blocking findings through
   a fresh implementer dispatch.
6. Commit the final verified changes and push `CHILD_BRANCH`.
7. Reconcile or create exactly one canonical PR targeting
   `INTEGRATION_BRANCH`.
8. Verify the rendered PR body, metadata, branch, base, and required status.
9. Send exactly one completion report with the completion proof (below),
   then end the turn and idle.

## Delegation contract (mandatory, never optional)

Delegation is a hard requirement: if any step in this mode, the ticket plan,
or a delegated task spec is assigned the role `implementer`, `explore`, or
`reviewer`, that step **MUST** be dispatched to a real sub-worker through
`worker-delegation` before it executes. Never perform it inline in this
session. The dispatch (not the inline execution) is what's mandatory —
batching several steps into one dispatch is allowed per the
`worker-delegation` batching rules.

- **Never perform delegated work inline.** This agent may discover context,
  parse the plan, run read-only/check-mode verification commands, compare
  diffs, and summarize results. It must not implement, explore, fix, or
  review code that belongs to a delegated step.
- **Every fix is dispatched.** A failed verification or blocking review
  finding requires a new `implementer` dispatch — never an inline fix.
- **The code review is dispatched.** The pre-commit review must be a
  `reviewer` dispatch with `MAY modify files: no`; it is not an inline
  review and is not optional.
- **Unassigned code-changing steps default to `implementer`.**
- **Generated-code regeneration is a dispatched task.** Schema, migration,
  or generated-artifact changes (types, ORM clients, SDKs) must include the
  regen command (resolved via the profile's `layout.generated_files`
  `regenerate_command`) in the same implementer task's acceptance criteria,
  or get their own dispatch — never an unassigned change in this session.
- **No substitute delegation.** No generic subagent API substitute, chat-only
  worker, ad-hoc PTY, or raw terminal input as a replacement for the
  supervised dispatch contract.
- **No inline fallback.** If the harness is unavailable, cannot start, or no
  provider is available, stop and tell the user per `worker-delegation`.
  Never ask permission to proceed inline.
- **No unvalidated provider fallback.** Run the `worker-delegation` preflight
  before the first dispatch. If the provider is missing, unauthenticated, or
  cannot start, stop; do not substitute another provider or retry blindly.
  If a model fails auth at runtime, follow the `worker-delegation` preflight
  model-failure procedure.
- **Model-default gate.** When the harness declares `model-pinning`, the
  preflight's model-default gate applies to sub-worker dispatches too: this
  coordinator's own model must match the configured sub-agent default before
  the first sub-worker dispatch; on mismatch, stop and report per
  `worker-delegation`.
- **Reviewer and explorer sub-workers must not modify files** (`MAY modify
  files: no`). Only `implementer` sub-workers may change code.

## Sub-worker supervision

Apply the `worker-delegation` wait/harvest discipline and terminal-state
matrix to every sub-worker dispatch: inspect before waiting, rely on
completion notifications when the harness declares `async-notification`,
harvest reports from the harness's log/state mechanism, cross-validate
worker identity + report + status, never re-wait a terminal worker, never
unbounded-wait when nothing is running. Mid-plan implementer steps report
success as: files changed, verification commands run and their outcomes, and
any deviations (the child-PR completion proof applies only to this mode's
own final report).

On a failed or protocol-invalid sub-worker: record the failure and create a
fresh recovery `implementer` dispatch in the preserved worktree/branch. Do
not declare the step done, fix it inline, or silently retry it.

Questions and escalations: a sub-worker needing a decision ends with a
QUESTION section and idles; read it from the harvested output, answer
through the `worker-delegation` question/reply channel (or escalate to the
user first), and resume waiting. Do not run the step yourself while the
sub-worker is active.

Include the `worker-delegation` testing obligations in every implementer
sub-worker spec, and the per-stack skill declared by the profile's `stack`
section (e.g. the installed `supabase` skill) in constraints when the step
touches DB/auth/RLS and the skill is installed.

## Completion proof

A success completion report is forbidden until all of these proofs exist and
are included verbatim in the single final report (the `worker-delegation`
§8 autonomous-child form):

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
push, PR creation, PR verification, or any proof is missing, report failure
with the exact blocking reason. Do not leave the worker at a supposed
success state for the coordinator to finish manually.

If creation or verification fails, report failure and end the worker turn.
Do not retry inside the same agent turn and do not create a second PR.
Recovery is a new coordinator-owned implementer dispatch in the preserved
worktree and branch; an existing canonical PR must be repaired or reused
rather than replaced.

## Rules

- **Autonomous mode is not direct mode.** The worker is authorized to
  commit, push, and create the one child PR without user confirmation. It
  must never ask for confirmation or claim success while leaving commit,
  push, PR creation, or PR verification for the coordinator.
- **A success report requires the completion proof.** A success report
  without commit SHA, pushed branch, canonical PR URL/number, exact PR base,
  and verified parent/child metadata is invalid and must be reported as
  failed.
- **Never merge the PR, never close issues, never archive or delete the
  worktree.** The coordinator owns merging, issue completion, and worktree
  lifecycle.
- **Never commit or push directly to `main`.** Always work on the supplied
  `CHILD_BRANCH` in the supplied worktree, verifying placement before
  modifying files.
- **Delegation is mandatory** per the contract above; never do delegated
  work inline, never use a substitute.
- **Verify, never assume.** Run lint/typecheck/format/tests from the plan's
  verification section (repository defaults as fallback) before committing;
  a failure is fixed via a fresh implementer dispatch, and nothing is
  committed with failing verification.
- **Reference the ticket number in the commit message.**
- **Significant plan divergence — stop and escalate** to the coordinator
  (QUESTION in the final message) before dispatching dependent work.
- **Shared infrastructure.** Before mutating shared infrastructure
  (databases, generated types, env), check project guidance for coordination
  rules; if none, ask the user (escalate to the coordinator) how to
  coordinate. Never let two workers mutate shared infrastructure
  concurrently.
- **Never assume platform, language, or framework** — derive from the ticket
  and project discovery.
- **Do not expose secrets from any `.env*` file.** Read only `.env.example`.
- Follow the `worker-delegation` contract when this document and it differ.
