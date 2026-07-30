#!/usr/bin/env bash
# plan-path.sh <spec-path> — resolve (and create the parent dir of) the plan file
# the analyst writes for one target, and the writer reads:
#   <repo-root>/.supensour/create-tests/<branch>/.plans/<spec-path>.plan.md
# Living under <branch>/ means `clean.sh [branch]` / `--clean-all` prune plans too.
# Also ensures .supensour/create-tests/ is gitignored. Prints the resolved path.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SPEC="${1:-}"
[ -n "$SPEC" ] || die "usage: plan-path.sh <spec-path>"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not a git repository."
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] && [ "$BRANCH" != HEAD ] || die "Could not resolve current branch."
SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr '/' '-')"

PLAN="$ROOT/.supensour/create-tests/$SAFE_BRANCH/.plans/${SPEC#/}.plan.md"
mkdir -p "$(dirname "$PLAN")"

# Keep plans out of git (shared helper: appends only to an existing .gitignore, logs it).
ensure_gitignore '.supensour/create-tests/'

printf '%s\n' "$PLAN"
