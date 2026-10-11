---
name: plan-feature
description: "Use when the user wants to plan a feature/improvement and produce a GitHub ticket (NOT implement it). Triggers: 'plan this feature', 'I want to add X', 'help me think through Y', 'design feature Z', 'prepare a plan for'. Detects complex features and proposes splitting into an epic with sub-tickets when appropriate. Use ONLY when the goal is to produce a plan + GitHub issue, not to start coding."
---

# Plan Feature

Turn a free-form feature/improvement idea into a reviewed plan saved as a
GitHub ticket. Complex features are automatically detected and proposed to
be split into an epic with sub-tickets linked via GitHub's native sub-issue
feature. **Do NOT implement.** This skill ends when the ticket(s) exist
(or, for Phase 5.5 option D, when the implementation handoff has been
dispatched and accepted).
Every generated plan must be decision-complete: an implementation agent must
be able to execute it without asking a product or technical question.

The plan body templates live in [templates.md](templates.md); this file owns
the workflow. `implement-ticket` parses published bodies that follow those
templates.

Research, impact analysis, and other delegated steps in this skill follow
the **worker-delegation** skill: it owns harness detection, dispatch
mechanics, batching, wait/harvest discipline, and recovery. When this skill
and `worker-delegation` disagree on delegation mechanics, `worker-delegation`
wins.

## Workflow

### Phase 0 — Map project context (run once, reuse throughout)

Do not load every project document or cache the whole repository in context at
this stage. First build a lightweight map of where relevant information lives
and how to search it.

**Resolve every project fact through the resolution ladder:**

1. **Profile slot:** read `.agents/project.yaml` (the project profile, when
   present) for the needed slot. A declared slot is deterministic and
   authoritative for facts; `AGENTS.md` and nested guidance remain
   authoritative for conventions and rationale ("why").
2. **Probe heuristic:** if the slot is absent or stale (the referenced path or
   command no longer resolves), fall back to a generic probe — manifests,
   `rg --files`, `find` — and **announce the assumption** you resolved with.
3. **Ask:** if the probe is ambiguous, stop and ask the user. Never silently
   guess.

Run these discovery steps in parallel:

1. **Repo info** (uses the logged-in `gh` CLI — works for GitHub.com and
   GitHub Enterprise automatically):
   ```
   gh repo view --json nameWithOwner,defaultBranchRef,description
   ```
   Capture `nameWithOwner`, default branch, and description.
2. **Project guidance:** locate `AGENTS.md`, `README.md`, nested guidance
   files, and the docs directories declared by the profile (`layout.docs`,
   else probe) with `find`/`rg --files`. Treat the closest applicable
   `AGENTS.md` and relevant documentation as authoritative for conventions.
3. **Functional requirements & specifications:** locate canonical capability specs
   with `find openspec/specs -type f` (and active changes with
   `find openspec/changes -type f`). These files are the product source of
   truth. Candidate specs can be identified by feature domain, capability
   names, headings, and requirement tags.
4. **Source and tests:** map workspaces and likely source/test locations.
   Use the profile's `layout.workspaces` when present; otherwise probe
   manifests and package configuration to discover workspaces and announce
   the assumption. Later search these paths with feature terms, domain
   nouns, route names, component names, exported symbols, and existing test
   names before opening files.
5. **Commands and infrastructure:** record available lint, typecheck, test,
   format, build, static-analysis, and database commands from the profile's
   `commands` section (probe manifests and announce the assumption if
   absent). Locate manifests and CI workflows with
   `rg --files -g 'package.json' -g '.github/workflows/**'` plus any
   deploy/infra configuration declared by the profile (`infra`). Read
   relevant files only after the affected workspace is known.
6. **Database and generated code:** read the profile's
   `layout.migrations_dir` and `layout.generated_files` slots. If absent or
   stale, probe for migration directories and generated files and announce
   the assumption; if ambiguous, ask the user. Read only migrations whose
   names or contents match the feature; the generated file declared in
   `layout.generated_files` is the ownership point for its types and its
   header is enough until a schema change is established.
7. **Platform documentation:** note in-repo or vendored documentation paths
   from the profile's `layout.vendored_platform_docs` slot (probe references
   in applicable guidance and announce the assumption if absent). Search
   those docs for APIs implicated by the feature; never assume platform
   conventions from training data.
8. **Git history & related work:** run in parallel:
   ```
   gh issue list --state open --limit 20
   gh issue list --state closed --limit 10
   git log --oneline -30
   ```

The Phase 0 output is a context map: paths, commands, search terms, and
applicable guidance — not a cache of all documents. If `gh` is not
authenticated, surface the error and ask the user how to proceed.

### Phase 0.5 — Scoped context review and discussion

Use the context map and the user's feature description to identify the
smallest relevant set of context resources. Search first, then read only
matching guidance, specs, source files, tests, migrations, platform docs,
issues, PRs, and commits. Start with applicable `AGENTS.md`, then follow links
to relevant docs and specs. Trace the current implementation and tests far
enough to describe existing behavior; expand scope only when a dependency or
cross-cutting concern is discovered.

Run the interactive discussion portion when ANY of these apply:

- User explicitly says "let's discuss", "let's plan", "I'm not sure", "help
  me think through this", or similar
- The goal is vague, ambiguous, or has multiple viable paths
- You can't determine what the user actually wants after scoped review
- The request touches a complex area (auth, DB schema, cross-cutting concern)
  and the user hasn't specified an approach

**Otherwise, complete the scoped review and go straight to Phase 1.**

#### Discussion rules

- Ask **one question at a time**, each with a **recommended answer** in
  italics.
