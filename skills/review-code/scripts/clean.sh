#!/usr/bin/env bash
# clean.sh — remove locally saved reviews (comments + JSON + any kept worktrees).
#   clean.sh [<branch>]   remove saved reviews for <branch> (default: current branch)
#   clean.sh --all        remove all saved reviews for every branch
#
# Saved reviews live in <repo-root>/.supensour/review-code/. Removing a branch's
# reviews also removes its kept worktrees (via `git worktree remove`) so none are orphaned.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not a git repository."
BASE="$ROOT/.supensour/review-code"

# remove_worktrees <glob> — git-remove each matching worktree dir, fall back to rm.
remove_worktrees() {
  local wt
  for wt in $1; do
    [ -d "$wt" ] || continue
    git -C "$ROOT" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    log "🧹 Removed worktree $wt"
  done
}

[ -d "$BASE" ] || { log "Nothing to clean — no saved reviews at $BASE"; exit 0; }

case "${1:-}" in
  --all)
    remove_worktrees "$BASE/worktrees/review-*"
    rm -rf "$BASE"
    log "🧹 Removed all saved reviews ($BASE)"
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
    remove_worktrees "$BASE/worktrees/review-${safe}-*"
    rm -rf "$dir"
    log "🧹 Removed saved reviews for branch '$branch' ($dir)"
    ;;
esac
