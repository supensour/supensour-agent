#!/usr/bin/env bash
# collect-diff.sh <BASE> <SRC> [--name-status|--full] [--path <glob>...]
# Prints the diff of SRC against BASE (three-dot: changes on SRC since it forked).
# Default prints both sections with headers; flags restrict to one.
#   --name-status → file list only      --full → unified diff only
#   --path <glob>  restrict the diff to matching paths (repeatable, or several after
#                  one --path). An analyst reviewing one file passes --path <file> so
#                  it reads its own diff, not the whole PR's.
# Globs are the shared dialect (* ? [] ** {a,b}; a bare directory = its subtree) —
# see lib/core.sh → normalize_globs.
# Uses origin/<ref> when a ref isn't checked out locally.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MODE="both"; GLOBS=(); POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --name-status) MODE="names"; shift ;;
    --full)        MODE="full"; shift ;;
    --path)        shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do GLOBS+=("$1"); shift; done ;;
    --)            shift; while [ $# -gt 0 ]; do GLOBS+=("$1"); shift; done ;;
    *)             POS+=("$1"); shift ;;
  esac
done

BASE="${POS[0]:-}"; SRC="${POS[1]:-}"
[ -n "$BASE" ] && [ -n "$SRC" ] \
  || die "collect-diff.sh: usage <BASE> <SRC> [--name-status|--full] [--path <glob>...]"

# Path scoping goes to git as pathspecs, not as expanded file lists: a pathspec also
# matches files the diff deletes, which no longer exist in the work tree.
PATHSPECS=()
if [ "${#GLOBS[@]}" -gt 0 ]; then
  while IFS= read -r _s; do [ -n "$_s" ] && PATHSPECS+=("$_s"); done < <(glob_pathspec "${GLOBS[@]}")
  [ "${#PATHSPECS[@]}" -gt 0 ] || die "collect-diff.sh: --path matched no pattern: ${GLOBS[*]}"
fi

# Resolve a ref to a local name or origin/<ref> if only on remote.
_ref() {
  if git rev-parse --verify --quiet "$1" >/dev/null; then printf '%s' "$1"
  elif git rev-parse --verify --quiet "origin/$1" >/dev/null; then printf 'origin/%s' "$1"
  else die "Ref not found locally or on origin: $1"; fi
}
B="$(_ref "$BASE")"; S="$(_ref "$SRC")"

if [ "$MODE" = names ] || [ "$MODE" = both ]; then
  [ "$MODE" = both ] && printf '=== name-status ===\n'
  git diff "$B...$S" --name-status ${PATHSPECS[@]+-- "${PATHSPECS[@]}"}
fi
if [ "$MODE" = full ] || [ "$MODE" = both ]; then
  [ "$MODE" = both ] && printf '\n=== diff ===\n'
  git diff "$B...$S" ${PATHSPECS[@]+-- "${PATHSPECS[@]}"}
fi
