#!/usr/bin/env bash
# spec-path.sh [--type <unit|integration>] <lang> <source-file>...
# Print the conventional spec path per source.
# Output: one TSV line per input → "<source>\t<spec-path>\t<new|append>".
#   new     no spec there yet → write a fresh file (watermark as the header)
#   append  a spec exists     → add cases to it, never rewrite what's there
# --type picks the test-root family (unit → test/unit/specs, integration →
# test/integration); defaults to project.test_type in the repo config, else unit.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --type) export CT_TEST_TYPE="$2"; shift 2 ;;
    *) break ;;
  esac
done

LANG_ARG="${1:-}"; shift || true
[ -n "$LANG_ARG" ] && [ $# -gt 0 ] || die "usage: spec-path.sh [--type <t>] <lang> <source-file>..."

load_lang "$LANG_ARG"
for src in "$@"; do
  spec="$(lang_dispatch spec_path "$src")"
  state="new"; [ -f "$spec" ] && state="append"
  printf '%s\t%s\t%s\n' "$src" "$spec" "$state"
done
