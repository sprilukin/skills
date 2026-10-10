---
name: implement-epic
description: "Use when implementing one validated GitHub Epic through autonomous Orca-supervised delegation of its native sub-issues; resumable and self-healing."
---

# Implement Epic

This skill owns the complete autonomous lifecycle for one native GitHub Epic and
its native sub-issues. It dispatches every implementation, exploration, review,
and recovery action through the live global `orca-cli` and `orchestration`
skills. Those skills own version-sensitive commands, flags, worker startup,
waiting, and completion verification; do not copy command sequences here.

## Authority and invariants

- Select exactly one open issue whose title begins exactly `Epic:`. GitHub's
  native `subIssues` relationship is authoritative; body `#N` placeholders are
  never identity or discovery mechanisms.
- Validate the epic, every native child body, exact stable-key/title mapping,
  dependency graph, acyclic topological order, decision completeness, and all
  required finalized metadata before dispatching anything. Reject unresolved
  markers, draft placeholders, missing/duplicate nodes, cycles, and order
  violations.
- The project default branch is `main`. The coordinator owns branches,
  worktrees, PR eligibility, merges, issue completion, reconciliation, healing,
  and the final integration PR. Workers own implementation, verification,
  review, one child commit/push/PR, and worker completion proof.
- No committed coordinator state file is permitted. State is reconstructed from
  GitHub issue/PR/branch data and local Orca worktrees on every invocation.
- The selected epic body must contain exactly one finalized coordinator
  activation gate:

  ```text
  AUTONOMOUS_EPIC_SUBTICKET
  PARENT_EPIC=<selected native epic number or URL>
  SUBTICKET=<native child number or URL for the first item in implementation order>
  ```

  This gate authorizes the epic coordinator before dispatch. It is distinct
  from the child-specific gate injected into each dispatched task spec. If the
  epic gate is absent, malformed, duplicated, or does not match the selected
  epic and first ordered native child, stop without dispatching work.

## Phase 0 — establish context and validate Orca

Read root `AGENTS.md`, `plan-feature`, this skill, and `implement-auto`; load
live `orca-cli` and `orchestration` skills. Confirm repository/default branch
with `gh repo view`, the selected worker agent's executable readiness (per the
`implement-auto` Worker provider and readiness preflight), and a suitable
coordinator context. Never read `.env*` except `.env.example`.

The selected worker agent is an execution/runtime choice, not a product
provider choice. The repository default is **`pi`**; use it unless the user
explicitly selects another supported Orca TUI agent (`opencode`, `claude`,
`codex`, `omp`, …). There are two readiness regimes: **local TUI agents**
(`pi`, `opencode`, `omp`, …) are local executables validated only with
`command -v <agent>` and `<agent> --version`; **managed-account agents**
(`claude`, `codex` only) additionally require a signed-in Orca-managed
account. Missing Orca-managed Claude/Codex accounts is never a blocker for a
local TUI agent — `orca account` manages only Claude and Codex accounts and is
irrelevant to `pi`/`opencode`. Do not run `orca account list` for a local TUI
agent session.

Before creating orchestration state, inspect existing Runs and Tasks. Reuse or
bind exactly one safe Run for this epic across all resumed invocations. If no
matching Run exists, create one. If multiple matching Runs exist or ownership
is ambiguous, stop for reconciliation; do not create a second Run. Create one
synthetic parent Task only when no matching parent Task exists in the selected
Run, and verify every create/bind response is successful with a real ID before
using it. Never continue with a null, guessed, or unverified Run or Task ID.

Stop only if the selected agent's executable is absent, cannot start via
`worker-start --agent <agent>`, or — for `claude`/`codex` only — no managed
account is signed in. Never work inline or invent mechanics.

## Phase 1 — discover and validate the native epic

When given a number/URL, fetch that issue and require open state and exact
`Epic:` title. With a description, search open issues and require the same
criteria; with no description list eligible epics and require selection if
ambiguous. Fetch the selected issue with `number,title,body,url,subIssues,
subIssuesSummary`, then fetch every native child individually.

Before any Task or worker, produce a validation report (in memory or a
non-committed run artifact) containing native children, exact titles and URLs,
stable-key mapping, graph edges, topological order, and body completeness.
Require the epic template sections (`Epic structure`, graph, order,
`Sub-ticket definitions`, decision completeness), exactly one finalized
coordinator activation gate matching the selected epic and the first native
child in implementation order, no draft or unresolved markers, and each child
to contain Context, decisions, ordered plan, verification, rollback, Decision
completeness, exact-title H1, and matching `Epic sub-ticket key: S<N>`. Native
GitHub issue numbers and parent relationships provide issue/epic identity; no
status or duplicate ticket metadata is required in the body.
Validate every graph node exactly once, every edge, no self-edge/duplicate/cycle,
and an order containing each key exactly once and respecting dependencies.
Stop with actionable errors and no side effects on any failure.

