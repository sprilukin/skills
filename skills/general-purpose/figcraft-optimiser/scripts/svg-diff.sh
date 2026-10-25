#!/usr/bin/env bash
# Structural diff of FigCraft SVG exports (resolved scene graph, zero noise).
#
# Usage: scripts/svg-diff.sh OLD NEW            # two files or two dirs of .svg
#   OLD  previous export (file, or dir of .svg files)
#   NEW  current export  (file, or dir of .svg files; dir pairs match by stem)
#
# Exports must use the same flags every time (the id/geometry mapping depends
# on them): file.export {format: "svg", svgIdAttribute: true, svgOutlineText: false}.
#
# Output: one line per frame `frame<TAB>added<TAB>removed<TAB>changed<TAB>verdict`,
# followed by detail lines `  id: attr old -> new` for changed elements (bounded
# per frame), and a final SUMMARY line. Verdict is IDENTICAL or CHANGED — a
# change is not a failure; the caller judges the change list against the work
# order's expected edits. Exits 0 unless files are missing or unparseable.
#
# Python 3 stdlib only (xml.etree), no ImageMagick needed.

set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: svg-diff.sh OLD NEW" >&2; exit 2; }
OLD="$1"
NEW="$2"

[[ -e "$OLD" && -e "$NEW" ]] || { echo "svg-diff.sh: $OLD or $NEW missing" >&2; exit 2; }

DETAIL_LIMIT=12

run_python() {
python3 - "$OLD" "$NEW" "$DETAIL_LIMIT" <<'PY'
import sys, os, glob
import xml.etree.ElementTree as ET

old_path, new_path, detail_limit = sys.argv[1], sys.argv[2], int(sys.argv[3])

def collect(p):
    if os.path.isfile(p):
        return [("", p)]
    return sorted((os.path.basename(f)[:-4], f) for f in glob.glob(os.path.join(p, "*.svg")))

def strip_ns(tag):
    return tag.split("}", 1)[-1] if "}" in tag else tag

# Attributes worth reporting. `d` is only counted (path data is unreadable in bulk).
TRACKED = {"transform", "fill", "stroke", "opacity", "font-family", "font-size",
           "font-weight", "letter-spacing", "clip-path"}

def flatten(path):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return None
    out = {}

    def key_for(elem, parent_key, idx):
        eid = elem.get("id")
        if eid:
            return eid
        return f"{parent_key}/{strip_ns(elem.tag)}[{idx}]"

    def walk(elem, parent_key, idx):
        key = key_for(elem, parent_key, idx)
        attrs = {k: v for k, v in elem.items() if k in TRACKED}
        text = "".join(elem.itertext()).strip()
        out[key] = {"tag": strip_ns(elem.tag), "attrs": attrs, "text": text}
        seen = {}
        for child in elem:
            i = seen.get(strip_ns(child.tag), 0)
            seen[strip_ns(child.tag)] = i + 1
            walk(child, key, i)

    walk(root, "", 0)
    return out

def matrix_delta(t_old, t_new):
    # Report translation/scale changes of `matrix(a b c d e f)` compactly.
    def nums(t):
        if not t or not t.startswith("matrix"):
            return None
        try:
            return [float(x) for x in t[t.index("(") + 1 : t.index(")")].replace(",", " ").split()]
        except ValueError:
            return None
    o, n = nums(t_old), nums(t_new)
    if o is None or n is None or len(o) != 6 or len(n) != 6:
        return None
    parts = []
    for name, i, kind in (("x", 4, "tx"), ("y", 5, "ty"), ("sx", 0, "a"), ("sy", 3, "d")):
        if abs(o[i] - n[i]) > 1e-9:
            parts.append(f"{name} {o[i]:g}->{n[i]:g}")
    return " ".join(parts) if parts else None

pairs = collect(old_path)
new_map = dict(collect(new_path))
rows = []
for stem, old_file in pairs:
    new_file = new_map.get(stem)
    if not new_file:
        rows.append((stem, "-", "-", "-", "FAIL(no-new-export)", []))
        continue
    old_tree, new_tree = flatten(old_file), flatten(new_file)
    if old_tree is None or new_tree is None:
        rows.append((stem, "-", "-", "-", "FAIL(parse)", []))
        continue
    old_keys, new_keys = set(old_tree), set(new_tree)
    added, removed = sorted(new_keys - old_keys), sorted(old_keys - new_keys)
    changes = []
    for key in sorted(old_keys & new_keys):
        o, n = old_tree[key], new_tree[key]
        if o["tag"] != n["tag"]:
            changes.append(f'{key}: tag {o["tag"]}->{n["tag"]}')
            continue
        o_text, n_text = o["text"], n["text"]
        if o_text != n_text and (o_text or n_text):
            shown_old = o_text[:40] + ("…" if len(o_text) > 40 else "")
            shown_new = n_text[:40] + ("…" if len(n_text) > 40 else "")
            changes.append(f'{key}: text "{shown_old}"->"{shown_new}"')
        for attr in sorted(set(o["attrs"]) | set(n["attrs"])):
            ov, nv = o["attrs"].get(attr), n["attrs"].get(attr)
            if ov == nv:
                continue
            if attr == "transform":
                delta = matrix_delta(ov, nv)
                if delta:
                    changes.append(f"{key}: {delta}")
                elif ov != nv:
                    changes.append(f"{key}: transform {ov} -> {nv}")
            elif attr == "d":
                changes.append(f'{key}: path data changed ({len(nv or "")} vs {len(ov or "")} chars)')
            else:
                changes.append(f"{key}: {attr} {ov} -> {nv}")
    verdict = "IDENTICAL" if not (added or removed or changes) else "CHANGED"
    rows.append((stem, str(len(added)), str(len(removed)), str(len(changes)), verdict, changes))

exit_code = 0
print("frame\tadded\tremoved\tchanged\tverdict")
for stem, a, r, c, verdict, changes in rows:
    print(f"{stem}\t{a}\t{r}\t{c}\t{verdict}")
    for line in changes[:detail_limit]:
        print(f"  {line}")
    if len(changes) > detail_limit:
        print(f"  … {len(changes) - detail_limit} more")
changed_n = sum(1 for row in rows if row[4] == "CHANGED")
total_deltas = sum(int(row[1]) + int(row[2]) + int(row[3]) for row in rows if row[1].isdigit())
print(f"SUMMARY\t{len(rows)} frames\t{changed_n} changed\t{total_deltas} element deltas")
sys.exit(exit_code)
PY
}

run_python
