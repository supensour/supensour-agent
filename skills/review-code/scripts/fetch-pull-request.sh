#!/usr/bin/env bash
# fetch-pull-request.sh --branch <SRC> [--platform <key>]
# Finds ALL open PR/MRs whose SOURCE branch is <SRC>; prints a JSON array (one line):
#   [{"number","url","title","source","base"}, ...]   ([] if none / no token)
#   source = source/head branch, base = target branch
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SRC="" OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)   SRC="$2"; shift 2 ;;
    --platform) OVERRIDE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$SRC" ] || die "fetch-pull-request.sh: --branch <SRC> required."

init_platform "$OVERRIDE"
result="$(platform_dispatch fetch_pr "$SRC" 2>/dev/null || true)"
printf '%s\n' "${result:-[]}"
