#!/usr/bin/env bash
# coverage-scan.sh [--threshold <n>] <lang> <source-file>...
#
# Pre-flight gate: runs the EXISTING specs that cover the given source files with
# coverage scoped to those sources only, then reports per-source coverage so the
# orchestrator can skip files that are already covered.
#
# Output: one keyed TSV line per source, in input order:
#   vue:        <source>\tstatements=<n>\tbranches=<n>\tfunctions=<n>\tlines=<n>\t<SKIP|GENERATE>
#   springboot: <source>\tinstructions=<n>\tbranches=<n>\tmethods=<n>\tlines=<n>\t<SKIP|GENERATE>
# Keys are explicit so metric sets can differ per language. `-` = no data.
# SKIP     = every metric >= threshold (default 100) → no subagent needed.
# GENERATE = anything else, including an unparseable or failing run (fail-safe).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

THRESHOLD=100
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --type)      export CT_TEST_TYPE="$2"; shift 2 ;;
    *) break ;;
  esac
done
case "$THRESHOLD" in
  ''|*[!0-9.]*) die "coverage-scan.sh: --threshold must be numeric (got '$THRESHOLD')" ;;
esac

LANG_ARG="${1:-}"; shift || true
[ -n "$LANG_ARG" ] && [ $# -gt 0 ] || die "usage: coverage-scan.sh [--threshold <n>] <lang> <source-file>..."

export CT_THRESHOLD="$THRESHOLD"
load_lang "$LANG_ARG"
lang_dispatch coverage_scan "$@"
