#!/usr/bin/env bash
# Diff exported FigCraft frames against @2x ground-truth captures.
#
# Usage: scripts/qa-export-diff.sh CAPTURES_DIR EXPORTS_DIR [THRESHOLD_PCT] [--artifacts [DIR]]
#   CAPTURES_DIR  dir of @2x capture PNGs (e.g. design/screens/light/1440/)
#   EXPORTS_DIR   dir of scale-1 exports, named like the captures (stem match)
#   THRESHOLD_PCT default 2.0 — frames above it are flagged FAIL
#   --artifacts   for each FAILing frame, write a perceptual diff overlay and a
#                 side-by-side strip (export | capture | overlay) into DIR
#                 (default /tmp/qa-export-diff-artifacts). Needs `odiff` and
#                 `magick`; each tool is skipped gracefully if missing.
#
# Output: machine-readable table `frame | diff% | verdict` (CSV-ish), one row
# per frame, plus a final SUMMARY line. Exits 1 if any frame fails.
#
# Requires ImageMagick (`magick` or `compare`) with a Python/PIL fallback.

set -euo pipefail

CAP=""
EXP=""
THRESHOLD="2.0"
ARTIFACTS_DIR=""
ARTIFACTS=0

# Parse flags, keep positional order (captures, exports, threshold).
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifacts)
      ARTIFACTS=1
      ARTIFACTS_DIR="${2:-}"
      [[ -n "$ARTIFACTS_DIR" ]] && shift
      ;;
    *) positional+=("$1") ;;
  esac
  shift
done
[[ ${#positional[@]} -ge 2 ]] || { echo "usage: qa-export-diff.sh CAPTURES_DIR EXPORTS_DIR [THRESHOLD_PCT] [--artifacts [DIR]]" >&2; exit 2; }
CAP="${positional[0]}"
EXP="${positional[1]}"
THRESHOLD="${positional[2]:-2.0}"
if [[ "$ARTIFACTS" -eq 1 && -z "$ARTIFACTS_DIR" ]]; then
  ARTIFACTS_DIR="/tmp/qa-export-diff-artifacts"
fi

have() { command -v "$1" >/dev/null 2>&1; }

pair_exports() {
  # Match each export to a capture by stem; exports may carry a "-1" dedup suffix.
  local exp cap stem
  for exp in "$EXP"/*.png; do
    [[ -e "$exp" ]] || continue
    stem="$(basename "$exp" .png)"
    stem="${stem%-1}"
    cap="$(find "$CAP" -maxdepth 1 -name "${stem}.png" -print -quit)"
    if [[ -n "$cap" ]]; then
      printf '%s\t%s\n' "$exp" "$cap"
    else
      printf '%s\tMISSING\n' "$exp"
    fi
  done
}

# Write visual artifacts for one failing frame: odiff overlay + side-by-side strip.
write_artifacts() {
  local exp cap name stem out
  exp="$1"; cap="$2"
  name="$(basename "$exp" .png)"
  stem="${name%-1}"
  out="$ARTIFACTS_DIR/$stem"
  mkdir -p "$out"
  # odiff writes no overlay when pixels match — synthesize a blank one from the export.
  if have odiff; then
    odiff "$exp" "$cap" "$out/diff-overlay.png" -t 0.15 >/dev/null 2>&1 || true
    [[ -f "$out/diff-overlay.png" ]] || magick "$exp" "$out/diff-overlay.png"
  fi
  if have magick; then
    local overlay
    overlay="$out/diff-overlay.png"
    [[ -f "$overlay" ]] || overlay="$exp"
    magick "$exp" "$cap" "$overlay" -background "#333333" -splice 4x0+0+0 -append "$out/side-by-side.png"
  fi
}

fail=0
total=0
printf 'frame\tdiff_pct\tverdict\n'

while IFS=$'\t' read -r exp cap; do
  total=$((total + 1))
  name="$(basename "$exp" .png)"
  if [[ "$cap" == "MISSING" ]]; then
    printf '%s\t-\tFAIL(no-capture)\n' "$name"
    fail=$((fail + 1))
    continue
  fi
  # Downscale the @2x capture to the export's size.
  tmp="$(mktemp -t cap1x.XXXXXX.png)"
  if have magick; then
    magick "$cap" -resize '50%' "$tmp"
  elif have compare; then
    : # handled below via python fallback
  fi
  diff_pct=""
  if have magick; then
    # compare -metric AE prints "<count> (<ratio>)"; keep the ratio.
    raw="$(compare -metric AE "$exp" "$tmp" null: 2>&1 || true)"
    ratio="$(printf '%s' "$raw" | sed -n 's/.*(\([0-9.e+-]*\)).*/\1/p')"
    if [[ -n "$ratio" ]]; then
      diff_pct="$(python3 -c "print(f'{100*float($ratio):.2f}')")"
    else
      diff_pct="$(python3 -c "print(f'{100*float($raw or 0):.2f}')")"
    fi
  else

    diff_pct="$(python3 - "$exp" "$tmp" <<'PY'
import sys
try:
    from PIL import Image, ImageChops
except ImportError:
    print("ERR(no-pill)")
    sys.exit(0)
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB").resize(a.size)
bbox = ImageChops.difference(a, b).getbbox()
if bbox is None:
    print("0.00")
else:
    import numpy as np
    d = np.asarray(ImageChops.difference(a, b)).sum(axis=2)
    print(f"{100 * (d > 24).mean():.2f}")
PY
)"
  fi
  rm -f "$tmp"
  verdict=""
  case "$diff_pct" in ERR*|""|"-") verdict="FAIL(diff-error)" ;; esac
  if [[ "${diff_pct%%.*}" =~ ^[0-9]+$ ]]; then
    if python3 -c "import sys; sys.exit(0 if float('${diff_pct:-999}') <= ${THRESHOLD} else 1)"; then
      verdict="PASS"
    else
      verdict="FAIL"
      fail=$((fail + 1))
    fi
  fi
  if [[ "$ARTIFACTS" -eq 1 && "$verdict" == FAIL ]]; then
    write_artifacts "$exp" "$cap"
  fi
  printf '%s\t%s\t%s\n' "$name" "${diff_pct:--}" "${verdict:-FAIL(diff-error)}"
done < <(pair_exports)

printf 'SUMMARY\t%s frames\t%s failed\tthreshold %s%%\n' "$total" "$fail" "$THRESHOLD"
if [[ "$ARTIFACTS" -eq 1 && "$fail" -gt 0 && -n "$ARTIFACTS_DIR" ]]; then
  printf 'artifacts: %s\n' "$ARTIFACTS_DIR"
fi
[[ "$fail" -eq 0 ]]
