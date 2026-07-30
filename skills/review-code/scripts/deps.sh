#!/usr/bin/env bash
# deps.sh — external tools this skill needs, as TSV: <cmd>\t<status>\t<path|hint>
# status: ok · MISSING (required, run will fail) · absent (optional) (degrades only).
# Exit 3 when a REQUIRED tool is missing, so a caller can surface it without parsing.
#
#   bash  4+ (associative arrays in the comment reconciler)        required
#   git   diffs, worktrees, pathspecs                             required
#   jq    platform API responses                                  required
#   curl  platform API calls                                      required
#   gh    GitHub PR lookup fallback when no token is set           optional
#
# A bash older than 4 never reaches this table: lib/core.sh refuses to load and prints
# how to install a newer one. Runs on Linux, macOS and Windows (Git Bash / WSL).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

printf 'os\t%s\t%s\n' "$(os_kind)" "$(uname -sm 2>/dev/null || echo '-')"
printf 'bash\tok\t%s\n' "${BASH_VERSION:-unknown}"
REQ="$(deps_report git jq curl)"
OPT="$(deps_report gh | sed 's/	MISSING	/	absent (optional)	/')"
printf '%s\n%s\n' "$REQ" "$OPT"
printf '%s' "$REQ" | grep -q '	MISSING	' && exit 3
exit 0