## Phase 2 — integration branch and reconciliation

Create or resume the integration branch `epic/<epic-number>-<slug>` from
`main`. If it exists, verify its remote and local ancestry, that its base is
`main` (or a documented main descendant), and that it is not a child branch;
repair/stop on ambiguous ancestry rather than guessing. Do not create a second
integration branch. The final PR is the sole PR from this branch to `main`.

**Remote integration-base publication is a hard pre-dispatch gate.** Before
creating child branches/worktrees or dispatching any child worker, ensure the
exact integration branch exists on the expected GitHub remote. If it is only
local, publish that already-validated branch using the live Orca/git mechanics,
then verify the remote ref and tip against the validated local branch with
`git ls-remote` and GitHub API inspection. Confirm that the remote branch
contains the validated `main` ancestry and that its exact name is the only
allowed child-PR base. A local-only, missing, ambiguous, or mismatched remote
base is terminal repair-required; do not dispatch workers that cannot create
or verify their child PR.

Re-run this publication and remote-tip gate on every restart before resuming
or creating a child Dispatch. Never ask a worker to repair or publish the
coordinator-owned integration base.

On every start/restart, reconcile GitHub and local Orca state: inspect native
child issues, all open/merged/closed PRs, PR bodies/metadata, branch ancestry,
and available Orca worktrees. Match by native child and this parent epic (title
similarity alone is insufficient). Reuse an existing matching child branch,
PR, and worktree when safe; continue an existing worktree rather than creating
another. A merged matching PR is completed. For each child, reconciliation
requires exactly one matching merged child PR with the child and parent
metadata, the integration-branch base, and the expected child-branch
ancestry; zero, multiple, or otherwise non-matching merged PRs are terminal
repair-required states. An ambiguous, conflicting, or unsafe open match is
terminal and must not produce a duplicate worker, branch, or PR. Record
outcomes durably in the run report, not a committed file.

