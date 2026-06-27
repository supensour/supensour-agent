#!/usr/bin/env bash
# collect-diff.sh <BASE> <SRC> [--name-status|--full]
# Prints the diff of SRC against BASE (three-dot: changes on SRC since it forked).
# Default prints both sections with headers; flags restrict to one.
#   --name-status → file list only      --full → unified diff only
# Uses origin/<ref> when a ref isn't checked out locally.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

BASE="${1:-}"; SRC="${2:-}"
[ -n "$BASE" ] && [ -n "$SRC" ] || die "collect-diff.sh: usage <BASE> <SRC> [--name-status|--full]"
MODE="both"; [ "${3:-}" = "--name-status" ] && MODE="names"; [ "${3:-}" = "--full" ] && MODE="full"

# Resolve a ref to a local name or origin/<ref> if only on remote.
_ref() {
  if git rev-parse --verify --quiet "$1" >/dev/null; then printf '%s' "$1"
  elif git rev-parse --verify --quiet "origin/$1" >/dev/null; then printf 'origin/%s' "$1"
  else die "Ref not found locally or on origin: $1"; fi
}
B="$(_ref "$BASE")"; S="$(_ref "$SRC")"

if [ "$MODE" = names ] || [ "$MODE" = both ]; then
  [ "$MODE" = both ] && printf '=== name-status ===\n'
  git diff "$B...$S" --name-status
fi
if [ "$MODE" = full ] || [ "$MODE" = both ]; then
  [ "$MODE" = both ] && printf '\n=== diff ===\n'
  git diff "$B...$S"
fi
