#!/usr/bin/env bash
# Regenerate references/inventory.md: every section, component set and
# component on the `Design System` page as `name | type | section | W×H`.
# Workers grep this file for master names instead of reading the page (a
# depth-2 page read cost ~8k tokens; the page holds ~200 masters). No ids
# are written: ids change on reopen — resolve one with
# `node.find {root: <section>, name}` when you need it.
#
# Usage: scripts/dump-inventory.sh [FILE.figcraft] [path-to-figcraft-cli]
#   FILE defaults to $FIGCRAFT_FILE; the CLI to $FIGCRAFT_CLI.
# Runs headless via `figcraft-cli run --in FILE` (read-only: no --out, so the
# file is never written). Needs python3. Save in the app first if the open
# document has unsaved changes — the CLI reads the file on disk.
#
# Fallback if the CLI cannot read the file: the two-call MCP recipe
# `node.find {type: "COMPONENT", limit: 500}` (+ COMPONENT_SET, SECTION),
# then ONE batch of `get_node {id, fields: ["name"], depth: 0}` per id.
# Cost: ~200 ids → ~200 small results (≈10–15k tokens) once, versus ~8k per
# page read repeated every pass — run it once and commit the file.

set -euo pipefail

FILE="${1:-${FIGCRAFT_FILE:-}}"
CLI="${2:-${FIGCRAFT_CLI:-}}"
PAGE="${FIGCRAFT_DS_PAGE:-Design System}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/references/inventory.md"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "design file not found: '${FILE}'. Pass it as \$1 or set FIGCRAFT_FILE." >&2
  exit 1
fi
if [[ -z "$CLI" || ! -x "$CLI" ]]; then
  echo "figcraft-cli not found or not executable: '${CLI}'. Pass it as \$2 or set FIGCRAFT_CLI." >&2
  exit 1
fi

FILE="$FILE" CLI="$CLI" PAGE="$PAGE" OUT="$OUT" python3 -I - <<'PY'
import json, os, subprocess, sys, tempfile, datetime

cli, file, page, out = (os.environ[k] for k in ("CLI", "FILE", "PAGE", "OUT"))

def run(steps):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(steps, f)
    try:
        p = subprocess.run([cli, "run", "--in", file, f.name],
                           capture_output=True, text=True)
    finally:
        os.unlink(f.name)
    if p.returncode != 0:
        sys.exit("figcraft-cli run failed:\n" + (p.stdout + p.stderr)[-800:])
    return [json.loads(l)["result"] for l in p.stdout.splitlines() if l.startswith("{")]

def cmd(c, **params):
    return {"command": c, "params": params}

pages = run([cmd("page.list")])[0]
plist = pages if isinstance(pages, list) else pages.get("pages", [])
idx = next((i for i, p in enumerate(plist) if p.get("name") == page), None)
if idx is None:
    sys.exit(f"page '{page}' not found")
sel = cmd("page.select", index=idx)

r = run([sel, cmd("node.find", type="SECTION", limit=10000)])
sections = r[1]["ids"]
r = run([sel] + [cmd("node.get", id=i, fields=["name", "type", "width", "height"]) for i in sections])
secs = {}
for i, n in zip(sections, r[1:]):
    secs[i] = n["name"]

steps = [sel]
keys = []
for sid in sections:
    for t in ("COMPONENT_SET", "COMPONENT"):
        steps.append(cmd("node.find", root=sid, type=t, limit=10000))
        keys.append((sid, t))
r = run(steps)[1:]
ids = {}
for (sid, t), res in zip(keys, r):
    for i in res["ids"]:
        ids[i] = (secs[sid], t)

order = list(ids)
r = run([sel] + [cmd("node.get", id=i, fields=["name", "width", "height"]) for i in order])[1:]
lines = []
for s in sections:
    lines.append((secs[s], "SECTION", "—", ""))
for i, n in zip(order, r):
    sec, t = ids[i]
    lines.append((n["name"], t, sec, f'{n["width"]:g}×{n["height"]:g}'))
# section sizes
r = run([sel] + [cmd("node.get", id=i, fields=["width", "height"]) for i in sections])[1:]
sizes = {secs[i]: f'{n["width"]:g}×{n["height"]:g}' for i, n in zip(sections, r)}
lines = [(a, b, c, sizes[a] if b == "SECTION" else d) for a, b, c, d in lines]
lines.sort(key=lambda x: (x[2] == "—" and 0 or 1, x[2], x[1] != "COMPONENT_SET", x[0]))

with open(out, "w") as f:
    f.write("# Design System inventory (generated)\n\n")
    f.write(f"Generated: {datetime.date.today().isoformat()} · Source file: {'/'.join(file.split('/')[-2:])}\n")
    f.write("Regenerate: scripts/dump-inventory.sh (see SKILL.md). Grep this file for "
            "master names; do NOT read the Design System page. No ids — they change on "
            "reopen; resolve with `node.find {root: <section>, name}`.\n\n")
    f.write("name | type | section | width×height\n")
    for l in lines:
        f.write(" | ".join(l) + "\n")
print(f"Wrote {out} ({len(lines) + 5} lines)")
PY
