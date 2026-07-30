#!/usr/bin/env bash
# protect.sh <path>... — shield generated spec files from destructive git commands.
#
# Marks each path intent-to-add (`git add -N`), which puts it in the index while
# leaving its content unstaged. Files in the index are NOT untracked, so a stray
# `git clean -fd` / `-fdx` can no longer delete them.
#
# Doubles as an integrity check: any path that is missing on disk is reported as
# `✖ MISSING <path>` and the script exits 3, so the caller can detect lost work.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -gt 0 ] || die "usage: protect.sh <path>..."

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  warn "Not a git repo — nothing to protect."; exit 0; }

missing=0
for p in "$@"; do
  if [ -f "$p" ]; then
    if git add -N -- "$p" 2>/dev/null; then
      log "🔒 protected $p"
    else
      # Usually .gitignore'd. The file exists but stays untracked → a stray `git clean -fd`
      # can still delete it. Loud on purpose: the caller must surface this in its summary.
      printf '⚠ UNPROTECTED %s (not indexable — gitignored?) — a git clean would delete it\n' "$p" >&2
    fi
  else
    printf '✖ MISSING %s\n' "$p" >&2
    missing=1
  fi
done

[ "$missing" -eq 0 ] || exit 3
