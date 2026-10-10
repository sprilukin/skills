---
name: implement-epic-paseo
description: "Use when implementing one validated GitHub Epic through autonomous Paseo-supervised delegation of its native sub-issues; resumable and self-healing."
---

# Implement Epic (Paseo edition)

This skill owns the complete autonomous lifecycle for one native GitHub Epic
and its native sub-issues. It is the **coordinator**: it validates the epic,
creates/resumes the integration branch and child worktree workspaces, wades
through the dependency DAG, merges eligible child PRs, and finally opens the
epic integration PR. Child implementation itself is delegated to the
`implement-auto-paseo` skill, which must be dispatched through the Paseo MCP
tools (`create_agent`) or, when those are unavailable, the live installed
`paseo` skill. That skill (with `paseo-delegation`) owns
version-sensitive commands, flags, worker startup, waiting, and completion
verification; do not copy their command sequences here.

## Authority and invariants

**Terminal invariants — each stated once here; every phase below refers back
to this section instead of restating:**

1. **One epic.** Select exactly one open issue whose title begins exactly
   `Epic:`. GitHub's native `subIssues` relationship is authoritative; body
   `#N` placeholders are never identity or discovery mechanisms.
2. **One integration branch.** `epic/<epic-number>-<slug>` based on `main`.
   Never create a second one; its sole PR is the final PR to `main`.
3. **Exactly one canonical PR per purpose.** For each child: exactly one
   matching child PR targeting the integration branch. For the epic: exactly
   one final PR from the integration branch to `main`. Any duplicate,
   ambiguous, invalid, conflicting, incorrectly based/linked, draft, or
   failing-check PR state is terminal/repair-required: preserve the existing
   PR, stop, never create or retarget another.
4. **Merged child reconciliation.** A child counts as completed only when
   exactly one matching merged child PR exists with the child + parent
   metadata, the integration-branch base, and the expected child-branch
   ancestry. Zero, multiple, or non-matching merged PRs are terminal.
5. **Placement.** Every child worker runs in an independent Paseo-managed
   worktree workspace based on the child branch — never in the coordinator's
   workspace, the main checkout, or another child's workspace. Use only
   Paseo workspace mechanics; never `git worktree` directly. Never delete or
   archive a child worktree workspace.
6. **No committed coordinator state.** State is reconstructed from GitHub
   issue/PR/branch data and local Paseo worktree workspaces on every
   invocation; record outcomes durably only in run reports, never in a
   committed file.
7. **No committed coordinator state file is permitted.** (Restated from (6)
   for emphasis: never write coordinator state into the repo.)
8. **Healing bound.** At most **two healing attempts per child across all
   resumed runs**; only a fresh implementer recovery dispatch counts. Exhaustion
   is terminal for that child and blocks descendants.
9. **Merge authority.** Only this coordinator may validate and squash-merge an
   eligible child PR, comment/close the child issue, or archive the OpenSpec
   change. `implement-auto-paseo` workers never merge PRs or close issues.
   The coordinator never auto-merges the final epic PR.
10. **Shared-state lane.** Schema/migration work, generated-file
    regeneration, and local service instances are serialized; keep a
    migration and its generated-file regeneration in one sub-ticket when
    possible. Before mutating shared infrastructure
    (databases, generated types, env), check project guidance for
    coordination rules; if none, ask the user how to coordinate.
11. **Model-default gate.** Before the first worker dispatch and on every
    restart, the coordinator's own model must match the configured sub-agent
    default (the `"isDefault": true` entry) for the selected provider in
    `${PASEO_HOME:-$HOME/.paseo}/config.json`, and must equal a
    `REQUIRED_MODEL` pin when the invocation prompt carries one. Any mismatch
    stops the run before creating branches, worktree workspaces, or workers.

## Phase 0 — Establish context and validate Paseo

