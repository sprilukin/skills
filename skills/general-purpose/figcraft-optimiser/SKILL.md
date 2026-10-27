---
name: figcraft-optimiser
description: >
  Cost-aware workflows for the figcraft-app MCP: planner/executor split,
  batching, cached reads, cheap QA. Use when an agent needs to read, build or
  modify FigCraft designs via MCP, or when spawning workers that will.
metadata:
  opencode/autoinvoke: true
---

# figcraft-optimiser

Goal: spend the least possible tokens and turns on figcraft-app MCP work.
Measured baseline (Oct 2026 analysis, 7 days): 80% of agent spend was on
FigCraft sessions; the dominant costs were long turn chains replaying context
(452 turns × 137M cache-read tokens on one QA worker), verbose tool output
(20–50k chars per `get_node` / `run_command` echo), 93 bare `list_commands`
calls (≈1.2M duplicate tokens), and no read caching across turns.

Round-2 retro (Oct 2026): the worker fixes worked — worker sets dropped from
≈$16 / 436M cache-read tokens to ≈$1 / 26M. The cost moved to the planner:
one orchestrator session held 90% of a run's cost (466 turns × 221M
cache-read tokens) by doing visual QA itself and re-spawning workers in a
loop. The planner rules below exist because of that.

## Server-side digesting (merged upstream as M0.9, Oct 2026)

Result digesting first shipped in the side build `sergii/mcp-optimisations`
(commit `98ecb072`) and is now merged upstream (M0.9, commit `50ed6368`,
verified live on CLI/app 0.11.2). Reference: `docs/mcp.md` → "Digesting
command results". It digests `run_command`, `batch`, `create_node` and
`set_properties` echoes to a 4 KiB budget by default. Most results are
unchanged; large ones come back squeezed with a `$trimmed` marker. What
this changes for this skill:

- Blanket result projection is no longer a *size* rule — the server
  handles size. Projection is now about relevance only (rule 3).
- `$trimmed` is a signpost, not a failure. `id` is always kept; when the
  dropped fields matter, call `get_node {id}`. Opt out per call with
  `full: true` or `maxBytes: n` (min 1024) on `run_command`/`batch`.
- Errors, strings and numbers are never digested.
- Tree tools (`inspect_document` / `get_node`) are untouched (8 MiB
  default) — minimum-`depth` reads still matter (rule 4).
- Bare `list_commands` is still uncapped upstream — rule 1 stands.

## 0.11 capabilities worth using (verified live Oct 2026, CLI 0.11.2)

Diffed against the 0.10 catalog; full list in the regenerated
`references/command-catalog.md`.

- **`variable.export {format: "tailwind"}`** — a Tailwind v4 `@theme`
  stylesheet from the variable collections (plus `dart`). Direct route for
  token-parity checks between the design file and a Tailwind codebase:
  export, diff against the code's theme block, no pixel QA needed for
  colour drift. Dark modes land as `[data-theme="<Mode>"]` — map the
  selector to the codebase's dark convention (`.dark` in this repo) when
  diffing.
- **`inspect.code {language: "tailwind", mobile?}`** (also `vue`, `arkui`)
  — React + Tailwind v4 utilities for a page/frame, bound variables as
  theme utilities, instances inlined with overrides. Cheap code-parity
  reads without screenshots.
- **Batch step references**: `as` + `{"$ref": "name"}` and `field:
  "ids/0"` slash paths — nested trees in one call (see quirks).
- **`file.export {svgIdAttribute}`** is now a documented parameter (the
  QA flags this skill pins were undocumented before; behaviour
  unchanged). Export formats gained `xml` (Android Vector Drawable, with
  `vdCompat?`), and `file.exportAssets` gained `zip?`.
- **`file.save {overwrite?}`** refuses to clobber changes another app
  wrote since open/save — good guard for parallel workers; `file.saveAs
  {data: true}` + **`file.markSaved`** round-trips a file without leaving
  phantom unsaved state (useful in headless CLI QA flows).
- **`image.create {target?}`** adds an image on top of an existing
  layer's fills instead of making a new layer.
- **FigBoard-only (not used by design-file passes):** `board.table*`,
  `board.template*`, `board.timer*`, `board.vote*`, `board.reattach`,
  connector `curved` style, `widget.setText` / `widget.menu`.
- **`.sketch` import** (48+, best effort) via `file.open` / `file.import`.

## Roles

- **Planner (smart model).** Never touches figcraft-app directly. Owns specs,
  master ids, and the frame map. Emits work orders (see
  `references/work-order.md`), verifies returned digests, and keeps the
  session state file updated.
- **Executor (cheap model).** Spawns per work order, interacts with
  figcraft-app only inside `execute` code, returns a compact digest. Use the
  prompt skeleton in `templates/executor-prompt.md`.
