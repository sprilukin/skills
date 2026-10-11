# Plan body templates (plan-feature)

This file holds the two GitHub issue body templates that `plan-feature`
produces. `SKILL.md` owns the workflow; this file owns the exact body
structure. `implement-ticket` parses published bodies that follow these
templates.

- Use the **single-ticket template** for simple features.
- Use the **epic template** when the complexity assessment produced a split.
  The epic body uses the epic sections; every child issue body follows the
  single-ticket template so `implement-ticket` can parse it
  independently.

---

## Single-ticket template

```markdown
# <Exact issue title>

## Context

### Problem

<What's broken, missing, or painful? What triggered this? (user request, bug
report, business requirement, tech debt, observed friction). 2-3 sentences.
Omitted if the user skipped this.>

### Current state (Before)

<What exists today and its limitations. "Nothing exists" if this is
greenfield. 1-3 sentences. Omitted if the user skipped this.>

### Proposed change (After)

<What will exist after, in plain language — not implementation details.
1-3 sentences. Omitted if the user skipped this.>

## Decision rationale

<Why this approach was chosen. What alternatives were considered and rejected.
Any constraints that shaped the decision (platform, existing patterns, time,
dependencies). 3-6 sentences. Omitted if the user skipped this.>

## Implementation decisions

List every implementation-affecting decision that an autonomous implementer
must follow. For each item, state the selected approach and its basis. Include
scope boundaries, defaults, spec-drift resolutions, and rejected alternatives
where they matter. Do not include unanswered questions or unselected options.

## Related context

- Related issues: #X, #Y
- PRs: #Z
- Discussion: <link or description>
- User feedback: <link or description>

(Omit this entire section if nothing to link.)

## Best practices researched

<Summary of patterns found in the codebase and/or official documentation.
Include `file_path:line_number` references for local patterns and URLs for
external sources.>

## Dependencies / impact

- **Source files:** <paths>
- **Tests:** <paths or "none">
- **Spec docs:** <paths — see "Spec changes" below>
- **Docs:** <paths or "none">
- **Infrastructure:** <IaC files, env var NAMES only, or "none">
- **Database:** <schema/migration changes or "none">

## OpenSpec Change

- **Change name:** `<change-name>`
- **Artifacts:** `openspec/changes/<change-name>/` (`proposal.md`, `specs/`, `design.md`, `tasks.md`)
- **Working branch:** <branch all implementation happens on — `main` for
  Phase 5.5 options A/B, `feature/<N>-<slug>` for option C (where `N` is
  this issue's number, filled in after ticket creation); for option C state
  explicitly that work must happen on this branch and must not be merged to
  `main` mid-implementation. For option A note the artifacts are local-only
  and the implementer commits them with the implementation.>

## Spec changes

> Canonical capability specs in `openspec/specs/` are the single source of truth
> for what the app does. Every feature that adds or changes product behavior
> MUST update these specs via OpenSpec delta specifications.

List each planned spec change below. If the feature introduces no new or
changed product behavior, write "None — no behavioral change."

### New requirements

For each new capability requirement:

- **Capability & Requirement:** e.g. `<capability>` -> `<requirement>`
- **Spec path:** `openspec/specs/<capability>/spec.md`
- **Scenario:**
  - **WHEN** <triggering user action or state>
  - **THEN** <observable outcome>

### Modified requirements

For each existing requirement that changes:

- **Capability:** e.g. `<capability>`
- **Spec path:** `openspec/specs/<capability>/spec.md`
- **Change:** <what changes — updated scenarios, new scenario, etc.>

### Spec drift corrections

List any mismatch found between the current code and the spec (from the
Phase 2 conformance report). For each:

- **Capability:** e.g. `<capability>`
- **Mismatch:** <what the spec says vs. what the code does>
- **Resolution:** <selected outcome: update spec | update code | both>

## Implementation plan

Ordered steps. Each step specifies which subagent role to dispatch.

### Step 1 — <name>

- **Subagent:** `implementer` | `explore` | `reviewer`
- **Task:** <one paragraph describing what to do>
- **Files affected:** <paths>
- **Delegation instructions:** <exact prompt to send to the subagent,
  including constraints from "Best practices researched" above>

### Step 2 — <name>

...

## Verification plan

Before finalizing this section, research any new framework, library,
platform, analyzer, or test tool introduced by the feature. Use applicable
in-repo guidance first, then official documentation for the exact versions in
the manifest; record relevant commands, limitations, and manual checks here
and cite external URLs in **Best practices researched**. Do not add a tool
merely because it is popular: use the repository's existing static-quality
policy and the profile's `test_layers` unless the feature requires a new
capability.

- **Lint:** `<lint command — profile `commands.lint`, else manifest, or "n/a">`
- **Typecheck:** `<typecheck command — profile `commands.typecheck`, else manifest, or "n/a">`
- **Format:** `<format check command — profile `commands.format`, else manifest, or "n/a">`
- **Static analysis:** `<static-quality command(s) from the profile, manifest, or project policy, or "n/a">`
- **Tests:** `<test command — profile `commands.test`/`commands.e2e`, else manifest, or "no test changes">`
- **Manual verification:** <steps to verify locally, or "n/a">

## Rollback plan

<If risky (see "Risky change detection" in SKILL.md): explicit rollback steps.
Otherwise: "Not applicable — change is reversible via `git revert` and touches
no DB/infra/auth/generated code.">

## Decision completeness

All implementation-affecting decisions were resolved before this plan was
drafted. No unresolved questions, pending choices, or user-directed decisions
remain.
```

