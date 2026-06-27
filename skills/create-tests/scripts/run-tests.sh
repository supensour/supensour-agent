#!/usr/bin/env bash
# run-tests.sh <lang> <spec-or-class> [--coverage <source-file>]
# Runs the test(s) for a generated spec via the language lib, printing the
# runner output. Exit code = the test runner's exit code.
#   vue:        run-tests.sh vue <spec-file> [--coverage <source-file>]
#   springboot: run-tests.sh springboot <ClassName|source-file>
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

LANG="${1:-}"; TARGET="${2:-}"
[ -n "$LANG" ] && [ -n "$TARGET" ] || die "usage: run-tests.sh <lang> <spec-or-class> [--coverage <source>]"
shift 2 || true

COVERAGE_SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --coverage) COVERAGE_SRC="$2"; shift 2 ;;
    *) shift ;;
  esac
done

load_lang "$LANG"
lang_dispatch run_tests "$TARGET" ${COVERAGE_SRC:+"$COVERAGE_SRC"}
