# FigCraft server wishlist

Asks for the FigCraft maintainers — not agent rules. Collected from the
Documents-screens retro (Oct 2026); each would remove a workaround in
`quirks.md`.

1. Address instance children by layer-name path (`node.set {root, path}`)
   instead of id-offset arithmetic (quirk 37).
2. `edit.duplicate` returns only the top-level id by default, with an
   opt-in map depth (quirk 36).
3. A compact `get_node` mode that drops default layout keys, or accepts
   dotted `fields` (quirk 34).
4. A nested-tree create command with `children`.
5. A "clone as Dark twin" macro (quirk 40 is five steps).
6. `batch {validate: true}` dry run — a failure at step 8 of 21 costs a
   full resend (quirk 38).
7. Accept `$ref` in `component.create` / `component.detach` ids, and a
   top-level `visible` in `node.create` (quirks 38–39).
