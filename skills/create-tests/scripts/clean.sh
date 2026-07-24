#!/usr/bin/env bash
# clean.sh — remove locally saved --proposal runs.
#   clean.sh [<branch>]   remove saved proposals for <branch> (default: current branch)
#   clean.sh --all        remove all saved proposals for every branch
#
# Saved proposals live in <repo-root>/.supensour/create-tests/.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not a git repository."
BASE="$ROOT/.supensour/create-tests"

[ -d "$BASE" ] || { log "Nothing to clean — no saved proposals at $BASE"; exit 0; }

case "${1:-}" in
  --all)
    rm -rf "$BASE"
    log "🧹 Removed all saved proposals ($BASE)"
    ;;
  -*)
    die "clean.sh: unknown option '$1' (use --all or a branch name)"
    ;;
  *)
    branch="${1:-}"
    [ -n "$branch" ] || branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    { [ -n "$branch" ] && [ "$branch" != HEAD ]; } || die "Could not resolve current branch — pass one explicitly."
    safe="$(printf '%s' "$branch" | tr '/' '-')"
    dir="$BASE/$safe"
    [ -d "$dir" ] || { log "Nothing to clean for branch '$branch' ($dir absent)"; exit 0; }
    rm -rf "$dir"
    log "🧹 Removed saved proposals for branch '$branch' ($dir)"
    ;;
esac