The integration branch's final-PR reconciliation is a separate exactness gate.
On every start/restart, enumerate every existing open, merged, or closed PR
whose head is the epic integration branch (and every PR claiming to be the
epic's final PR), then validate its base, branch ancestry, epic metadata, draft
state, merge/conflict state, and required checks. Recognize exactly one
canonical valid final PR only when there is one and only one such PR, it targets
`main`, is based on the integration branch's allowed ancestry, is correctly
linked to the epic and all required child PRs, is not a draft, and has no
conflicting, failing, missing, or unknown required status. A missing final PR
is the sole state in which creation may later be considered. Any invalid,
ambiguous, duplicate, conflicting, incorrectly based, incorrectly linked,
draft, or otherwise noncanonical final-PR state—including a valid-looking PR
alongside any other candidate—is terminal/repair-required: preserve the
existing PRs, stop, and never create another PR. This rule applies before and
after quiescence and across resumed runs; it preserves the exactly-one-final-PR
invariant.

For each child, create/resume the branch
`epic/<epic-number>/<child-number>-<slug>` from the integration branch and a
matching Orca-managed child worktree based on that branch. Validate branch
ancestry against the integration branch before dispatch and preserve existing
worktrees/branches on completion or failure. Use only live Orca worktree
mechanics; never invoke `git worktree` directly.

**Worktree/group isolation is mandatory.** Every child worktree must be an
independent Orca worktree context with its own UI group; never place a child
worker in the coordinator's `main` worktree, the active/current worktree, or a
terminal merely opened in the main group. Before dispatch, verify the exact
worktree selector, absolute path, branch, and Orca worktree/group identity.
Pass that exact existing-worktree selector to the supervised worker loop. Do
not use `current`, `active`, an omitted `--worktree`, or a bare terminal handle
that resolves to the main group. If Orca cannot prove that the worker terminal
belongs to the supplied child worktree/group, stop rather than dispatching.

## Phase 3 — topology and child dispatch

Create one Orca child Task per native child, with validated DAG dependencies.
If an OpenSpec change is associated with the epic or sub-tickets, map the native sub-issues
against the OpenSpec task graph in `openspec/changes/<change-name>/tasks.md` and include
the relevant delta specifications in the worker context.
Dispatch ready nodes in dependency waves, independent nodes in parallel, while
serializing the shared-state lane (schema/migration work, generated-file
regeneration, local service instances, or uncertain shared mutable state).
Keep unrelated nodes moving when a node fails. Before mutating shared
infrastructure (databases, generated types, env), check project
guidance for coordination rules; if none, ask the user how to coordinate. A
failed/stopped/unresponsive node blocks all
its descendants but not unrelated nodes.

The child dispatch is anchored to the child's exact Orca worktree/group, not to
the coordinator's group. The injected spec must include the absolute
worktree path and branch, and the coordinator must verify the worker-start
receipt's worktree effect plus the terminal's worktree/group before accepting
input. A worker that starts in `main` or another child's group is a placement
failure: stop/reconcile that dispatch and do not let it modify files.

Each child spec includes the complete fetched issue body verbatim, issue and
parent URLs/numbers, slug, direct/transitive dependencies and predecessor
results, expected files, verification obligations, `TIMEOUT_MS=900000`, and
these concrete branch/worktree contract fields:

```text
REPO=<repository name with owner>
WORKTREE_SELECTOR=<exact existing Orca selector>
WORKTREE_PATH=<absolute child worktree path>
CHILD_BRANCH=<exact child branch>
INTEGRATION_BRANCH=<exact published integration branch>
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native child number or URL>
```

The spec must also include the one-PR contract and this exact gate:

```
AUTONOMOUS_EPIC_SUBTICKET
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native sub-ticket number or URL>
```

It must explicitly invoke `implement-auto` as the only executor, delegate
implementer/explore/reviewer work through live Orca guides, preserve parent and
child metadata, target the child PR only at the published integration branch,
verify with `gh pr view`, and report its canonical URL plus completion proof.
Require all three success proofs independently:

1. exact succeeded `worker_done` whose body contains the commit, pushed branch,
   canonical PR URL/number, exact PR base, parent/child metadata, and rendered
   PR verification;
2. Dispatch status `completed` for the same Task/Dispatch; and
3. fresh GitHub reconciliation finds exactly one canonical matching child PR.

A worker completion without PR proof is protocol-invalid, not successful. A
worker failure or protocol-invalid completion must never be followed up by
sending mail to that terminal Dispatch. If the Dispatch is terminal, create a
new coordinator-owned recovery implementer Task/Dispatch in the preserved
worktree and branch, subject to the healing bound; use `--retry-of` only when
the live orchestration guide explicitly says the failed/stopped Dispatch is
retryable. A timeout is a checkpoint, not permission to retry; inspect
liveness and Dispatch state before waiting or recovering, and never create a
second PR.

## Phase 4 — child PR eligibility, refresh, repair, and coordinator merge

A child PR is eligible only if it is one canonical matching PR whose body links
both native child and parent epic, targets exactly the integration branch,
has the expected child branch ancestry, is not draft, has no conflicts, has
passing required checks, and is not missing or unknown in any required status.
During child reconciliation, require exactly one matching merged child PR;
zero, multiple, or conflicting merged candidates are terminal/repair-required.
Reject failing, missing, unknown, draft, conflicting, incorrectly based, or
incorrectly linked PRs. Preserve the existing PR while repairing it.

The integration branch may contain validated squash merges of eligible child
PRs and coordinator-owned integration-branch merge commits needed to maintain
that branch; such coordinator-owned merge commits are explicitly permitted,
provided the child work remains based on the epic's validated ancestry. Every
commit must descend from `main` and remain in that validated child ancestry. A
branch with unexplained, unrelated, or incorrectly based commits, or ancestry
that cannot be established unambiguously, is terminal/repair-required and must
not be used to create or retarget a PR.

The coordinator must treat child work as a state machine, not as a single
worker result:

```text
pending -> dispatched -> worker_reported -> child_pr_reconciled
         -> pr_verified -> eligible -> merged -> issue_reconciled
```

A worker-reported success without a canonical child PR becomes
`protocol_invalid_recovery_pending`. A worker failure, interruption, missing
remote base, conflict, or failed required check becomes `recovery_pending`
after GitHub and Orca reconciliation. An ambiguous branch/PR/worktree,
unsafe ancestry, or exhausted healing budget becomes terminal repair-required
and blocks descendants.

Before merging a dependent, refresh its stale branch from the current
integration branch. If refresh exposes conflicts or required checks fail,
dispatch a fresh implementer recovery worker in the child's existing worktree
and branch. Recovery must preserve the existing PR and metadata; it must not
create a new PR. Initial implementation does not count as healing. The bound
is at most **two healing attempts** per child across all resumed runs, and only
a **new implementer repair dispatch** for a failed, interrupted, conflicted, or
incomplete child counts as one attempt; count those attempts from reconciled
PR/worker history, stop the child after the bound, and block its descendants if
unresolved. Recovery workers still require Orca `worker_done` and Dispatch
completion proofs.

Only this skill may, in autonomous epic execution, validate and squash-merge an
eligible child PR into the integration branch. After each validated squash
merge, coordinator-owned completion comments/closure may close the matching
child issue (never the epic automatically), and the merge/closure must be
reconciled before advancing. `implement-auto` workers are never authorized
to merge PRs or close issues. Never delete worktrees. Do not auto-merge the
final epic PR.

### Dispatch terminal-state and recovery rules

Before waiting, sending follow-up guidance, or scheduling recovery, inspect the
current Task and Dispatch state. Use this matrix:

| Dispatch state                                       | Coordinator action                                                                                        |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `ready` or `dispatched`                              | Wait, inspect liveness, or answer a worker question/escalation.                                           |
| `completed` with valid worker proof and canonical PR | Reconcile GitHub and continue; do not retry.                                                              |
| `completed` without required PR proof                | Record protocol-invalid completion and create a fresh recovery Dispatch.                                  |
| `failed` or `stopped`                                | Use the live guide's retry path only when explicitly allowed; otherwise create a fresh recovery Dispatch. |
| `outcome_unknown`                                    | Follow the live guide's worker-show/stop/abandon recovery guidance; do not guess.                         |
| terminal Dispatch                                    | Never send follow-up mail expecting it to resume and never wait for new lifecycle messages from it.       |
| idle terminal with terminal Dispatch                 | Treat the terminal as an idle surface, not as an active worker.                                           |

A fresh recovery Dispatch must preserve the exact existing child worktree and
branch, include the full branch/base contract, and reconcile GitHub before
creating or repairing a PR. Count only fresh implementer recovery Dispatches
against the two-attempt healing bound.

## Phase 5 — quiescence and final integration PR

Continue scheduling, refreshing, repairing, merging, and reconciling until the
validated graph reaches quiescence: every node is merged/completed, terminal
failed, or terminal blocked, with no runnable or in-flight work. Failed or
blocked nodes block descendants; unrelated nodes continue. Do not create a
final PR while any node is failed, blocked, ambiguous, unsafe, or incomplete.

Before every `check --wait`, verify that at least one expected Dispatch is
actually `ready` or `dispatched`, or that an explicitly pending worker
question/escalation requires a response. A visible or idle terminal is not
enough. If no active Dispatch remains, do not enter an unbounded wait:
reconcile Run/Task/Dispatch/GitHub state, schedule a valid recovery or ready
node, mark descendants blocked, or stop with a precise terminal report.

After every worker message, independently validate the Task/Dispatch IDs,
worker outcome, Dispatch status, commit on the expected child branch, pushed
branch, exactly one canonical PR, exact integration-branch base, parent/child
metadata, rendered PR body, and required statuses. Orca lifecycle completion
alone is never semantic child completion.

When and only when all children are validated and squash-merged, and the final-
PR reconciliation gate has found no existing PR from the integration branch:

1. If an OpenSpec change was associated with this epic (`openspec/changes/<change-name>/`), verify all tasks in `tasks.md` are marked complete and archive the change via `openspec archive "<change-name>" --yes` on the integration branch, staging and committing any updated canonical specs.
2. Create exactly one comprehensive PR from `epic/<epic-number>-<slug>` to `main`.
   It must reference the parent epic and every merged child PR, explain rationale,
   implementation details, verification, deviations, and risks, and be verified
   with `gh pr view` (including rendered body). Do not auto-merge it. If
   reconciliation recognizes exactly one canonical valid final PR, reuse it and
   never create another. If reconciliation finds any invalid, ambiguous, duplicate,
   conflicting, incorrectly based, incorrectly linked, draft, or otherwise
   noncanonical final-PR state, stop as terminal/repair-required and never create
   or retarget another PR.

## Reports, testing, and restart safety

Produce a durable final report with epic/Run/Task IDs, validation graph/order,
wave and shared-state lane membership, every child once, branch/worktree,
predecessors, PR URL, merge/closure result, healing count, and precise failure
or block reason. Documentation-only changes still require checking Markdown
format/structure and link or consistency obligations applicable to the skill;
run the repository's documented lint/format checks when available and report
commands not applicable rather than claiming they ran.

A rerun refetches and revalidates the epic and children, rechecks branch
ancestry, reconciles PRs/worktrees, resumes safe work, and avoids duplicate
workers, branches, PRs, merges, or closures. If the epic graph/order/body
changed, stop for fresh validation rather than assuming prior state.