- Before asking, try to answer it yourself by exploring the codebase or
  reviewing Phase 0 context. If you find the answer, state it and move on
  — don't ask the user what you already know.
- Keep questions focused on the **key unknowns** that block proceeding —
  don't ask about details that can be figured out later.
- Treat every implementation-affecting unknown as a decision to close. Do not
  confuse an efficient discussion with an incomplete one.
- After each answer, assess: "Do I have enough to proceed?" If the goal is
  clear enough to restate in 1-2 sentences, **propose moving on**:
  > I think I have enough to proceed. Want me to draft the plan, or should
  > we keep discussing?
- User can say "yes/move on/proceed" to end the discussion, or "let's keep
  going" to continue.
- User can say "stop" at any time, but may only skip the remaining discussion
  after all implementation-affecting decisions have been explicitly resolved.
  If any remain open, offer the recommended answers and wait for explicit
  approval, or end without drafting a plan.
- **Default is efficient, not exhaustive.** 1-3 questions is typical, but
  continue until every implementation-affecting decision is closed.
- When the discussion ends, summarize what was decided in 2-3 sentences.

### Phase 1 — Restate intent & infer context

Take the user's free-form description and everything learned in Phase 0 /
Phase 0.5, and produce a **drafted context** for the plan. The agent does
the heavy lifting — the user confirms, edits, or skips.

#### Infer these sections:

1. **Problem** — what's broken, missing, or painful? Infer from the user's
   description + what exists in code. If unclear, record a working "TBD"
   internally and resolve it before drafting the final plan.
2. **Current state (Before)** — what exists today and its limitations.
   Infer from codebase exploration. Write "Nothing exists" if greenfield.
3. **Proposed change (After)** — what will exist after, in plain language
   (not implementation details). Infer from the user's description.
4. **Decision rationale** — why this approach? Infer if the user mentioned
   constraints or alternatives. Otherwise draft a recommendation based on
   codebase patterns. Any inferred recommendation is a working proposal, not
   a final decision, until it is explicitly accepted or replaced.
5. **Related context** — search `gh issue list`, `gh pr list`, and
   `git log` for related work. Link anything relevant.

#### Present the draft

Show the full drafted context to the user. Treat this as a working draft, not
yet as a decision-complete plan:

> Here's what I inferred. Confirm, edit, or skip anything — nothing is
> mandatory.
>
> **Problem:** ...
> **Current state:** ...
> **Proposed change:** ...
> **Decision rationale:** ...
> **Related context:** ...

The user can:

- Say "looks good" / "go with it" / "proceed" → confirm all, move to Phase 2
- Edit specific fields → update and move on
- Say "skip" → omit skipped narrative sections from the plan. A user cannot
  skip an implementation-affecting decision; route it to Phase 4 instead.

Narrative context fields are optional. Implementation-affecting decisions are
mandatory and must be closed before Phase 5, even when the user wants to
proceed with minimal context.

### Phase 1.5 — Complexity assessment

Evaluate whether the feature should be split into an epic with sub-tickets.
Check each complexity signal:

- **Multi-area scope:** Touches 3+ distinct source areas (e.g., dashboard +
  detail page + shared components, or UI + DB + auth)
- **Natural decomposition:** Can be broken into independently shippable
  pieces that each deliver value on their own
- **Plan size:** Would produce a plan body exceeding ~400 lines if kept as
  a single ticket
- **Ordered work:** Involves dependencies where A must ship before B (e.g.,
  infrastructure hook → feature components that use it)
- **Spec breadth:** Touches 3+ spec files or introduces 3+ new FR
  requirements

**If 2+ signals match AND the user hasn't already proposed splitting:**

Ask the user (one question, with a recommended answer):

> This feature looks complex enough to split into an epic with sub-tickets.
> Should I break it into multiple tickets linked via GitHub's sub-issue
> feature?
>
> - **Yes, split into an epic** — I'll propose a ticket breakdown with
>   dependencies _(recommended)_
> - **No, keep as single ticket** — proceed with a single plan

**If the user already said "split", "epic", "multiple tickets", or similar
— skip the question and go directly to Phase 1.6.**

**If the user declines splitting or only 0-1 signals match — skip Phase 1.6
and proceed to Phase 2 as a single-ticket flow.**

### Phase 1.6 — Epic structure proposal (conditional)

**This phase only runs when Phase 1.5 resulted in a "split" decision.**

Based on Phase 0 context, Phase 1 inferred context, and the complexity
analysis, draft an epic breakdown:

1. **Epic title** — ≤72 chars, prefixed with `Epic:`. Summarizes the
   overall initiative.
2. **Sub-ticket list** — for each sub-ticket:
   - Stable plan key (`S1`, `S2`, ...) assigned in implementation order. This
     key is not a GitHub issue number and remains unchanged after issue
     creation.
   - Working title (≤72 chars, following commit-message convention:
     lowercase prefix + colon + imperative)
   - The exact title must be reused in the epic definition, child plan H1,
     GitHub issue title, graph node declaration, and implementation order.
   - Scope description (2-3 sentences of what this sub-ticket delivers)
   - Source files and spec files it touches
   - Whether it's a prerequisite for other sub-tickets
3. **Dependency graph** — declare every sub-ticket node exactly once, then
   list directed edges using the stable keys. An edge points from a blocker to
   the sub-ticket it blocks:
   ```
   Nodes:
   - `S1` — <exact sub-ticket title>
   - `S2` — <exact sub-ticket title>
   - `S3` — <exact sub-ticket title>

   Edges (blocker -> dependent):
   - `S1` -> `S2`
   - `S1` -> `S3`
   ```
   Include every node even when it has no edges. Write `- none` under Edges
   when all sub-tickets are independent. Never use issue-number placeholders
   such as `#N`.
