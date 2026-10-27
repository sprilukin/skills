# FigCraft MCP quirks and cost rules

Add new findings here after every pass; rediscovering
a quirk has cost whole work orders.

## Engine quirks (behaviour verified in practice)

1. **Batch failures are atomic on 0.11.2 — re-verified.** Pass-2-era
   behaviour (a guard refusal kept steps before and after the refused one)
   no longer reproduces: on 0.11.2 both hard errors ("no such node") and
   guard refusals roll the whole batch back. Note for scripted workers: a
   guard refusal throws OUT of the batch call as an exception, so prior
   steps' results are lost from the script's view even though nothing
   committed — catch it, and never re-run a batch blind after an error.
2. **Geometry overrides inside instances are partial.** Docs refuse all
   geometry of layers inside instances; on 0.11.2 padding, width/height,
   fills, visibility and characters override fine, but **both `x` and `y`
   are now refused** (pass-2 saw `x` work), nested-instance position is
   refused, and `absolute` is refused (verbatim: "A layer's position comes
   from the main component in an instance: edit the main component, or
   detach the instance"). Fix the geometry in the main component, then
   re-create the instance — do not fight it.
3. **Instances cache geometry from creation — but 0.11.2 propagates at
   least master-child width changes.** Pass-14 probe: a master child width
   change was read back through an existing instance immediately (after a
   size-override reset). Keep the suspicion for position/size tweaks made
   AFTER instance creation (pass-9 mobile strips went stale), and always
   spot-check instances after master geometry edits instead of assuming
   either direction.
4. **`node.set` x/y silently no-ops on children of an auto-layout frame**
   (success reported, value unchanged). Move content via padding /
   mainAlign / crossAlign, or make the child `absolute` in the main.
5. **Hug width + right constraint does not reflow.** For right-aligned
   dynamic-width content use a horizontal auto-layout with a fill-width
   spacer.
6. **`edit.delete` fails the whole batch on an already-deleted id**
   ("no such node"). Deleting a parent removes its subtree — list
   top-level nodes only, never their children, before a delete pass.
7. **Unbound boolean component properties do nothing.** A boolean prop
   only hides/shows layers bound with
   `component.bindProperty {field: "visible"}`.
8. **New frames default to a white fill.** Pass `fills: []` in the same
   batch for every structural frame that must be transparent.
9. **Text wrap needs the box, not just the text**: `sizingH: "fill"` on
   the parent chain, `sizingH: "fill"` + `textAutoResize: "height"` on the
   text, and set it on the instance too — instances cache sizing from
   creation time.
10. **Export per frame, never per page** — pass `ids: [frameId]` and
    `scale: 1`. Page-level export without ids came back blank.
11. **`$step` references are strict.** Only an object whose keys are
    `$step` (and optionally `field`) is a reference; a reference to the
    same or a later step, a negative or non-integer index, or any extra key
    beside `$step` fails the whole batch. A step that is itself a
    `command.batch` resolves `$step` against its own steps.
12. **Component/instance ids are session ids.** They change on reopen.
    Re-list masters with `component.list` (or grep the handover) instead of
    trusting stored ids.
13. **SVG export is deterministic and numeric.** Two exports of an
    unchanged frame are byte-identical, so `scripts/svg-diff.sh` gives a
    zero-noise change list with id-localised deltas (`x 112->118`, `fill
    #A->#B`). Pin the flags (`svgIdAttribute: true, svgOutlineText: false`)
    — different flags churn every diff. Ids come from layer names: a rename
    shows as a remove + add, and elements without their own id localise to
    the nearest id'd ancestor (`Board/text[0]`). SVG comes back as text
    (never image content), and with `path` the echo is just the file
    summary. Limits: noise/texture effects are cut out, exotic blend modes
    map to CSS (`darker` → `plus-darker`), and it verifies the resolved
    scene graph, not rasterisation — font hinting and kerning still need
    the raster gate.
13. **`scripts/qa-export-diff.sh` must run under `bash`,** not `sh`/zsh —
    it uses a bashism around line 151 and dies under POSIX sh. Workers'
    shells may default to zsh: invoke it as `bash scripts/qa-export-diff.sh …`.
14. **`component.list` can come back `$trimmed` even with `maxBytes` raised**
    (95 components is enough). Grep the response for the names you need; the
    digest keeps ids, so a trimmed list is usable — just don't expect the
    full array.
15. **Gradient fills: `{type: "radialGradient"}` with hex-string stops
    renders opaque.** Pass-9 QA: a `#6366F112 → #6366F100` stop pair under
    `type: "radialGradient"` came back as a near-solid blue wash (frame diff
    62.9%). The encoding that renders correctly (verified against a passing
    frame) is `{type: "gradient", kind: "radial", from: [0.5, 0.5],
    to: [0.5, 1], width: [1, 0.5], stops: [{color: {a, r, g, b}, position},
    …]}` — alpha as rgba objects, not `#RRGGBBAA` strings. When a gradient
    looks wrong, diff the fill encoding against a known-good node before
    touching geometry.
16. **Never duplicate a decorative fill on the root frame and a child.**
    The same pass-9 bug: the accent glow existed both as a full-bleed child
    (correct) and on the root frame's own fill (whole-frame tint, strongest
    at edges/corners). A whole-frame colour residual with no layout offset
    and edge-weighted buckets means check the root frame's own fill first.

