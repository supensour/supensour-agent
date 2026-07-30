#!/usr/bin/env bash
# explain.sh [--branch <SRC>] [--base <branch>] [--platform <key>] [--pool <n>]
# Everything `--explain` can resolve WITHOUT network, subagents or writes. Prints
# `<section>\t<key>\t<value>` TSV; the orchestrator renders it and adds what only it
# knows (PR/MR, models, changed-file list).
#
# Sections: deps · platform · git · commands · pool
# Nothing here mutates the repo — no config scaffolding, no worktree, no .gitignore.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SRC="" BASE="" OVERRIDE="" POOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)   SRC="${2:-}"; shift 2 ;;
    --base)     BASE="${2:-}"; shift 2 ;;
    --platform) OVERRIDE="${2:-}"; shift 2 ;;
    --pool)     POOL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

# --- deps (never fatal: a missing tool is the most useful thing to report) ----
while IFS=$'\t' read -r cmd status detail; do
  [ -z "$cmd" ] && continue
  row deps "$cmd" "$status${detail:+ — $detail}"
done < <(bash "$SCRIPTS_DIR/deps.sh" || true)

# --- git ---------------------------------------------------------------------
[ -z "$SRC" ] && SRC="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
row git branch "$SRC"
row git head "$(git rev-parse --short HEAD 2>/dev/null || echo '-')"
dirty=clean; [ -n "$(git status --porcelain 2>/dev/null)" ] && dirty=dirty
row git worktree_needed "$( [ "$dirty" = dirty ] && echo "yes (tree $dirty)" || echo no )"
[ -z "$BASE" ] && BASE="$(proj_get git base_branch 2>/dev/null || true)"
row git base "${BASE:-<from PR/MR or repo default>}"

# --- platform (config only — no API call, so no token is spent here) ---------
key="$OVERRIDE"
[ -z "$key" ] && key="$(proj_get git platform 2>/dev/null || true)"
[ -z "$key" ] && key="$(cfg_default 2>/dev/null || true)"
row platform key "${key:-<auto-detect from remote>}"
if [ -n "$key" ]; then
  row platform type "$(cfg_field "$key" type 2>/dev/null || echo '-')"
  row platform host "$(cfg_field "$key" host 2>/dev/null || echo '-')"
  tenv="$(proj_get git token_env 2>/dev/null || true)"
  [ -z "$tenv" ] && tenv="$(cfg_field "$key" token_env 2>/dev/null || true)"
  row platform token_env "${tenv:-<none>}"
  row platform token_present "$( [ -n "${tenv:-}" ] && [ -n "${!tenv:-}" ] && echo yes || echo no )"
fi

# --- commands (same resolution Step 3 will use) ------------------------------
tool="$(detect_build_tool || true)"
row commands build_tool "${tool:-<none recognized>}"
while IFS=$'\t' read -r step cmd _ _; do
  [ -z "$step" ] && continue
  row commands "$step" "$cmd"
done < <(bash "$SCRIPTS_DIR/verify.sh" --print 2>/dev/null || true)

# --- pool --------------------------------------------------------------------
cores="$(cpu_cores)"
def=$(( cores * 30 / 100 )); [ "$def" -lt 1 ] && def=1; [ "$def" -gt 8 ] && def=8
row pool cores "$cores"
row pool size "${POOL:-$def}${POOL:+ (--pool)}"
