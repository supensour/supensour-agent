#!/usr/bin/env bash
# clean.sh — remove locally saved analyst plan files.
#   clean.sh [<branch>]   remove scratch state for <branch> (default: current branch)
#   clean.sh --all        remove scratch state for every branch
#
# Scratch state = <repo-root>/.supensour/create-tests/<branch>/: .plans/ (analyst→writer handoff
# files) and .runs/ (per-target run-budget ledgers). Both are per-branch and disposable
# between analyst and writer. Removing them never touches generated spec files.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not a git repository."
BASE="$ROOT/.supensour/create-tests"

[ -d "$BASE" ] || { log "Nothing to clean — no saved plans at $BASE"; exit 0; }

case "${1:-}" in
  --all)
    rm -rf "$BASE"
    log "🧹 Removed all saved plans ($BASE)"
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
    log "🧹 Removed saved plans for branch '$branch' ($dir)"
    ;;
esac