4. **Implementation order** — numbered sequence respecting dependencies.
   Include each stable key exactly once, paired with its exact title.
   Sub-tickets with no blockers are first; dependent ones follow.

Present the breakdown to the user for review. The user can:

- **Confirm** → proceed to Phase 2 (research scoped per sub-ticket)
- **Edit** (add/remove/reorder sub-tickets) → update and proceed
- **Merge back into single ticket** → fall through to Phase 2 as
  single-ticket flow

After confirmation, cache the approved sub-ticket list for use in all later
phases. All subsequent phases operate in **epic mode** — research,
impact analysis, and plan drafting are scoped per sub-ticket.

Stable keys are assigned only after the sub-ticket list is approved. If the
list changes before ticket creation, regenerate the final keys and update all
references together. After the first GitHub issue is created, keys, titles,
scope, and dependency edges are immutable for that epic; stop and revise the
epic deliberately if they need to change.

### Phase 2 — Research best practices & spec conformance (dispatch an `explore` worker)

**Epic mode:** If Phase 1.6 was executed, pass the approved sub-ticket list
to the `explore` worker. Scope research to each sub-ticket's files and
spec areas. Return findings **grouped by sub-ticket** so they can be used
directly in each sub-ticket's plan.

**Single-ticket mode:** Research the feature as a whole (default behavior
below).

Dispatch a read-only `explore` worker through the **worker-delegation**
contract (role `explore`, `MAY modify files: no`, a readable kebab-case slug
such as `explore-<feature-area>`, with the research brief below as the task
spec). Prefer thoroughness in the brief. Do not pass it a bulk dump of
Phase 0 context or cached documents. Pass the context map's paths, discovery
commands, search strategy, applicable repository guidance locations, and (if
in epic mode) the approved sub-ticket list. Instruct it to build the relevant
context itself, starting with searches and reading only matching resources.
Ask it to:

1. Search the project's mapped source directories for established patterns
   relevant to the feature (file structure, helpers, utilities, conventions).
   Use feature terms, domain nouns, route/component names, symbols, and test
   names, then return `file_path:line_number` references.
2. Read the applicable `AGENTS.md`, `README.md`, and relevant `docs/` files
   discovered by those searches. Do not bulk-read unrelated guidance.
3. **Cross-check existing code against relevant `openspec/specs/` capabilities.**
   Locate candidate specs under `openspec/specs/<capability>/spec.md`. For each
   requirement that the feature touches or relates to:
   - Read the relevant spec file(s).
   - Compare the spec's acceptance criteria against what the code actually
     does (trace the code paths, check component behavior, inspect tests).
   - Return a **spec conformance report**: for each relevant requirement, state
     whether the code `matches`, `partially matches`, or `diverges` from
     the spec, with specific details on what's missing or different.
   - If a requirement is specified but the code diverges, **flag it explicitly**
     as a spec drift.
   - Note any missing scenarios or requirements so the change proposal can
     address it.
4. If Phase 0 found in-repo platform docs (vendored or local), read the
   relevant guides for the feature. **Never assume platform APIs/conventions
   from training data** — always defer to in-repo docs when present.
5. If the feature touches DB/auth/RLS, read the migrations directory resolved
   via the ladder (profile `layout.migrations_dir`, else probe) and consult
   the per-stack skill declared by the profile's `stack` section (e.g. the
   installed `supabase` skill) for best practices.
6. **Search for related past decisions:** look through git log, closed PRs,
   and abandoned branches for similar features or reverted changes. Note
   what was tried before and why it was changed — this enriches the
   Decision rationale section.
7. Return: (a) patterns found with file refs, (b) files likely to need
   changes, (c) ambiguity requiring user input, (d) spec conformance report,
   (e) related past decisions found. Every ambiguity requiring user input must
   become a tracked decision in Phase 4; it must not be copied into the final
   plan as an unresolved item.
   **In epic mode:** organize (a)-(e) per sub-ticket.

Cross-validate the worker's report per the `worker-delegation` wait/harvest
discipline before relying on it.

**Inline fallback (only when no worker capability exists).** Only when the
detected harness has no worker capability at all (no sub-agent mechanism of
any kind), perform the research inline in this session instead — this is the
sole sanctioned exception to the no-inline rule, and it must be announced to
the user. If the harness has a worker capability, the dispatch is mandatory.

If the explore findings report **no established local pattern** for the
feature (or a major sub-component of it), THEN and only then:

- Use `webfetch` on official docs for the relevant platform(s) detected in
  Phase 0 — prefer URLs already referenced in `AGENTS.md` or `README.md`.
- If still nothing, use `websearch` for community best practices.
- Cite every external source with its URL.
- If a doc can't be fetched (network blocked, auth-walled), record the gap
  explicitly in the plan's _Best practices researched_ section and flag the
  affected decision as needing verification during implementation. Never
  silently assume.

### Phase 3 — Dependency / impact analysis

**Epic mode:** Organize the impact analysis **by sub-ticket**. Each
sub-ticket should list its own source files, tests, spec docs, docs,
infrastructure, and database changes. This per-sub-ticket breakdown feeds
directly into the sub-ticket plan definitions in Phase 5.

**Single-ticket mode:** Analyze the feature as a whole (default behavior
below).

From the explore results, the scoped Phase 0.5 context, and the context map,
enumerate everything that needs to change:

- **Source files** (paths)
- **Tests** (whatever the project uses: unit/integration/e2e/component
  stories — check for `*.test.*`, `*.spec.*`, `__tests__/`, `tests/`,
  `storybook/`, etc.)
