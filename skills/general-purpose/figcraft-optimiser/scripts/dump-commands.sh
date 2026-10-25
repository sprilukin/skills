#!/usr/bin/env bash
# Regenerate the cached FigCraft command catalog (references/command-catalog.md).
# Run after a FigCraft build update, or when a run_command fails with
# "unknown command" against the live app.
#
# Usage: scripts/dump-commands.sh [path-to-figcraft-cli]
# (Override with FIGCRAFT_CLI env var.)

set -euo pipefail

CLI="${1:-${FIGCRAFT_CLI}}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/references/command-catalog.md"

if [[ ! -x "$CLI" ]]; then
  echo "figcraft-cli not found or not executable: $CLI" >&2
  echo "Pass the path as \$1 or set FIGCRAFT_CLI." >&2
  exit 1
fi

{
  echo "# FigCraft command catalog (cached)"
  echo
  echo "Generated: $(date -u +%Y-%m-%d) · CLI: $("$CLI" --version) · lines: $(("$("$CLI" commands | wc -l)" + 8))"
  echo "Regenerate: scripts/dump-commands.sh (see SKILL.md). Source of truth: figcraft-cli commands; the running app may have a different build — verify ids with \`list_commands {filter: \"...\"}\` ONLY if a run_command fails with unknown command."
  echo "Search this file with grep. Do NOT call figcraft-app list_commands without a filter."
  echo
  echo '```'
  "$CLI" commands
  echo '```'
} > "$OUT"

echo "Wrote $OUT ($("$(wc -l < "$OUT")") lines)"
