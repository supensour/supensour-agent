#!/usr/bin/env bash
# worktree.sh <command> [args]
# Mechanical worktree helpers ONLY — the decision to create one when the tree is
# dirty (ask user vs abort) stays in SKILL.md. Scripts never prompt.
#
#   status <SRC>   → JSON {current, src, dirty, needs_worktree}
#   ensure <SRC>   → create a detached worktree at SRC; print its path on stdout
#   remove <PATH>  → git worktree remove --force <PATH>
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

cmd="${1:-}"; shift || true

case "$cmd" in
  status)
    SRC="${1:?worktree.sh status <SRC>}"
    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    dirty=false; [ -n "$(git status --porcelain 2>/dev/null)" ] && dirty=true
    needs=false; { [ "$SRC" != "$current" ] || [ "$dirty" = true ]; } && needs=true
    # Four known-shape fields — printf, not jq: this command must work before any
    # dependency check, and a branch name is the only free-form value (quotes escaped).
    printf '{"current":"%s","src":"%s","dirty":%s,"needs_worktree":%s}\n' \
      "$(printf '%s' "$current" | sed 's/["\\]/\\&/g')" \
      "$(printf '%s' "$SRC"     | sed 's/["\\]/\\&/g')" \
      "$dirty" "$needs"
    ;;
  ensure)
    SRC="${1:?worktree.sh ensure <SRC>}"
    # Ignore the tree BEFORE creating it — otherwise a whole checked-out worktree sits
    # untracked until Step 4's gitignore call, and any `git add -A` would stage it.
    ensure_gitignore '.supensour/review-code/'
    safe="$(printf '%s' "$SRC" | tr '/' '-')"
    ts="$(date +%Y%m%d-%H%M%S)"
    wt=".supensour/review-code/worktrees/review-${safe}-${ts}"
    ref="$SRC"
    git rev-parse --verify --quiet "$SRC" >/dev/null || ref="origin/$SRC"
    git worktree add --detach "$wt" "$ref" >&2 || die "git worktree add failed for $ref"
    printf '%s\n' "$wt"
    ;;
  remove)
    WT="${1:?worktree.sh remove <PATH>}"
    git worktree remove --force "$WT" || warn "Could not remove worktree $WT — remove manually: git worktree remove --force $WT"
    ;;
  *)
    die "worktree.sh: unknown command '$cmd' (status|ensure|remove)"
    ;;
esac