- **Spec / capability changes** — for every capability requirement the
  feature touches:
  - New requirements: draft requirement title, user scenario (GIVEN/WHEN/THEN),
    and target capability directory under `openspec/specs/<capability>/`.
  - Modified requirements: describe what changes (scenario updates, new
    scenarios, requirement wording).
  - Spec drift found in Phase 2: list each mismatch and the fix needed in the
    spec (or in code, if the spec is correct and the code is wrong). Select the
    resolution in Phase 4; never leave "user to decide" in the final plan.
  - Identify which `openspec/specs/<capability>/spec.md` files are affected.
- **Docs** (docs directories resolved via the ladder — profile
  `layout.docs`, else probe; `README.md`, `AGENTS.md` if introducing a new
  convention)
- **Infrastructure** (deploy/CI configuration resolved via the ladder —
  profile `infra`, else probe; env var **names only** — never paste real env
  values, per the secrets policy in `AGENTS.md`)
- **Database** (migrations under the ladder-resolved migrations directory —
  profile `layout.migrations_dir`; generated files from profile
  `layout.generated_files`, regenerated via their declared
  `regenerate_command`)

In epic mode, treat schema/migration work, generated-file regeneration, and
local-stack mutations as shared state. Keep a migration and its required
generated-file regeneration in one sub-ticket whenever possible. If they must
be split, make the regeneration sub-ticket explicitly depend on the migration
sub-ticket and record the dependency in the graph and implementation order.

### Phase 4 — Close all implementation decisions (mandatory gate)

This phase always runs and must complete before Phase 5. Build a decision
register from all prior phases and the explore report. Include, at minimum:

- Product behavior, scope boundaries, and user-visible defaults
- Architecture, UX, data model, auth/security, migration, and integration
  choices
- Test strategy and manual verification expectations
- Spec drift resolutions: update the spec, update the code, or update both
- Epic boundaries, dependencies, and ordering
- Any assumption that could cause two reasonable implementers to produce
  different behavior

For each unresolved item:

1. Try to resolve it from the repository, functional requirements, platform
   docs, and established patterns before asking the user.
2. If it remains unresolved, ask **one question at a time** and provide a
   recommended answer in _italics_.
3. Record the explicit outcome as a selected decision, including the basis or
   source. A user may approve the recommendation, provide a different answer,
   or approve a batch of clearly listed recommendations.

Do not proceed to Phase 5 until every item has an explicit outcome. Silence,
"proceed", "stop", or approval of the general context does not resolve an
individual decision unless the decision is clearly listed and explicitly
included in that approval.

The following are not resolved decisions and must never appear in a final
plan: `TBD`, `TODO`, `unknown`, `to be decided`, `user to decide`,
"we can choose later", an unaccepted "Recommendation", an unanswered
question, or an unselected alternative. If the user declines to decide, use
the repository-backed recommendation only after the user explicitly approves
it; otherwise stop without drafting or creating a ticket.

When this phase ends, summarize the closed decision register in 2-3 sentences
and state that no implementation-affecting questions remain.

### Phase 5 — Scaffold OpenSpec change & draft the plan

Before writing, saving, or showing the plan, run the decision-completeness
gate:

- Confirm the Phase 4 decision register has an explicit outcome for every
  implementation-affecting item.
- Replace every working `TBD`, recommendation, assumption, implementation
  placeholder, and unresolved alternative with the selected decision or omit
  it if it is optional narrative context.
- Ensure every spec-drift entry has a selected resolution.
- Ensure every epic and sub-ticket has closed decisions for its own scope.
- In epic mode, ensure every sub-ticket has one stable key, a unique exact
  title, and that the same key/title pair appears in the sub-ticket list,
  graph node declarations, implementation order, sub-ticket definition, child
  plan H1, and planned GitHub issue title.
- In the epic body, include the coordinator activation gate exactly once. Its
  `SUBTICKET` value is the native issue number or URL of the first child in
  the approved implementation order; this is a deterministic activation
  witness, not a replacement for the stable-key graph or the per-child gate
  that the `implement-ticket` epic coordinator injects into each dispatched
  task specification.
- Replace all content placeholders before showing the final plan. The only
  placeholders permitted before GitHub issue creation are the publication
  metadata values for issue numbers and URLs, including the epic activation
  gate; Phase 6 must replace them before the epic is considered ready for
  `implement-ticket` epic mode.
- Scan the proposed plan for unresolved markers, including `TBD`, `TODO`,
  `unknown`, `to be decided`, `user to decide`, `choose later`, and question
  marks used as unanswered questions.

If any check fails, return to Phase 4. Do not save, show, or create a plan
that fails this gate. Re-run the gate after every user-requested plan edit.

#### Scaffold OpenSpec Change

Scaffold the OpenSpec change directory:

```bash
openspec new change "<change-name>"
```

Populate the change artifacts in `openspec/changes/<change-name>/`:

1. `proposal.md`: Why, what changes, capabilities affected, and impact.
2. `specs/<capability>/spec.md`: Delta specifications using standard `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`, and GIVEN/WHEN/THEN scenarios.
3. `design.md`: Context, goals/non-goals, architectural decisions, and trade-offs.
4. `tasks.md`: Ordered checklist (`- [ ]`) grouped by phase with clear completion criteria.

Validate the generated OpenSpec change:

```bash
openspec validate "<change-name>" --strict
```

Produce the plan body using the applicable template in
[templates.md](templates.md). The plan embeds the OpenSpec change name,
summary, and links to local change artifacts.

