#!/usr/bin/env bash
# smoke.sh — run the scripts for real on this machine. Complements validate.sh (static):
# this one executes things, so it catches OS differences a grep can't — BSD vs GNU flags,
# a missing tool, bash-version behavior, Git Bash path shapes.
#
#   bash scripts/smoke.sh
#
# Read-only with respect to the repo: fixtures live in a temp dir that is always removed,
# and nothing here writes config, posts a comment or calls a network API.
set -uo pipefail

# Byte ordering, everywhere. This file compares `sort`ed file lists as exact strings, and
# glibc's en_US.UTF-8 collation orders `Money.vue` differently than BSD/C does — the
# assertions would fail on Linux for a reason that has nothing to do with the code.
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
ok()   { printf '  ✓ %s\n' "$*"; }
bad()  { printf '  ✖ %s\n' "$*" >&2; FAIL=1; }
sect() { printf '\n── %s\n' "$*"; }

FIXT="$ROOT/.smoke-fixtures"
cleanup() { rm -rf "$FIXT"; }
trap cleanup EXIT
rm -rf "$FIXT"
mkdir -p "$FIXT/src/util" "$FIXT/test/unit"
: > "$FIXT/src/util/money.ts"
: > "$FIXT/src/util/Money.vue"
: > "$FIXT/src/util/money.spec.ts"
: > "$FIXT/test/unit/helper.js"

# --- shared core -------------------------------------------------------------
sect "lib/core.sh on $(uname -s 2>/dev/null || echo unknown)"
# shellcheck disable=SC1091
SKILL_DIR="$ROOT/skills/create-tests" . "$ROOT/lib/core.sh"
ok "sourced (bash ${BASH_VERSION%%(*}, os=$(os_kind), cores=$(cpu_cores))"

case "$(cpu_cores)" in ''|*[!0-9]*) bad "cpu_cores did not return a number" ;; *) ok "cpu_cores numeric" ;; esac
hint="$(_install_hint jq)"
case "$hint" in
  *brew*|*apt-get*|*dnf*|*pacman*|*apk*|*winget*|*scoop*) ok "install hint fits this OS: $hint" ;;
  *) bad "install hint looks wrong for this OS: $hint" ;;
esac

# --- glob dialect ------------------------------------------------------------
sect "glob dialect"
got="$(expand_globs ".smoke-fixtures/src/**/*.{ts,vue}" | sort | tr '\n' ' ')"
want=".smoke-fixtures/src/util/Money.vue .smoke-fixtures/src/util/money.spec.ts .smoke-fixtures/src/util/money.ts "
[ "$got" = "$want" ] && ok "** + {a,b} over untracked files" || bad "expand_globs: got [$got] want [$want]"

got="$(expand_globs ".smoke-fixtures/src/*.ts" | tr '\n' ' ')"
[ -z "$got" ] && ok "* does not cross /" || bad "* crossed a / boundary: [$got]"

got="$(expand_globs ".smoke-fixtures/test" | tr '\n' ' ')"
[ "$got" = ".smoke-fixtures/test/unit/helper.js " ] && ok "bare directory = subtree" \
  || bad "directory expansion: [$got]"

# --- per-skill scripts -------------------------------------------------------
for skill in create-tests review-code; do
  sect "skills/$skill"
  out="$(bash "skills/$skill/scripts/deps.sh")"; rc=$?
  case "$rc" in
    0) ok "deps.sh — all required tools present" ;;
    3) printf '%s\n' "$out" | grep '	MISSING	' >&2; ok "deps.sh — reported a missing required tool (exit 3)" ;;
    *) bad "deps.sh exited $rc" ;;
  esac
  printf '%s\n' "$out" | grep -q '^bash	ok' || bad "deps.sh did not report the bash row"
  bash "skills/$skill/scripts/help.sh" >/dev/null 2>&1 && ok "help.sh runs" || bad "help.sh failed"
  bash "skills/$skill/scripts/watermark.sh" >/dev/null 2>&1 && ok "watermark.sh runs" || bad "watermark.sh failed"
done

sect "create-tests: target detection"
got="$(bash skills/create-tests/scripts/detect-targets.sh --files ".smoke-fixtures/**/*.{ts,vue,js}" 2>/dev/null | sort | tr '\n' ' ')"
want=".smoke-fixtures/src/util/Money.vue .smoke-fixtures/src/util/money.ts "
[ "$got" = "$want" ] && ok "specs and test dirs filtered out" || bad "detect-targets: got [$got] want [$want]"

sect "review-code: diff scoping + worktree status"
if git rev-parse --verify --quiet HEAD~1 >/dev/null; then
  all="$(bash skills/review-code/scripts/collect-diff.sh HEAD~1 HEAD --name-status | wc -l | tr -d ' ')"
  one="$(bash skills/review-code/scripts/collect-diff.sh HEAD~1 HEAD --name-status --path 'skills/**' | wc -l | tr -d ' ')"
  [ "$one" -le "$all" ] && ok "--path narrows the diff ($one of $all paths)" \
    || bad "--path widened the diff ($one > $all)"
else
  printf '  ↷ only one commit — diff scoping skipped\n'
fi
st="$(bash skills/review-code/scripts/worktree.sh status "$(git rev-parse --abbrev-ref HEAD)")"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$st" | jq -e '.current and has("dirty") and has("needs_worktree")' >/dev/null \
    && ok "worktree.sh status emits valid JSON" || bad "worktree.sh status JSON invalid: $st"
else
  case "$st" in '{"current":'*) ok "worktree.sh status shape (jq absent)" ;; *) bad "worktree status: $st" ;; esac
fi
bash skills/review-code/scripts/explain.sh >/dev/null 2>&1 && ok "explain.sh runs" || bad "explain.sh failed"
bash skills/review-code/scripts/verify.sh --print >/dev/null 2>&1 && ok "verify.sh --print runs" || bad "verify.sh --print failed"

# --- bash floor --------------------------------------------------------------
sect "bash version floor"
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]; then
  if SKILL_DIR="$ROOT/skills/create-tests" /bin/bash -c ". '$ROOT/lib/core.sh'" 2>/dev/null; then
    bad "lib/core.sh loaded under bash 3.2 — require_bash did not fire"
  else
    ok "require_bash rejects the system bash 3.2"
  fi
else
  printf '  ↷ no bash < 4 on this machine to test the guard against\n'
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then printf '✓ smoke tests passed\n'; else printf '✖ smoke tests failed\n' >&2; fi
exit "$FAIL"
