#!/usr/bin/env bash
# detect-targets.sh [--files <glob>...] [--base <branch>] [--lang <key>]
# Prints the list of SOURCE files to generate tests for, one per line.
#   --files <glob>   one or more globs (repeatable); explicit target set.
#   (no --files)     changed source files vs <base> (git diff <base>...HEAD --name-only).
#   --base <branch>  diff base (default: origin/HEAD → main → master → develop).
#   --lang <key>     restrict to a language's source extensions (vue|springboot).
# Existing test/spec files and non-source files are filtered out.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

GLOBS=() BASE="" LANG_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --files) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do GLOBS+=("$1"); shift; done ;;
    --base)  BASE="$2"; shift 2 ;;
    --lang)  LANG_FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Per-repo hints (skip detection): default --lang and --base from project config.
[ -z "$LANG_FILTER" ] && LANG_FILTER="$(proj_get project language 2>/dev/null || true)"
[ -z "$BASE" ] && BASE="$(proj_get git base_branch 2>/dev/null || true)"

_default_base() {
  local d
  d="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  [ -n "$d" ] && { printf '%s' "$d"; return; }
  for b in main master develop; do
    git rev-parse --verify --quiet "$b" >/dev/null && { printf '%s' "$b"; return; }
  done
  printf 'main'
}

# Gather candidate files.
# --files goes through the shared glob dialect (* ? [] ** {a,b}; a bare directory means
# its subtree) — see lib/core.sh → expand_globs, which unions tracked, untracked and
# literal paths. Testing a brand-new (untracked) source file is the common case.
candidates() {
  if [ "${#GLOBS[@]}" -gt 0 ]; then
    expand_globs "${GLOBS[@]}"
  else
    [ -z "$BASE" ] && BASE="$(_default_base)"
    local ref="$BASE"
    git rev-parse --verify --quiet "$BASE" >/dev/null || ref="origin/$BASE"
    git diff "$ref...HEAD" --name-only --diff-filter=d 2>/dev/null
  fi
}

# Filter: drop existing tests/specs; keep source files; apply --lang if set.
# Anything dropped for living under a test path is logged (it may be a real source
# file, e.g. src/tests/factory.js) so a silent skip never looks like full coverage.
SKIPPED_TEST_PATHS=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.spec.*|*.test.*|*Test.java|*Tests.java|*Test.kt|*Tests.kt) continue ;;
    # `src/test/*` used to sit here, but `*/test/*` already covers it — while a
    # repo-root `test/…` / `tests/…` matched neither and slipped through as a target.
    */test/*|*/tests/*|test/*|tests/*)
      l="$(detect_lang "$f")" || true
      [ -n "$l" ] && SKIPPED_TEST_PATHS+=("$f")
      continue ;;
  esac
  l="$(detect_lang "$f")" || true
  [ -z "$l" ] && continue
  if [ -n "$LANG_FILTER" ] && [ "$l" != "$LANG_FILTER" ]; then continue; fi
  printf '%s\n' "$f"
done < <(candidates | sort -u)

if [ "${#SKIPPED_TEST_PATHS[@]}" -gt 0 ]; then
  warn "skipped ${#SKIPPED_TEST_PATHS[@]} candidate(s) matching test paths:"
  printf '    %s\n' "${SKIPPED_TEST_PATHS[@]}" >&2
fi