Show the plan to the user. **Iterate** based on feedback — do NOT skip this
step and do NOT create the ticket(s) until the user explicitly approves the
plan. If feedback introduces a new implementation-affecting choice, return to
Phase 4, close it, and re-run the decision-completeness gate before showing the
revised plan.

### Phase 5.5 — Handle uncommitted OpenSpec artifacts (mandatory gate)

This phase always runs after the plan is approved, before any ticket is
created. At this point the OpenSpec change artifacts under
`openspec/changes/<change-name>/` exist locally and are typically
uncommitted. Present exactly these four options to the user:

> The OpenSpec change artifacts are uncommitted. How should I handle them
> before creating the ticket?
>
> - **A) Ticket only** — create the ticket; leave the OpenSpec files
>   uncommitted locally. The implementer commits them together with the
>   implementation.
> - **B) Commit to `main`** — commit and push the OpenSpec files to
>   `origin/main`, then create the ticket.
> - **C) Feature branch** — create the ticket first, then create a branch
>   `feature/<N>-<slug>` (epic: `epic/<N>-<slug>`, where `N` is the GitHub
>   ticket number) off fresh `origin/main`, commit and push the OpenSpec
>   files to that branch, and remove the local uncommitted artifacts from
>   the `main` working tree. The ticket will state that all work happens on
>   that branch.
> - **D) Feature branch + implementation handoff** — everything in C, then
>   also dispatch a fire-and-forget implementation handoff through the
>   worker-delegation skill: a worktree-based placement checked out on that
>   branch, a sub-agent launched in it running the implement skill
>   (`implement-ticket` for single tickets, `implement-ticket` epic mode for
>   epics) instead of handing the user a copy-pasteable command. Requires a
>   worker-capable harness; if the harness or `worker-delegation` preflight
>   fails, report the error and stop — do not silently fall back to option C.

Do not proceed to Phase 6 until the user picks A, B, C, or D. Then apply the
selected option:

**Option A — no git actions.** Leave the artifacts uncommitted. The ticket
body's `OpenSpec Change` section must note that the artifacts are local-only
and that the implementer commits them (under the same change directory) with
the implementation.

**Option B — commit to `main`:**

```bash
git add openspec/changes/<change-name>
git commit -m "spec: scaffold openspec change <change-name>"
git push origin main
```

Commit only files under the change directory — never stage unrelated working
tree changes or env files. The project's declared format command and
pre-commit hook (see `.agents/project.yaml` `commands`) may reformat; that is
expected.

**Option C — feature branch off fresh `origin/main` (performed in Phase 6):**

The branch name embeds the GitHub ticket number so branches stay traceable
to their tickets: `feature/<N>-<slug>` for a single ticket, `epic/<N>-<slug>`
for an epic (one shared epic branch for the whole epic; every sub-ticket is
implemented on it — do not create per-sub-ticket branches). Keep the slug
short — a few kebab-case words derived from the ticket title, not the full
title.

Because the branch name needs the ticket number, **the ticket is created
first and the branch afterwards**. In this phase only record the selection —
do not perform any git actions yet. In Phase 6, after the ticket
(single-ticket mode) or the epic (epic mode) is created and its number `N`
is captured, run the procedure below. For epic mode, run it after the epic
is created but **before** creating sub-tickets, so every child body already
names the working branch.

⚠️ **Never switch branches in the current working tree.** The repository is
checked out on `main` and **other agents may be working on it right now** —
running `git switch`/`git checkout` to the feature branch in place would
disrupt them. Use one of these two methods instead; both leave the current
working tree on `main`, untouched:

_Method 1 — temporary worktree (simplest, use by default):_

```bash
git fetch origin
wt=$(mktemp -d)
git worktree add --detach "$wt" origin/main
mkdir -p "$wt/openspec/changes"
cp -R "$(pwd)/openspec/changes/<change-name>" "$wt/openspec/changes/"
git -C "$wt" add openspec/changes/<change-name>
git -C "$wt" commit -m "spec: scaffold openspec change <change-name>"
git -C "$wt" push origin HEAD:refs/heads/<N>-<slug>
git worktree remove "$wt"
```

- Run `git fetch origin` first so the branch starts from the latest
  `origin/main`, not a stale local `main`.
- the project's pre-commit hooks may not run inside the temp worktree — make
  sure the copied files are already formatted with the project's declared
  format command before committing.

_Method 2 — in-memory via plumbing (no worktree; never touches HEAD, the
index, or any file outside `openspec/changes/`):_

```bash
git fetch origin
base=$(git rev-parse origin/main)
tmp_index=$(mktemp)
GIT_INDEX_FILE="$tmp_index" git read-tree "origin/main^{tree}"
GIT_INDEX_FILE="$tmp_index" git add openspec/changes/<change-name>
tree=$(GIT_INDEX_FILE="$tmp_index" git write-tree)
commit=$(git commit-tree "$tree" -p "$base" \
  -m "spec: scaffold openspec change <change-name>")
git push origin "$commit":refs/heads/<N>-<slug>
rm -f "$tmp_index"
```

- The temp index is process-local (`GIT_INDEX_FILE`) — the repo's real index
  and working tree are never modified, so concurrent agents on `main` are
  unaffected.

For both methods:

- Commit only files under the change directory — never stage unrelated
  working tree changes or env files.
- **Roll back the local artifacts.** Once the branch is pushed, the
  uncommitted `openspec/changes/<change-name>/` files in the `main` working
  tree are redundant — they live on the pushed branch. Remove only the
  change directory, never other uncommitted work:
  ```bash
  git status --porcelain -- openspec/changes/<change-name>
  git clean -fd -- openspec/changes/<change-name>
  ```
  If `git status --porcelain` shows anything other than untracked files
  under the change directory (for example modified tracked files), stop and
  ask the user before deleting. If the artifacts are ever needed again, they
  are on the pushed branch.