- **QA (cheap model).** Separate worker; exports frames and diffs them
  against captures with scripts, not with the model's eyes. Use
  `templates/qa-prompt.md`.

Hard rule: the planner's context must never contain a raw node tree, a
command catalog, a full export, or an image. Digests and script verdicts only.

## Planner rules (round-2 retro, Oct 2026)

The planner runs the most expensive context in the run. These rules bind it
in addition to the core rules:

1. **No images in the planner context.** Never `read` a `.png`/`.jpg` crop,
   however small. Pixel verification is the QA worker's scripted diff
   verdict table, or the plain-text output of `scripts/qa-export-diff.sh`.
   Measured: 56 image reads (2.6 MB) drove 176M cache-read tokens over 330
   turns at ~534k context each — 80% of the whole run.
2. **Turn budget: ≤60 turns.** Then checkpoint the state to the session
   state file and report or hand off. Do not count on compaction: one
   466-turn session grew to ~800k tokens of context, never compacted, and
   replayed all of it every turn.
3. **Spawn discipline.** Read every `create_agent` result before the next
   action. An agent id in the result means the spawn succeeded — never
   re-spawn the same title. On an error, check `paseo_list_agents` before
   retrying; retry at most 3 times, then stop and report. Run one probe
   round per verification need and record the results in the state file, so
   later phases do not re-probe.
4. **Stay out of the MCP.** If the planner must fetch (rare), `get_node`
   needs an explicit minimum `depth`, and the result goes into the state
   file — never into repeated turns.
5. **Take over at budget.** When a worker reaches its turn budget or
   reports a stall, spawn a takeover (see `templates/executor-prompt.md`)
   pointing at the state file — do not let the worker drift. Measure once
   for the whole order: run the capture-measurement scripts yourself and
   put the numbers in the work order, so executors build to numbers
   instead of re-running PIL loops (round-3 retro: two executors
   re-measured the same captures independently).
