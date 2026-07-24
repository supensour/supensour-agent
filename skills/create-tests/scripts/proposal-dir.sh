#!/usr/bin/env bash
# proposal-dir.sh
# Resolves (and creates) the disk location for one --proposal run's saved specs:
#   <repo-root>/.supensour/create-tests/<branch>/<timestamp>
# <branch> = current branch, sanitized (slashes → -). <timestamp> = YYYYMMDD-HHMMSS.
# Call ONCE per run (not per target) so every target in the run shares one timestamp dir.
# Prints the resolved path.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not a git repository."
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] && [ "$BRANCH" != HEAD ] || die "Could not resolve current branch."
SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr '/' '-')"

DIR="$ROOT/.supensour/create-tests/$SAFE_BRANCH/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"
printf '%s\n' "$DIR"