Read root `AGENTS.md`, this skill, `implement-auto-paseo`, and the
`paseo-delegation` skill (it owns dispatch mechanics, worker preflight, the
wait/harvest discipline, and completion proof). Load the installed `paseo`
skill (fallback: `paseo --help` and https://paseo.sh/docs/cli). Do **not**
pre-load `plan-feature-paseo` — the validated epic body is the plan. Confirm
repository/default branch with `gh repo view`. Never read `.env*` except
`.env.example`.

Run the `paseo-delegation` provider preflight (repository default `pi`;
execution/runtime choice, not a product provider choice), including its
model-default gate (invariant 11). Stop only if the provider is absent,
`unavailable`, fails the diagnostic, fails the model-default gate, or the
first worker cannot start. Never work inline or invent mechanics.

Before creating any worker agents, inspect existing Paseo state: list agents
across all workspaces (`list_agents` with `includeArchived: true`; CLI
fallback `paseo ls -g -a --json`) filtered by this project's
directory and inspect any plausible prior coordinator/worker agents. On
resume, reuse or bind exactly one safe prior coordination context for this
epic — matching by epic number, branch names, and workspace paths, never by
title similarity alone. If multiple plausible prior contexts exist and
ownership is ambiguous, stop for reconciliation; do not create duplicate
workers or branches.

## Phase 1 — Discover and validate the native epic

When given a number/URL, fetch that issue and require open state and exact
`Epic:` title. With a description, search open issues and require the same
criteria; with no description, list eligible epics and require selection if
ambiguous. Fetch the selected issue with
`number,title,body,url,subIssues,subIssuesSummary`, then fetch every native
child individually.

Before any worker dispatch, produce a validation report (in memory or a
non-committed run artifact) containing native children, exact titles and
URLs, stable-key mapping, graph edges, topological order, and body
completeness. Require from the epic body:

- template sections: `Epic structure`, dependency graph, implementation
  order, `Sub-ticket definitions`, decision completeness;
- exactly one finalized coordinator activation gate
  (`AUTONOMOUS_EPIC_SUBTICKET` / `PARENT_EPIC=` / `SUBTICKET=`) matching the
  selected epic and the first native child in implementation order — absent,
  malformed, duplicated, or mismatched means stop without dispatching;
- no draft or unresolved markers (`TBD`, `TODO`, `user to decide`, …);
- each child body containing: Context, Implementation decisions, ordered
  Implementation plan, Verification plan, Rollback plan, Decision
  completeness, exact-title H1, and a matching `Epic sub-ticket key: S<N>` line.

Native GitHub issue numbers and parent relationships provide issue/epic
identity; no status or duplicate ticket metadata is required in bodies.
Validate every graph node exactly once, every edge, no self-edge/duplicate/
cycle, and an order containing each key exactly once and respecting
dependencies. Stop with actionable errors and no side effects on any failure.

## Phase 2 — Integration branch, publication gate, and reconciliation

Create or resume the integration branch `epic/<epic-number>-<slug>` from
`main` (invariant 2). If it exists, verify remote/local ancestry, that its
base is `main` (or a documented main descendant), and that it is not a child
branch; repair/stop on ambiguous ancestry rather than guessing.

**Remote integration-base publication is a hard pre-dispatch gate.** Before
creating child branches/worktree workspaces or dispatching any child worker,
ensure the exact integration branch exists on the expected GitHub remote. If
it is only local, publish it with normal git mechanics, then verify the
remote ref and tip against the validated local branch with `git ls-remote`
and GitHub API inspection. Confirm the remote branch contains the validated
`main` ancestry and that its exact name is the only allowed child-PR base. A
local-only, missing, ambiguous, or mismatched remote base is terminal
repair-required; do not dispatch workers that cannot create or verify their
child PR. Re-run this gate on every restart. Never ask a worker to repair or
publish the coordinator-owned integration base.

On every start/restart, reconcile GitHub and local Paseo state: inspect
native child issues, all open/merged/closed PRs, PR bodies/metadata, branch
ancestry, and available Paseo worktree workspaces (`list_workspaces`,
`list_agents` with `includeArchived: true`, `paseo inspect`; CLI fallbacks
`paseo workspace ls`, `paseo ls -g -a --json`). Match by native child and this
parent epic (title similarity alone is insufficient). Reuse an existing
matching child branch, PR, and worktree workspace when safe; continue an
existing worktree workspace rather than creating another. Apply invariant 3
(child PRs) and the final-PR gate below.

**Final-PR reconciliation gate.** On every start/restart, enumerate every
existing PR whose head is the epic integration branch (and every PR claiming
to be the epic's final PR). Recognize exactly one canonical valid final PR
only when there is one and only one such PR, it targets `main`, is based on
the integration branch's allowed ancestry, is correctly linked to the epic
and all required child PRs, is not a draft, and has no conflicting, failing,
missing, or unknown required status. A missing final PR is the sole state in
which creation may later be considered; any other noncanonical state is
terminal/repair-required (invariant 3) — preserve existing PRs, stop, never
create another.

For each child, create/resume the branch
`epic/<epic-number>/<child-number>-<slug>` from the integration branch and a
matching Paseo-managed child worktree workspace based on that branch
(invariant 5). Validate branch ancestry against the integration branch before
dispatch and preserve existing worktree workspaces/branches on completion or
failure.

## Phase 3 — Topology and child dispatch

Create one child worker agent per native child, with validated DAG
dependencies. If an OpenSpec change is associated with the epic or
sub-tickets, map the native sub-issues against the OpenSpec task graph in
`openspec/changes/<change-name>/tasks.md` and include the relevant delta
specifications in the worker context.

Dispatch ready nodes in dependency waves; independent nodes in parallel;
serialize the shared-state lane (invariant 10). Keep unrelated nodes moving
when a node fails: a failed/stopped/unresponsive node blocks all its
descendants but not unrelated nodes.

The child dispatch is anchored to the child's exact worktree workspace, not
to the coordinator's. Before dispatch, verify the workspace ID, absolute
path, and branch (`paseo inspect` on the created worker and the workspace
listing); pass that exact existing workspace ID to the dispatch. After the
worker starts, verify placement (`paseo inspect`: `Cwd` = the child worktree
path, `ParentAgentId` set). A worker that starts in the coordinator's
workspace or another child's workspace is a placement failure:
stop/reconcile that dispatch and do not let it modify files (invariant 5).

Each child spec includes the complete fetched issue body verbatim, issue and
parent URLs/numbers, slug, direct/transitive dependencies and predecessor
results, expected files, verification obligations, and these concrete
branch/workspace contract fields:

```text
REPO=<repository name with owner>
WORKSPACE_ID=<exact existing Paseo worktree workspace id>
WORKTREE_PATH=<absolute child worktree path>
CHILD_BRANCH=<exact child branch>
INTEGRATION_BRANCH=<exact published integration branch>
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native child number or URL>
```

The spec must also include the one-PR contract (invariant 3) and this exact
gate:

```
AUTONOMOUS_EPIC_SUBTICKET
PARENT_EPIC=<native epic number or URL>
SUBTICKET=<native sub-ticket number or URL>
```

It must explicitly invoke `implement-auto-paseo` as the only executor, delegate
implementer/explore/reviewer work through Paseo workers per `paseo-delegation`,
preserve parent and child metadata, target the child PR only at the published
integration branch, verify with `gh pr view`, and report its canonical URL
plus completion proof (per `paseo-delegation` section 7) in its final message.

Require all three success proofs independently:

1. the worker reached `idle` — via the completion notification or
   `paseo inspect` (CLI fallback `paseo wait`) — and its final
   message (harvested from `paseo logs`) contains the commit, pushed branch,
   canonical PR URL/number, exact PR base, parent/child metadata, and rendered
   PR verification;
2. the worker is not in `error` state and the harvested report claims success
   with all proof fields;
3. fresh GitHub reconciliation finds exactly one canonical matching child PR.

A worker completion without PR proof is protocol-invalid, not successful. A
worker failure or protocol-invalid completion must never be followed up by
sending a message to that worker expecting resumption. If the worker is
terminal, create a new coordinator-owned recovery implementer agent in the
preserved worktree and branch, subject to the healing bound (invariant 8). A
timeout is a checkpoint, not permission to retry; inspect liveness and worker
state before waiting or recovering, and never create a second PR.

### Dispatch terminal-state and recovery rules

Apply the `paseo-delegation` wait/harvest discipline and terminal-state
matrix to every child worker. Before waiting, sending follow-up guidance, or
scheduling recovery, inspect the current worker state (`paseo ls`,
`paseo inspect`).

## Phase 4 — Child PR eligibility, refresh, repair, and coordinator merge

A child PR is eligible only if it is one canonical matching PR (invariant 3)
whose body links both native child and parent epic, targets exactly the
integration branch, has the expected child branch ancestry, is not draft, has
no conflicts, has passing required checks, and is not missing or unknown in
any required status. Reject failing, missing, unknown, draft, conflicting,
incorrectly based, or incorrectly linked PRs. Preserve the existing PR while
repairing it.

The integration branch may contain validated squash merges of eligible child
PRs and coordinator-owned merge commits needed to maintain the branch; such
coordinator-owned merge commits are explicitly permitted, provided the child
work remains based on the epic's validated ancestry. Every commit must
descend from `main` and remain in that validated child ancestry. A branch
with unexplained, unrelated, or incorrectly based commits, or ancestry that
cannot be established unambiguously, is terminal/repair-required and must not
be used to create or retarget a PR.

Treat child work as a state machine, not a single worker result:

```text
pending -> dispatched -> worker_reported -> child_pr_reconciled
         -> pr_verified -> eligible -> merged -> issue_reconciled
```

A worker-reported success without a canonical child PR becomes
`protocol_invalid_recovery_pending`. A worker failure, interruption, missing
remote base, conflict, or failed required check becomes `recovery_pending`
after GitHub and Paseo reconciliation. An ambiguous branch/PR/worktree,
unsafe ancestry, or exhausted healing budget (invariant 8) becomes terminal
repair-required and blocks descendants.

Before merging a dependent, refresh its stale branch from the current
integration branch. If refresh exposes conflicts or required checks fail,
dispatch a fresh implementer recovery worker in the child's existing worktree
and branch (recovery preserves the existing PR and metadata; it must not
create a new PR). Count attempts per invariant 8.

Only this coordinator may validate and squash-merge an eligible child PR into
the integration branch (invariant 9). After each validated squash merge,
coordinator-owned completion comments/closure may close the matching child
issue (never the epic automatically), and the merge/closure must be
reconciled before advancing. Workers are never authorized to merge PRs or
close issues.

## Phase 5 — Quiescence and final integration PR

Continue scheduling, refreshing, repairing, merging, and reconciling until
the validated graph reaches quiescence: every node merged/completed, terminal
failed, or terminal blocked, with no runnable or in-flight work. Failed or
blocked nodes block descendants; unrelated nodes continue. Do not create a
final PR while any node is failed, blocked, ambiguous, unsafe, or incomplete.

Before every wait, verify that at least one expected worker is actually
`running`, or that an explicitly pending worker question requires a response.
An idle or errored worker is not enough. If no active worker remains, do not
enter an unbounded wait: reconcile worker/GitHub state, schedule a valid
recovery or ready node, mark descendants blocked, or stop with a precise
terminal report (the `paseo-delegation` no-active-worker rule).

After every worker completion, independently validate the worker ID, worker
outcome, final-message proof, commit on the expected child branch, pushed
branch, exactly one canonical PR, exact integration-branch base, parent/child
metadata, rendered PR body, and required statuses. Worker lifecycle
completion alone is never semantic child completion.

When — and only when — all children are validated and squash-merged, and the
final-PR reconciliation gate has found no existing PR from the integration
branch:

1. If an OpenSpec change was associated with this epic
   (`openspec/changes/<change-name>/`), verify all tasks in `tasks.md` are
   marked complete and archive the change via
   `openspec archive "<change-name>" --yes` on the integration branch,
   staging and committing any updated canonical specs.
2. Create exactly one comprehensive PR from `epic/<epic-number>-<slug>` to
   `main`. It must reference the parent epic and every merged child PR,
   explain rationale, implementation details, verification, deviations, and
   risks, and be verified with `gh pr view` (including rendered body). Do not
   auto-merge it. If reconciliation recognizes exactly one canonical valid
   final PR, reuse it and never create another (invariant 3).

## Reports, testing, and restart safety

Produce a durable final report with epic number, workspace/branch names,
validation graph/order, wave and shared-state lane membership, every child
once, branch/worktree workspace, predecessors, PR URL, merge/closure result,
healing count, and precise failure or block reason. Documentation-only changes
still require checking Markdown format/structure and applicable link or
consistency obligations; run the repository's documented lint/format checks
when available and report commands not applicable rather than claiming they
ran.

A rerun refetches and revalidates the epic and children, rechecks branch
ancestry, reconciles PRs and Paseo worktree workspaces, resumes safe work, and
avoids duplicate workers, branches, PRs, merges, or closures. If the epic
graph/order/body changed, stop for fresh validation rather than assuming
prior state.
