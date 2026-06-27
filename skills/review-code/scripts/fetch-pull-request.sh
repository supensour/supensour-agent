#!/usr/bin/env bash
# fetch-pull-request.sh --branch <SRC> [--platform <key>]
# Finds the open PR/MR whose SOURCE branch is <SRC> and prints it as one JSON line:
#   {"number","url","title","base"}   (empty object {} if none / no token)
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
printf '%s\n' "${result:-{\}}"