- Replace the plan body's `Working branch` line with the actual branch name
  (`feature/<N>-<slug>` or `epic/<N>-<slug>`) and publish it with
  `gh issue edit <N> --body-file`. In epic mode, do this on the epic body
  **before** creating sub-tickets so every child body already names the
  branch.
- Do not check out the new branch locally afterwards — leave it
  un-checked-out so the implementer (or a worktree placement in the epic
  coordinator) can check it out fresh.
- The ticket body's `OpenSpec Change` section must name the branch and state
  that **all implementation happens on this branch, not on `main`**. In epic
  mode, state this in the epic body and in every sub-ticket body.

**Option D — feature branch plus implementation handoff (performed in
Phase 6, after the Option C procedure):**

Performs all of Option C (ticket/epic first, branch carrying the OpenSpec
artifacts, local rollback, `Working branch` write-back), then additionally
starts implementation immediately as a **fire-and-forget handoff** per the
worker-delegation skill: resolve the harness per its detection rules, then
run the harness file's fire-and-forget handoff recipe — a worktree-based
placement checked out on the working branch, a sub-agent launched in it,
and the implement skill invoked there. Do not embed harness command
sequences here — the harness file owns all command-level details. The
current session never runs the implement skill itself — the dispatched
sub-agent owns the implementation and becomes the supervisor of any further
delegation. Requires a worker-capable harness; if the worker-delegation
preflight fails, report the error and stop — do not silently fall back to
option C.

Handoff timing (run in Phase 6 — single-ticket mode: right after step 3's
branch push and `Working branch` write-back; epic mode: after the step 8
body verification, so the epic coordinator never starts before the children
are published):

Dispatch the fire-and-forget handoff with this brief as the worker prompt:

- First run `git fetch origin` in the current checkout — the working-branch
  ref must exist locally before worktree creation or the checkout fails.
- Create a new worktree-based placement for repo `<repoId>` named `<N>-<slug>`
  (harness naming per the harness file), linked to GitHub issue `<N>`.
  Prefer root-level placement (no parent lineage) unless the user asked for
  it to be parented under the current context. Repo setup hooks should run so
  dependencies are installed for later test runs.
- The placement MUST end up checked out on the working branch
  `feature/<N>-<slug>` (single ticket) or `epic/<N>-<slug>` (epic). Verify
  the checked-out branch inside the new placement after creation (`git
  switch <branch>` DWIM-tracks `origin/<branch>`).
- Launch the harness's default worker agent in that placement and send this
  command exactly once (re-sending the same command queues a duplicate
  steering message in the agent's queue):
  - single-ticket: `/skill:implement-ticket <ticket-title>`
  - epic mode: `/skill:implement-ticket <epic-number>`
- Verify acceptance by reading the worker's initial output (skill loaded,
  turn started), not by re-sending.
- Report the placement path, branch, and sub-agent handle to the user.
- Then stop: a handoff is done when the new placement id and worker handle
  have been reported and the prompt delivery was accepted. Do not supervise,
  monitor, or wait for the sub-agent, and never also run the implement skill
  in the current session for the same ticket/epic.
- Never paste secret values into prompts — the command references only the
  ticket/epic number; the sub-agent reads issue bodies from GitHub.

After applying the option: for A and B, set the plan body's `Working branch`
line to `main` before creating tickets in Phase 6. For C and D, the branch
name (embedding the ticket number) is resolved in Phase 6 after the ticket
exists and is written back with `gh issue edit`; for D the fire-and-forget
handoff follows the branch write-back per the timing above.

### Phase 6 — Create the GitHub ticket(s)

#### Single-ticket mode

1. Show the user the proposed ticket title (≤ 72 chars, summarizing the
   plan). Wait for confirmation.
2. Create the ticket:
   - Pass the approved plan body via stdin:
     ```
     gh issue create --title "<title>" --body-file - <<'PLAN_EOF'
     <full plan markdown content here>
     PLAN_EOF
     ```
   Do not apply any labels automatically. The user can add labels afterwards
   via `gh issue edit <number> --add-label <label>` if desired.
3. **Option C (Phase 5.5): create the feature branch.** If Phase 5.5
   selected option C or D, run the Option C procedure from Phase 5.5 with
   `N` = this ticket's number: create and push `feature/<N>-<slug>` carrying
   the OpenSpec artifacts, roll back the local uncommitted artifacts from
   the `main` working tree, then replace the `Working branch` line in the
   plan body with the actual branch name and publish it via
   `gh issue edit <N> --body-file`. For options A/B the `Working branch`
   line already says `main` and this step is skipped.
4. **Option D (Phase 5.5): dispatch the handoff.** If Phase 5.5 selected
   option D, run the Option D fire-and-forget handoff from Phase 5.5 with
   the working branch `feature/<N>-<slug>` and the command
   `/skill:implement-ticket <ticket-title>` (the exact title confirmed in
   step 1), immediately after step 3's branch push and `Working branch`
   write-back.
5. Tell the user the ticket is ready. If option D was selected, report that
   implementation was already started in the dispatched sub-agent
   (placement path, branch, worker handle) and skip the copy-pasteable
   command. Otherwise provide a copy-pasteable command to start
   implementation:
   ```
   /skill:implement-ticket <ticket-title>
   ```
   where `<ticket-title>` is the exact ticket title confirmed in step 1.
   Example: `/skill:implement-ticket Add bulk archive to <capability>`

