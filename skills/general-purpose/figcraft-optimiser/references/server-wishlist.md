# FigCraft server wishlist

Asks for the FigCraft maintainers — not agent rules. Collected from the
Documents-screens retro (Oct 2026). Re-checked Nov 1 2026 against the
checkout at 0.13.1 + 17 commits (headless CLI): items 1–6 shipped.

## Shipped (use them; see quirks 34–40)

1. `node.resolve {root, path}` — instance children by layer-name path.
2. `edit.duplicate` maps roots by default; `mapDepth` / `mapNames` opt in.
3. `node.get` dotted `fields`, `layout: false` (and `compact`).
4. `node.createTree` — nested create with `children`.
5. `variable.cloneWithMode` — Dark-twin macro (returns a detached frame).
6. `batch {dryRun: true}`.
7. `$ref` in `component.create` ids; top-level `visible` on `node.create`.

## Still open

- `variable.cloneWithMode` could finish the job: an option to re-create
  the component (`component: true`) and set name/x/y.
- `get_node` (MCP tool) schema does not list dotted `fields` or `layout`.
- `node.createTree` returns `refs: {}` unless children carry `as` —
  document it, or return child ids by name.
- Confirm what `node.get {compact: true}` drops (no effect seen on a
  fresh frame).