17. **A stroked rounded frame feathers its clipped children near the corner
    arcs.** Pass 9: a kanban card master with an inside 1px stroke rendered
    its absolute `interest-strip` child with a constant ~13px soft inset at
    top and bottom (constant regardless of card height — 34/62/100-tall test
    cards all inset 13px; width/gap/padding/height/sizing/variables innocent;
    square corners and `strokesIncluded: false` innocent). The renderer gives
    a stroked rounded frame's clipped children a soft top/bottom band; a
    full-size stroked rectangle child at index 0 (ring, height = master
    height) restores the height and renders the hairline. When a stripe or
    band looks shorter than the code-derived spec, scan an exported PNG
    column for the band colour before touching geometry.
18. **A full-size replacement ring must have its fill cleared — rectangles
    default to #D9D9D9, not white.** Pass 9: the ring child created without
    `fill: "none"` tinted every board card gray at full card size (quirk 8
    says frames default to white; rectangles default to gray). Always pass
    `fill: "none"` on ring/border replacements, and verify a fix with a
    full-frame body-colour scan, not only the column the complaint was
    about. Instance rings also cache the wrong size from creation (quirk 3)
    — set width/height per instance or re-create them.
19. **After a master size change, re-size every instance explicitly.**
    Pass 9: instances cached the masters' transient 98/131 hug heights after
    a stroke removal and did not follow the masters back to 100/133 (quirk 3
    in practice). Width can also go stale per instance (four mobile cards
    cached 260 while masters/peers were 343). After any master size change,
    walk every instance, compare width/height to the code-derived truth, and
    set both the instance and its ring/border child explicitly. Don't assume
    the tree's earlier values are still current — re-measure before judging.
20. **A stroked rounded node overlapping a parent's clip arc feathers the
    sibling below it.** Pass 9: a card frame with an inside stroke (or any
    full-size stroked rounded child) rendered the sibling below it at the
    corner arcs with a constant ~13px soft inset at top and bottom,
    regardless of card height (34/62/100-tall all inset 13px). The topmost
    arc-overlapping node renders crisp; z-order decides who eats the halo.
    Verified-clean anatomy for the kanban card: card frame unstroked
    (`stroke: null`), then bottom→top: `hairline-border` absolute child
    (fills [], stroke hairline var, radius var, constraints
    leftRight/topBottom), then `interest-strip`, then content. Filled-path
    rings behave the same as stroked ones; square-corner strokes do not
    halo; `strokesIncluded: false` does not help. Do not trust a render
    across unrelated edits — re-export after every structural change and
    re-measure the band column.

21. **A bare-hex fill override on an instance drops the master's alpha.**
    Pass 9: dark badge instances overridden with `fill: "#EF4444"` lost the
    master's 15% opacity and rendered as solid bright pills on dark cards.
    When a master paint carries opacity, overrides must pass the full paint
    object (`{type: "solid", color, opacity}`), not a bare hex string.

22. **Commands without `ids` are refused unless the catalog documents a
    selection default.** Pass 10: one executor concluded `node.set`
    "requires interactive selection" and burned its budget — it had simply
    omitted `ids`. Pass-14 re-check on 0.11: `node.get` / `node.set`
    without `ids` still refuse. The catalog is explicit per command: where
    it says `ids? (default selection, …)` omission is fine; everywhere
    else pass `ids: [...]`. There is no worker-visible selection context
    worth relying on either way.

23. **Spawn-time model outages cost zero document mutations.** Pass 10:
    `glm-5.3-flash` was intermittently unavailable at spawn (3 workers died
    the same second they were created, dirty=false each time). Spawn-time
    errors never need a takeover survey — re-spawn directly on the fallback
    ladder. Also: `inkling-small:free` has no thinking variants (spawn with
    no `thinkingOptionId`); `glm-5.3-flash` uses `low`/`high`/`max`.

24. **Editing a master child in place preserves instance overrides;
    deleting/recreating it drops them.** Pass 14: resizing + re-binding the
    masters' `interest-strip` child kept every per-instance fill override
    (28 across the board frames) because the node id never changed. A
    delete + re-create would have silently stripped them all. Prefer
    in-place mutation of master children over structural replacement when
    instances carry overrides on that child.

