#!/usr/bin/env bash
# Prepare a QA pass: scratch tree, capture symlinks, and the exact commands
# the QA worker runs next. Text-only output — safe for the planner to run.
#
# Usage: scripts/qa-setup.sh MANIFEST THEME VIEWPORT [SCRATCH_DIR] [CAPTURES_ROOT]
#   MANIFEST       one `FRAME_ID capture-stem` per line (# comments, blanks ok)
#   THEME          e.g. light | dark
#   VIEWPORT       e.g. 1440 | 375
#   SCRATCH_DIR    default: a fresh mktemp dir
#   CAPTURES_ROOT  default: captures (captures live in ROOT/THEME/VIEWPORT/)
#
# Creates SCRATCH/cap/ (symlinks to the captures) and SCRATCH/exp/ (empty:
# `export` fails if the directory is missing), then prints one `export` call
# per frame and the qa-export-diff.sh command to run afterwards.

set -euo pipefail

[[ $# -ge 3 ]] || { echo "usage: qa-setup.sh MANIFEST THEME VIEWPORT [SCRATCH_DIR] [CAPTURES_ROOT]" >&2; exit 2; }
MANIFEST="$1"; THEME="$2"; VIEWPORT="$3"
SCRATCH="${4:-$(mktemp -d)}"
ROOT="${5:-captures}"
SRC="$(cd "$ROOT/$THEME/$VIEWPORT" 2>/dev/null && pwd)" || { echo "captures dir not found: $ROOT/$THEME/$VIEWPORT" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SCRATCH/cap" "$SCRATCH/exp"
SCRATCH="$(cd "$SCRATCH" && pwd)"

calls=()
missing=0
while read -r id stem _; do
  [[ -z "${id:-}" || "$id" == \#* ]] && continue
  if [[ -z "${stem:-}" ]]; then echo "bad manifest line (need FRAME_ID capture-stem): $id" >&2; exit 1; fi
  if [[ -e "$SRC/$stem.png" ]]; then
    ln -sf "$SRC/$stem.png" "$SCRATCH/cap/$stem.png"
  else
    echo "MISSING capture: $SRC/$stem.png" >&2
    missing=$((missing + 1))
  fi
  calls+=("export {ids: [\"$id\"], scale: 1, path: \"$SCRATCH/exp/$stem.png\"}")
done < "$MANIFEST"

echo "scratch: $SCRATCH (cap/ exp/ ready)"
echo "# 1. run these exports (one per frame, never a whole page):"
printf '%s\n' "${calls[@]}"
echo "# 2. then diff (threshold %, default 2.0):"
echo "bash $HERE/qa-export-diff.sh $SCRATCH/cap $SCRATCH/exp 2.0"
[[ "$missing" -eq 0 ]] || { echo "$missing capture(s) missing" >&2; exit 1; }