#### Epic mode

1. Show the user the proposed epic title (≤72 chars, prefixed with
   `Epic:`). Wait for confirmation. Also confirm every stable sub-ticket key
   and exact title. The exact epic title must be used as the epic body's H1.
2. Create the epic ticket first:
   - Pass the approved epic body via stdin:
     ```
     gh issue create --title "<epic title>" --body-file - <<'PLAN_EOF'
     <full epic plan markdown content here>
     PLAN_EOF
     ```
   Capture the epic ticket number from the output.
3. **Option C (Phase 5.5): create the epic branch.** If Phase 5.5 selected
   option C or D, run the Option C procedure from Phase 5.5 with `N` = the
   epic's number: create and push `epic/<N>-<slug>` carrying the OpenSpec
   artifacts, roll back the local uncommitted artifacts from the `main`
   working tree, then replace the `Working branch` line in the epic body
   with the actual branch name via `gh issue edit <epic-number>
--body-file`. This must happen **before** creating sub-tickets so every
   child body already names the shared working branch.
4. Create each sub-ticket with the exact approved title and `--parent` to link
   it to the epic. The child plan body must already contain its stable
   `Epic sub-ticket key` metadata line.
   ```
   gh issue create \
     --title "<sub-ticket title>" \
     --body-file - \
     --parent <epic-number>
   ```
   Pass the full child plan body via stdin:
   ```
   gh issue create \
     --title "<sub-ticket title>" \
     --body-file - \
     --parent <epic-number> <<'PLAN_EOF'
   <full child plan markdown content here>
   PLAN_EOF
   ```
   If `--parent` fails (older `gh` version), create the sub-ticket without
   `--parent` and link it afterwards:
   ```
   gh issue edit <epic-number> --add-sub-issue <sub-ticket-number>
   ```
   Capture each sub-ticket number from the output.
5. Finalize the published bodies before declaring the epic ready. Replace the
   publication placeholders in the epic body with the actual epic number and
   URL and the complete native sub-ticket number/URL list. Finalize the one
   epic-level activation gate in that body with the actual epic number or URL
   and the native number or URL of the first child in implementation order.
   Replace any publication-only issue/URL placeholders in the epic and child
   bodies with actual metadata. The body H1 and GitHub issue title must be
   identical. If a body needs publication-time substitutions, use temporary
   files outside the repository and remove them after publication. Do not
   retain local plan files. Update the temporary body before running
   `gh issue edit`.

   Publish the finalized bodies with:

   ```
   gh issue edit <epic-number> --body-file <final-epic-body-file>
   gh issue edit <sub-ticket-number> --body-file <final-child-body-file>
   ```

   Do this for every child. Do not merely append metadata to the original
   issue bodies, because the original draft placeholders would remain.

6. Re-fetch the epic and every child before continuing:
   ```
   gh issue view <epic-number> --json number,title,body,url,subIssues,subIssuesSummary
   gh issue view <sub-ticket-number> --json number,title,body,url,subIssues,subIssuesSummary
   ```
   Confirm that native `subIssues` contains exactly the created children,
   every key/title pair is consistent across the epic and child bodies, the
   epic activation gate occurs exactly once and names the epic plus the first
   native child in implementation order, the graph declares every key exactly
   once, the order declares every key exactly once and is topological, and no
   publication or template placeholders remain. If any check fails, do not
   recommend starting the `implement-ticket` epic coordinator; repair and
   re-fetch first.
7. Do not apply any labels automatically. The user can add labels afterwards.
8. Confirm the published epic and child bodies match the approved plan
   content and contain no publication placeholders or template metadata.
9. Tell the user the epic and sub-tickets are ready. Show the epic URL and
   list all sub-ticket numbers. If Phase 5.5 selected option D, run the
   Option D fire-and-forget handoff from Phase 5.5 with the working branch
   `epic/<N>-<slug>` and the command `/skill:implement-ticket <epic-number>`
   (after the step 8 verification, so the epic coordinator never starts
   before the children are published), and report the placement path and
   branch instead of a copy-pasteable command. Otherwise provide the
   autonomous epic command:
   ```
   /skill:implement-ticket <epic-number>
   ```
   The epic number or URL is the preferred selector because it avoids an
   ambiguous title search. The `implement-ticket` epic coordinator will
   dispatch children in the validated dependency order and must not be
   replaced with separate direct `implement-ticket` invocations for this
   epic.

## Plan body templates

The plan body templates live in [templates.md](templates.md) and MUST be
followed exactly so `implement-ticket` can parse published bodies later.

- Use the **single-ticket template** for simple features.
- Use the **epic template** (with `## Epic structure` and `## Sub-ticket
  definitions`) when Phase 1.6 produced a split. The epic body uses the epic
  sections; every child issue body follows the single-ticket template so
  `implement-ticket` can parse it independently.

## Risky change detection

A change is "risky" and **MUST include a rollback plan** if ANY of these apply:

- New database schema change or migration in the migrations directory resolved
  via the ladder (profile `layout.migrations_dir`)
- Changes to auth, session, cookie, JWT, or row-level security (RLS) flows
- Changes to the deploy/CI configuration declared by the profile
  (`infra.deploy_config`, `infra.ci_workflows`) or to env var names
- Changes to any file declared in the profile's `layout.generated_files`
  (requires regeneration via its `regenerate_command`)
- Destructive operations (deleting data, dropping tables/columns, removing
  files that other code depends on)
- Changes to request-routing middleware identified by project guidance

For everything else, the rollback section can say "Not applicable".

## Rules

- Never skip the iteration step. Always show the draft and ask for feedback
  before creating the ticket.
