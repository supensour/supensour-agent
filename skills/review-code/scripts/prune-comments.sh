#!/usr/bin/env bash
# prune-comments.sh <PR> [--platform <key>]
# Deletes THIS skill's own prior review comments on the PR/MR (identified by the
# hidden marker), so a fresh push doesn't stack duplicates. Prints the count:
#   🧹 Removed N stale review comment(s)
# Auth/permission failure → warn and continue (never aborts the push).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PR="" OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) OVERRIDE="$2"; shift 2 ;;
    *) [ -z "$PR" ] && PR="$1"; shift ;;
  esac
done
[ -n "$PR" ] || die "prune-comments.sh: <PR> required."

init_platform "$OVERRIDE"
require_token || { printf '🧹 Removed 0 stale review comment(s)\n'; exit 0; }

n="$(platform_dispatch delete_prior "$PR" 2>/dev/null || echo 0)"
printf '🧹 Removed %s stale review comment(s)\n' "${n:-0}"
