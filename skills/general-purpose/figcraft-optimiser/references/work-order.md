# Work order schema

A work order is the complete contract between the planner and an executor
worker. It must be self-sufficient: the worker reads the order, the cached
command catalog, and the quirks file — and nothing else. If the planner
cannot write the order without guessing, the planner first resolves the
unknowns itself (via one targeted executor probe or the handover docs).

## Template

```markdown
# Work order: <short title>

## Context
- File: <absolute path to .figcraft> (already open / needs file.open)
- Page: <name or id> · Target: <frame ids / region>
- Relevant master ids (L / D): <from handover or component.list>
- Prior state: <what exists, what was last done, where the state file is>

## Steps
Numbered, imperative, each executable as one batch (or a few). For every
step: the exact command(s) with literal params or $step references, and the
expected outcome ("creates frame, returns id").

## Constraints
- Turn budget: <n> turns
- Output budget: <n> chars per digest
- Do NOT: <e.g. re-fetch nodes already mapped; touch frames outside ids; fix bespoke art that deviates from captures>

## Verification targets
Literal values the executor must check and report: node ids, widths,
padding, characters, export diff threshold. The executor reports
target → observed → pass/fail, nothing else.

## Measured geometry (capture-driven builds)
Literal numbers the planner pre-measured — once, scripted, from captures
(strip scans, edge detection) or from code-truth files: positions, sizes,
gaps, font sizes, colours per region. The executor builds to these numbers.
It never reads captures or runs measurement scripts — that is the planner's
one-time job, and two workers re-measuring the same captures is a measured
waste (round-3 retro).

## Digest format
Per step: ok | PARTIAL | FAIL + one line of detail. Final: ids created /
changed / deleted, dirty flag, and the verification table.
```

## Rules for planners

1. **Resolve ids before ordering.** Never write "find the header" — write
   "frame 4020, child id X". If ids are stale (they change on reopen), the
   first step of the order is a single cheap re-list, not an exploration.
2. **Front-load knowledge.** Copy the relevant quirk into the order when it
   changes how a step must be written (e.g. "x/y no-op in auto layout — use
   padding").
3. **Design for failure.** State what the worker should do when a step
   fails once, twice, and always: stop, digest, report. Never "keep
   trying".
4. **Keep batches atomic.** Each step's commands must be safe to run as one
   `batch` call; put `save_file` as its own step, not inside a mutation
   batch.
5. **Budget the digest.** Say exactly which fields to return. An
   unbounded digest defeats the whole optimisation.
6. **Measure once, order forever.** For capture-driven builds, run the
   measurement scripts yourself (or via one cheap probe) and put the
   numbers in the Measured geometry section. Never leave "measure from the
   capture" as an executor step.
7. **Name the state file.** Give the order an explicit state-file path and
   require the executor to write it before stopping — a takeover reads it
   first and surveys only what it does not cover.

## Rules for executors

1. Read `references/command-catalog.md` and `references/quirks.md` first;
   never call `list_commands` unfiltered.
2. One `execute` call per batch; project all results down before returning.
3. Track every fetched id locally; never fetch the same id twice.
4. After any failed batch, verify the affected ids (cheap, shallow) before
   retrying — partial commits are real.
5. Report in the digest format exactly; no prose trees.
6. Count your tool calls against the budget; at budget − 2, checkpoint and
   report.
7. Before stopping — budget, failure, or completion — write the state file
   the order names: variable id map, known ids, done/remaining.
8. Never read capture images into context; build to the Measured geometry
   numbers and the code-truth files the order names.
