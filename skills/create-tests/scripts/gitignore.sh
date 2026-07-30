#!/usr/bin/env bash
# gitignore.sh <pattern>... — append each missing pattern to the repo-root .gitignore.
# Idempotent, logs what it appends, never creates a .gitignore (warns instead).
# Use this instead of editing .gitignore by hand, so every skill behaves the same.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ $# -gt 0 ] || die "usage: gitignore.sh <pattern>..."
ensure_gitignore "$@"