---

## Epic template

The epic body uses the sections below. Each child issue body follows the
single-ticket template so `implement-ticket` can parse it independently.

````markdown
# <Exact epic issue title, including the `Epic:` prefix>

## Autonomous execution gate

```text
AUTONOMOUS_EPIC_SUBTICKET
PARENT_EPIC=_(filled in after ticket creation)_
SUBTICKET=_(filled in after child issue creation; first child in implementation order)_
```

## Context

### Problem

<Same as single-ticket template.>

### Current state (Before)

<Same as single-ticket template.>

### Proposed change (After)

<Same as single-ticket template.>

## Decision rationale

<Same as single-ticket template.>

## Implementation decisions

List every implementation-affecting decision for the epic and each sub-ticket.
For each item, state the selected approach and its basis. Include scope
boundaries, defaults, spec-drift resolutions, dependency decisions, and
rejected alternatives where they matter. Do not include unanswered questions
or unselected options.

## Related context

<Same as single-ticket template.>

## Epic structure

### Sub-tickets

- [ ] `S1` — <exact title> — <one-sentence scope>
- [ ] `S2` — <exact title> — <one-sentence scope>
- [ ] `S3` — <exact title> — <one-sentence scope>
- ...

### Dependency graph

```
Nodes:
- `S1` — <exact sub-ticket title>
- `S2` — <exact sub-ticket title>
- `S3` — <exact sub-ticket title>

Edges (blocker -> dependent):
- `S1` -> `S2`
- `S1` -> `S3`
```

Declare every node exactly once, including nodes with no edges. Write
`- none` under Edges when all sub-tickets are independent. Stable keys are
plan identities, not GitHub issue numbers.

### Implementation order

1. `S1` — <exact title> (no blockers)
2. `S2` — <exact title> (depends on S1)
3. `S3` — <exact title> (depends on S1)
4. ...

## Best practices researched

<Patterns found, grouped by sub-ticket where applicable. Include
`file_path:line_number` references.>

## Dependencies / impact

### Sub-ticket S1: <exact title>

- **Source files:** <paths>
- **Tests:** <paths or "none">
- **Spec docs:** <paths>
- **Docs:** <paths or "none">
- **Infrastructure:** <IaC files, env var NAMES only, or "none">
- **Database:** <schema/migration changes or "none">

### Sub-ticket S2: <exact title>

...

## OpenSpec Change