- Never start implementing. This skill ends when the ticket(s) exist (or,
  for option D, when the fire-and-forget handoff has been dispatched and
  accepted — the handoff must never be followed by running the implement
  skill in this session).
- Never paste real env/secret values into the plan. Use env var NAMES only.
- Always cite external sources with URLs.
- Always include `file_path:line_number` references for codebase patterns.
- The slug should be kebab-case, lowercase, derived from the feature name
  (e.g. `add-<feature>-<verb>`).
- Do not create or retain local plan files. GitHub issue bodies are the sole
  persistent storage for generated plans.
- **Spec docs are mandatory deliverables.** If the feature adds or changes
  product behavior, the plan MUST include an OpenSpec delta specification under
  `openspec/changes/<name>/specs/` updating the relevant capabilities. Spec updates
  are not optional documentation cleanup — they are part of the feature.
- **Flag spec drift.** If existing code doesn't match what the spec says,
  surface it in the plan even if the feature itself doesn't fix it. Select and
  record whether the spec, code, or both will change before drafting the plan;
  never leave the resolution for the implementer or the user.
- **Spec-first numbering.** When adding new requirements, follow the
  numbering conventions in the spec overview (stable IDs, never renumber
  existing ones).
- **Context fields are optional.** The user can skip any section in the
  Context, Decision rationale, or Related context. Never block on missing
  context — proceed with what you have.
- **Agent infers, user confirms.** Don't ask the user to write what you can
  figure out from the codebase. Draft the context yourself and present it
  for confirmation.
- **Decision-complete plans are mandatory.** Before Phase 5, close every
  implementation-affecting decision in Phase 4. No final plan may contain an
  unanswered question, `TBD`, `TODO`, `unknown`, "to be decided", "user to
  decide", "choose later", or an unaccepted recommendation.
- **No Open questions section.** Do not add `## Open questions` to a generated
  plan. Use `## Implementation decisions` and `## Decision completeness` to
  record selected outcomes and certify that no unresolved decisions remain.
- **Revalidate after edits.** If plan feedback introduces a new choice,
  return to Phase 4 and close it before saving, showing, or creating the
  revised plan.
- **Always ask how to handle uncommitted OpenSpec artifacts (Phase 5.5).**
  Present options A (ticket only), B (commit to `main`), C (feature branch
  off fresh `origin/main`), and D (feature branch plus a fire-and-forget
  implementation handoff dispatched through worker-delegation, which
  immediately starts the implement skill in a new worktree placement)
  before creating any ticket, and record the choice in the plan's
  `OpenSpec Change` section. Never commit or push
  OpenSpec artifacts, and never create branches, without the user's explicit
  selection. Option C ordering: ticket (or epic) first, branch afterwards —
  the branch name embeds the ticket number (`feature/<N>-<slug>` for single
  tickets, `epic/<N>-<slug>` for epics; one shared epic branch for all
  sub-tickets). After the branch is pushed, roll back the local uncommitted
  artifacts (`git clean -fd -- openspec/changes/<change-name>`) so `main`
  isn't left with stray files; only ever clean the change directory. Fetch
  `origin` first so the branch starts from fresh `origin/main`, and never
  switch the current working tree to the new branch (other agents may be on
  `main`) — use a temporary worktree or in-memory plumbing instead. The ticket
  body must state where implementation happens.
- **Epic mode: self-contained sub-tickets.** Each sub-ticket plan must be
  self-contained and parseable by `implement-ticket` independently. The
  sub-ticket plan body must include its own Context, Implementation plan,
  Verification plan, and Rollback plan — not just a reference to the epic.
- **Epic mode: sub-ticket titles.** Sub-ticket titles must be ≤72 chars and
  follow the commit-message convention (lowercase prefix + colon +
  imperative). Reuse each exact title as the child issue title, child plan H1,
  epic definition title, graph node title, and implementation-order title.
- **Epic mode: stable identities.** Assign one immutable `S<N>` plan key to
  every sub-ticket. Keys are not GitHub issue numbers. Declare every key/title
  pair exactly once in the graph, use the keys for graph edges and ordering,
  and include the matching `Epic sub-ticket key: S<N>` line in each child plan.
- **Epic mode: dependency graph required.** The dependency graph must be
  present in the epic plan body, must declare every child including isolated
  children, and must use stable keys rather than issue-number placeholders.
  The `implement-ticket` epic coordinator validates the graph against the
  native `subIssues` set.
- **Epic mode: activation gate required.** The epic body must contain exactly
  one finalized block with this shape:
  ```text
  AUTONOMOUS_EPIC_SUBTICKET
  PARENT_EPIC=<native epic number or URL>
  SUBTICKET=<first native child number or URL in implementation order>
  ```
  The `implement-ticket` epic coordinator uses this block only to authorize
  the epic coordinator; it still injects a separate child-specific block into
  every dispatched task specification. Do not copy the epic block into child
  issue bodies.
- **Epic mode: create epic first.** Never create sub-tickets before the
  epic ticket exists — GitHub sub-issues need a parent to link to.
- **Epic mode: use `--parent`.** Use `gh issue create --parent <epic-number>`
  for linking sub-tickets to the epic. Fall back to
  `gh issue edit <epic> --add-sub-issue <sub>` only if `--parent` fails.
- **Epic mode: finalize publication.** After all native children exist,
  replace every publication issue/URL placeholder in the epic and child bodies
  with actual metadata and publish the bodies with `gh issue edit --body-file`.
  Re-fetch and verify the native child set, key/title mappings, graph, order,
  and absence of placeholders before recommending
  `/skill:implement-ticket <epic-number>`.
