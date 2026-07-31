#!/usr/bin/env bash
# run-tests.sh <lang> <spec-or-class> [--coverage <source-file>] [--budget <n>] [--reset]
#
# The ONE way a spec is run during generation — the plan's `Run:` line is this command —
# because this is also where the run budget is enforced.
#
# Why a budget: each role only sees its own cap (writer: 2 runs; analyst: n dispatches),
# so the per-target total was unbounded in practice — observed >5 full test+coverage
# cycles for a single file. The ledger below is shared, so the cap is real.
#
#   vue:        run-tests.sh vue <spec-file> [--coverage <source-file>]
#   springboot: run-tests.sh springboot <ClassName|source-file>
#   --budget <n>  max runs for this target (default $CT_RUN_BUDGET, else 4)
#   --reset       clear this target's ledger, then run
#   --reset-only  clear the ledger and exit 0 without running — how an analyst starts a
#                 target, so opening the books doesn't itself cost a run
#
# Ledger: <repo>/.supensour/create-tests/<branch>/.runs/<target>.count — scratch for one
# branch's generation pass, pruned by clean.sh along with the plans.
#
# Exit codes: the runner's own exit code · 5 = budget exhausted, nothing was run.
# On 5 the caller must report what it already knows, never "just once more".
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

LANG="${1:-}"; TARGET="${2:-}"
[ -n "$LANG" ] && [ -n "$TARGET" ] \
  || die "usage: run-tests.sh <lang> <spec-or-class> [--coverage <source>] [--budget <n>] [--reset]"
shift 2 || true

COVERAGE_SRC="" BUDGET="${CT_RUN_BUDGET:-4}" RESET=0 RESET_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --coverage) COVERAGE_SRC="$2"; shift 2 ;;
    --budget)   BUDGET="$2"; shift 2 ;;
    --reset)      RESET=1; shift ;;
    --reset-only) RESET=1; RESET_ONLY=1; shift ;;
    *) shift ;;
  esac
done
case "$BUDGET" in ''|*[!0-9]*) die "run-tests.sh: --budget must be a number, got '$BUDGET'" ;; esac

# --- run ledger --------------------------------------------------------------
LEDGER=""
ROOT="$(repo_root)"
if [ -n "$ROOT" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -n "$BRANCH" ] && [ "$BRANCH" != HEAD ]; then
    SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr '/' '-')"
    SAFE_TARGET="$(printf '%s' "${TARGET#/}" | tr '/' '-')"
    LEDGER="$ROOT/.supensour/create-tests/$SAFE_BRANCH/.runs/$SAFE_TARGET.count"
    mkdir -p "$(dirname "$LEDGER")"
    ensure_gitignore '.supensour/create-tests/'
  fi
fi

if [ -n "$LEDGER" ]; then
  [ "$RESET" -eq 1 ] && rm -f "$LEDGER"
  if [ "$RESET_ONLY" -eq 1 ]; then
    log "↺ run ledger cleared for $TARGET (budget $BUDGET)"
    exit 0
  fi
  used=0
  [ -f "$LEDGER" ] && used="$(tr -dc '0-9' < "$LEDGER")"
  case "$used" in '') used=0 ;; esac

  if [ "$used" -ge "$BUDGET" ]; then
    printf '✖ Run budget exhausted for %s — %d of %d runs used, nothing was run.\n' \
      "$TARGET" "$used" "$BUDGET" >&2
    printf '     Report what you already know instead of running again: PASS if the last run was green,\n' >&2
    printf '     PARTIAL if tests pass but a metric cannot reach the threshold, FAIL otherwise.\n' >&2
    printf '     Raise it deliberately with --runs <n> (skill flag) or CT_RUN_BUDGET=<n> (env).\n' >&2
    exit 5
  fi
  used=$((used + 1))
  printf '%s' "$used" > "$LEDGER"
  log "▶ run $used/$BUDGET — $TARGET"
else
  [ "$RESET_ONLY" -eq 1 ] && exit 0
  warn "No branch resolved — running without a budget ledger."
fi

load_lang "$LANG"
lang_dispatch run_tests "$TARGET" ${COVERAGE_SRC:+"$COVERAGE_SRC"}