- **Change name:** `<change-name>`
- **Artifacts:** `openspec/changes/<change-name>/` (`proposal.md`, `specs/`, `design.md`, `tasks.md`)
- **Working branch:** <branch all implementation happens on — `main` for
  Phase 5.5 options A/B, `epic/<N>-<slug>` for option C (where `N` is
  the epic issue's number, filled in after epic creation); for option C state
  explicitly that ALL sub-tickets are implemented on this shared epic branch.
  Repeat this line in every sub-ticket body so each child is self-contained.>

## Spec changes

> Canonical capability specs in `openspec/specs/` are the single source of truth
> for what the app does. Every feature that adds or changes product behavior
> MUST update these specs via OpenSpec delta specifications.

List spec changes across all sub-tickets. Group by sub-ticket if multiple
sub-tickets touch different spec files.

### New requirements

<Same format as single-ticket template.>

### Modified requirements

<Same format as single-ticket template.>

### Spec drift corrections

<Same format as single-ticket template.>

## Sub-ticket definitions

Each sub-ticket below becomes a separate GitHub issue linked to the epic via
`--parent`. The plan body for each sub-ticket must be self-contained so
`implement-ticket` can parse it without reading the epic. Use the stable
key and exact title in every definition heading. The child issue body must use
the single-ticket template with the exact title as its H1. Add the stable key
immediately below the H1:

```markdown
> Epic sub-ticket key: S1
```

Replace `S1` with that definition's key. The stable key is retained in the
published child body; the GitHub issue and native parent relationship provide
the publication identity.

### Sub-ticket S1: <exact title>

#### Context

<Problem, Before, After — can be brief (1-2 sentences each), referencing
the epic context above.>

#### Implementation decisions

List the selected implementation-affecting decisions for this sub-ticket.
Include the basis for each decision and do not include unanswered questions or
unselected alternatives.

#### Implementation plan

##### Step 1 — <name>

- **Subagent:** `implementer` | `explore` | `reviewer`
- **Task:** <one paragraph>
- **Files affected:** <paths>
- **Delegation instructions:** <exact prompt>

##### Step 2 — <name>

...

#### Verification plan

Before finalizing this section, research any new framework, library,
platform, analyzer, or test tool introduced by the feature. Use applicable
in-repo guidance first, then official documentation for the exact versions in
the manifest; record relevant commands, limitations, and manual checks here
and cite external URLs in **Best practices researched**. Do not add a tool
merely because it is popular: use the repository's existing static-quality
policy and the profile's `test_layers` unless the feature requires a new
capability.

- **Lint:** `<command or "n/a">`
- **Typecheck:** `<command or "n/a">`
- **Format:** `<command or "n/a">`
- **Static analysis:** `<static-quality command(s) from the manifest/policy, or "n/a">`
- **Tests:** `<command or "no test changes">`
- **Manual verification:** <steps or "n/a">

#### Rollback plan

<If risky: explicit rollback steps. Otherwise: "Not applicable.">

#### Decision completeness

All implementation-affecting decisions for this sub-ticket were resolved
before this plan was drafted. No unresolved questions, pending choices, or
user-directed decisions remain.

---

### Sub-ticket S2: <exact title>

...

## Verification plan (epic-level)

Before finalizing this section, research any new framework, library,
platform, analyzer, or test tool introduced by the feature. Use applicable
in-repo guidance first, then official documentation for the exact versions in
the manifest; record relevant commands, limitations, and manual checks here
and cite external URLs in **Best practices researched**. Do not add a tool
merely because it is popular: use the repository's existing static-quality
policy and the profile's `test_layers` unless the feature requires a new
capability.

<Overall verification strategy that spans all sub-tickets. Typically:
verify each sub-ticket individually, then do a final integration check.>

- **Lint:** `<command>`
- **Typecheck:** `<command>`
- **Format:** `<command>`
- **Static analysis:** `<static-quality command(s) from the manifest/policy>`
- **Tests:** `<command>`
- **Manual verification:** <end-to-end steps covering the full feature>

## Rollback plan

<If any sub-ticket is risky (see "Risky change detection" in SKILL.md):
describe the rollback for that sub-ticket. Otherwise:
"Not applicable — all changes are reversible via `git revert`.">

## Decision completeness

All implementation-affecting decisions across the epic were resolved before
this plan was drafted. No unresolved questions, pending choices, or
user-directed decisions remain.
````

---

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