6. **Spawn from the file, not from memory.** Re-read
   `templates/executor-prompt.md`, `templates/qa-prompt.md`, and
   `references/work-order.md` from disk each time you compose a spawn
   prompt. A running orchestrator that spawns from its loaded context
   ships workers the rules of an older skill version (measured: one
   campaign's post-update spawns carried none of the new hard rules).

## Source-of-truth hierarchy

Code is truth for values; scripted measurement is truth for rendered
geometry; image evidence is the last resort. Escalate one level only when
the level below cannot answer the question:

1. **Code + FigCraft variables.** Colors, radii, fonts, spacing, text
   content, component anatomy. `globals.css` and the bound Theme
   collection (`design/notes/variables.md`) share the same values, so
   color drift between code and design is structurally impossible — never
   verify a token with pixels.
2. **Tree reads.** `get_node` at minimum `depth`, compared against the
   code-derived spec: structure and geometry as designed.
3. **SVG structural diff.** `export {format: "svg", svgIdAttribute: true,
   svgOutlineText: false}` returns the resolved scene graph as text:
   post-layout absolute geometry, real `<text>` elements, ids from layer
   names. `scripts/svg-diff.sh OLD NEW` diffs two exports into an exact,
   zero-noise change list (`id: x 112->118`, `fill #A->#B`). Use it after
   edits for regression checks and to localise drift. Always pass the same
   flags, and keep one export per frame per pass so the diff stays clean.
4. **Scripted export diff (raster).** `export` at scale 1 plus
   `scripts/qa-export-diff.sh` against captures: pass/fail, which regions
   drifted, and by how many pixels. The output is numbers and verdict
   tables — no image enters context. This stays the final acceptance gate
   against app captures: an SVG diff cannot compare against a Chromium
   render, and rasterisation (font hinting, kerning) only shows in pixels.
5. **Fallback: one measured crop.** Only on a FAIL the scripts cannot
   localise, the QA worker may read one crop of the diff region, and it
   must try a strip-scan measurement (see quirks) before visual judgment.
   Never in the planner context (planner rule 1).

Comparison direction decides which side ages:

- **Design-extraction QA** (does the frame match what was extracted): the
  capture was the one-time ground truth. After extraction, code is the
  truth going forward.
- **Implementation QA** (does the app match the design): current code plus
  a fresh export is the truth. A stale capture that disagrees is a
  suspect, not a verdict — re-export before trusting it.

## Interactive sessions (user-driven)

When the user drives FigCraft work live — no work order, no workers — these
guardrails still apply. An interactive session runs the most expensive
context in the run and has no QA worker behind it:

1. **Baseline before bulk edits.** Before any edit that touches more than
   one node (a master, a loop over instances, a batch): `save_file`, and
   export an SVG baseline of every affected frame (same flags as rule 7).
   This defines both the rollback point and the diff target.
2. **Verify before you claim done.** After bulk edits, run one scripted
   check (`qa-export-diff.sh` on the affected frames) and report the
   verdict with your change. The user must never be the QA worker
   (measured: one interactive session produced three breakages that the
   user found manually — "you broken all the kanban cards").
3. **Fix the master, not the instances.** A defect shared by many
   instances is a master fix. Per-instance edits drift — one interactive
   pass left some cards shorter than others.
4. **Watch the turn chain.** An interactive session has no turn budget and
   compaction may never trigger; 200+ turns over a growing context is the
   round-2 planner failure mode again. If the session is long and the
   remaining work is well-defined, propose spinning it into a work order
   for a cheap executor.

## Core rules (all roles)

1. **Cache before calling.** Read `references/command-catalog.md` with grep
   instead of `list_commands`. Only re-list live with a `filter` when
   `run_command` fails with unknown command.
2. **Batch by default.** One `execute` call = one batch attempt. Compose
   multi-step trees with step references — never guess ids across turns.
   Name a step with `as` and use `{"$ref": "name"}` (or `{"$step": n}` with
   `field: "ids/0"` for list items) in later steps; see quirks #11 and the
   0.11 note. The batch shape is `{commands: [{command, params}], label}` —
   the key is `params`, not `args`.
3. **Project for relevance, not size.** The server digests big
   `run_command` / `batch` / `create_node` / `set_properties` echoes to
   4 KiB by default (`$trimmed` names what went; `full: true` or
   `maxBytes: n` opt out per call). Inside `execute`, still return only
   the fields the work order asks for — but don't project to survive
   floods that no longer happen.
4. **Read once, remember.** Store node id maps and geometry in the session
   state file (handover or `design/notes/*.md`). Never fetch the same node
   id twice in one worker. Fetch with the minimum `depth` that answers the
   question (a page listing needs `depth: 1`, not the default 4).
5. **Turn budget — count it, don't estimate it.** Executors: ≤40 tool
   calls. Planners: ≤60 turns (Planner rules). At budget − 2, checkpoint
   (`save_file` + state file) and report — the orchestrator spawns a
   takeover at budget. A worker that drifts past its budget costs more
   than a fresh one (measured: one executor ran to 57 and its takeover to
   95+ calls). After 2 failed attempts on one step, stop, record the
   state, and report — do not retry-storm.
6. **Verify renders, not JSON — but code first.** Escalate through the
   source-of-truth hierarchy (code → tree reads → SVG structural diff →
   scripted export diff → one measured crop). JSON eyeballing misses
   5–10px drifts; so does image eyeballing. Headless QA can bypass MCP
   entirely: `figcraft-cli export` after `save_file` (see
   `scripts/qa-export-diff.sh`).
7. **Save and checkpoint.** `save_file` after each completed frame or
   master, then export its SVG baseline — `export {ids: [frameId],
   format: "svg", svgIdAttribute: true, svgOutlineText: false, path:
   <per-pass dir>/<frame>.svg}` — so the next pass can regression-diff it
   with `scripts/svg-diff.sh`. A frame without a baseline export is
   unverifiable by diff later. Report the dirty flag in every digest. Undo
   state is the rollback plan — prefer undo over compensating edits.

## Quirks

Engine quirks and known failure modes live in `references/quirks.md` — read
it before writing any batch. Highlights: batches are atomic on 0.11.2 but a
guard refusal throws out of the call (catch it); geometry overrides inside
instances are partial (position is refused, size/fills work); `node.set` x/y
silently no-ops on auto-layout children; master geometry changes may not
reach existing instances — spot-check after master edits.

## Files

| File | Purpose |
| --- | --- |
| `references/command-catalog.md` | Cached full command catalog (grep this, not list_commands) |
| `references/quirks.md` | Engine quirks, failure modes, cost rules |
| `references/work-order.md` | Work-order schema: steps, budgets, verification targets |
| `templates/executor-prompt.md` | Spawn prompt for cheap executor workers |
| `templates/qa-prompt.md` | Spawn prompt for cheap QA workers |
| `scripts/dump-commands.sh` | Regenerate the cached catalog |
| `scripts/qa-export-diff.sh` | Diff exports against captures (batch table; `--artifacts [DIR]` adds odiff overlays + side-by-side strips for FAILing frames) |
| `scripts/svg-diff.sh` | Structural diff of two SVG exports: exact, id-localised numeric change list (regression checks after edits) |

## Refresh policy

Re-run `scripts/dump-commands.sh` after a FigCraft build update, or when a
command id fails against the live app. Update `references/quirks.md` after
any pass retro that finds a new behaviour — quirks are the highest-value
cache: rediscovering one cost whole work orders.