25. **`node.create` ignores a top-level `fill` shorthand.** Pass-14 probe:
    `node.create {type: "rectangle", fill: "#FF0000"}` is silently dropped
    and the node gets the engine default (#D9D9D9). Paints must go through
    `props: {fill: ...}` (or a follow-up `fill.set`).

## Suspected (verify before relying)

- **A literal fill overwrite may strip a variable binding.** In one
  interactive pass (round-3 retro), "closure reason colours are broken"
  appeared after fill edits on variable-bound nodes. Hypothesis: setting a
  literal hex fill on a node bound to a Theme variable replaces the
  binding with the literal. Verify with one test (bind a node, set a
  literal fill, re-read the binding); if confirmed, move this up to the
  engine quirks. Until then: on variable-bound nodes, edit through the
  variable, not the node fill.

## Cost rules (where tokens actually went)

- **Turn count × context is the dominant cost, not output size.** One QA
  worker burned 137M cache-read tokens over 452 turns to make 16 MCP calls.
  Cap workers at ~40 turns, and split work by frame row / ≤6 frames per
  worker rather than by page.
- **Mutation echoes are digested server-side (Oct 2026 build).**
  `run_command` / `batch` / `create_node` / `set_properties` results are
  capped at 4 KiB by default with a `$trimmed` marker; `id` is always
  kept (call `get_node {id}` for dropped detail), `full: true` or
  `maxBytes: n` (min 1024) opt out, and errors are never digested. Blanket
  projection is no longer needed for size — only for relevance.
- **`get_node` / `inspect_document` still default to an 8 MiB budget** —
  the digest does not cover tree tools. Fetch with the minimum `depth`
  that answers the question (a page listing needs `depth: 1`), and never
  fetch the same node id twice.
- **`list_commands` without a filter dumps ≈1200 commands (≈50k chars).**
  Use the cached catalog (`references/command-catalog.md`), or
  `list_commands {filter: "keyword"}`.
- **No read caching exists across turns.** The same node id was fetched 40
  times across two sessions. Keep a per-worker id map in the state file and
  check it before every fetch.
- **QA belongs in scripts.** `export` + ImageMagick/PIL diff against
  captures finds exact geometry (hairlines, row pitch) in seconds. A
  text-free x-strip scan locates hairline colour rows precisely; account
  for the 50% scrim (hairline under scrim ≈ `#717374`). Escalate code →
  tree read → scripted diff → one measured crop; every past "ambiguous"
  pixel hunt ended in a numeric answer anyway.
- **Captures age; code does not.** Captures are renders of a past code
  state. When a capture and the current code disagree, re-export the app
  before trusting the capture — in implementation QA the stale capture is
  a suspect, not a verdict.
- **The planner can be the cost centre.** After the worker fixes (Oct 2026
  round 2), one planner session held 90% of a run's cost: 466 turns × 221M
  cache-read tokens. 330 of those turns were hands-on visual QA that burned
  176M at ~534k context each, with no compaction. The workers together cost
  ~$1; the planner alone $8.60.
- **Images are permanent context.** 56 image reads (2.6 MB) into one session
  never left it and were replayed by every later turn. Crops, zooms, and
  re-reads of the same file count too. Pixel verdicts come from script
  output, not from the model's eyes.
- **Spawn storms are real.** One session made 31 `create_agent` calls, 19
  errored, and re-spawned one probe pair 9 times after a spawn had already
  returned an agent id. Read the spawn result before the next action; never
  re-spawn a running title; check `paseo_list_agents` on error; cap retries
  at 3.
- **Model fallback hierarchy.** Planning/verification: strong model.
  Batch execution and QA: cheap model. Never let a strong model babysit a
  batch.
- **`batch` tool input shape is `{commands: [...]}`** (not a bare array,
  not `steps`); `run_command` takes `{command, params}`. Found in pass 13.
- **`$step` index syntax — fixed upstream in 0.11.** `field` now takes a
  slash path (`{ $step: 1, field: "ids/0" }`), and steps can be named with
  `as` and referenced with `{"$ref": "name"}` anywhere in later params
  (mixable with `$step`; `field` also reaches keys like `"name"`). The
  old two-call workaround is gone — build nested trees in one batch (0.11
  docs, "Step references").
- **`node.set x/y` on a vector re-normalizes its path data** to a 0-based
  bbox. `vector.create` keeps raw coordinates as offsets from the node
  origin. Recipe for X-style icons: path `M0 0L12 12M12 0L0 12` at node
  (2,2) inside the 16×16 box (pass 13).
- **`export` fails if the target directory does not exist** — mkdir -p
  the path first (pass 13).
- **The dock toolbar is `#111827` (VariableID:29) on light frames too** —
  the dark dock is by design in both themes; a light dock would be a
  variable-value change, not frame work (pass 13 confirmation).
- **SVG exports serialize every shape as `<path>`, not `<rect>`/`<circle>`**
  — element searches by tag name (e.g. "find the circle") silently miss
  them; match by `fill`/`transform` values instead. Cost a QA pass a false
  "element absent" verdict in pass 13 (the 6×6 accent dot was there, as a
  6px circle path at `matrix(1 0 0 1 158 771.5)`).
