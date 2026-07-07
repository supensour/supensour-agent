#!/usr/bin/env bash
# reconcile-comments.sh <PR> <manifest.json> [--platform <key>] [--head <sha>]
#
# Posts a review to a PR/MR WITHOUT ever deleting comments. Given the full set of
# current findings (a manifest) it reconciles against this skill's prior comments:
#
#   • already commented, unchanged  → SKIP  (no duplicate post)
#   • already commented, changed     → UPDATE in place (edit the existing comment)
#   • new finding                    → POST (inline → file-level; never on the summary comment)
#   • prior finding now absent        → RESOLVE (issue fixed) — collapse/mark resolved
#
# Nothing is deleted. Prior comments are matched by the hidden marker's finding
# fingerprint (fp); "changed" is detected by the body hash (h). See lib/common.sh.
#
# Manifest JSON:
#   {
#     "summary":  { "body_file": "/path/to/summary.md" },
#     "findings": [
#       { "file":"src/a.ts", "line":42, "dimension":"Security",
#         "title":"SQL injection", "body_file":"/path/to/1.md" }, ...
#     ]
#   }
#
# Prints a one-line reconcile report:
#   ♻ Reconcile: 2 posted, 1 updated, 3 unchanged, 1 resolved (0 deleted)
# Auth/permission failure → warn and keep the local review (never aborts hard).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PR="" MANIFEST="" OVERRIDE="" HEAD_SHA="${HEAD_SHA:-}"
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) OVERRIDE="$2"; shift 2 ;;
    --head)     HEAD_SHA="$2"; shift 2 ;;
    *) POS+=("$1"); shift ;;
  esac
done
PR="${POS[0]:-}"; MANIFEST="${POS[1]:-}"
[ -n "$PR" ] || die "reconcile-comments.sh: <PR> required."
[ -n "$MANIFEST" ] && [ -f "$MANIFEST" ] || die "reconcile-comments.sh: <manifest.json> required and must exist."
export HEAD_SHA

init_platform "$OVERRIDE"
require_token || { echo "♻ Reconcile: skipped — no token (local review kept)."; exit 0; }
declare -F "${PLATFORM_TYPE}_list_prior" >/dev/null \
  || die "Platform '$PLATFORM_TYPE' has no reconcile support (list_prior). Extend platform-${PLATFORM_TYPE}.sh."

# _post_new <pr> <path> <line> <body> — post a brand-new finding with the fallback:
#   inline → file-level → standalone comment.
# The last tier is its OWN separate normal PR/MR comment (used when the line can't be
# found / is outside the diff context) — it is NOT merged into the aggregated summary
# comment. It still carries the finding's fingerprint ($FP) so reconcile tracks it.
# $FP must be set by the caller. Prints the level used to stderr. 0=posted.
_post_new() {
  local pr="$1" path="$2" line="$3" body="$4"
  if platform_dispatch post_inline "$pr" "$path" "$line" "$body"; then
    log "＋ posted     $path:$line (inline)"
  elif platform_dispatch post_file "$pr" "$path" "$body"; then
    log "＋ posted     $path:$line (file-level — line not commentable)"
  elif platform_dispatch post_summary "$pr" "$body" >/dev/null; then
    log "＋ posted     $path:$line (standalone comment — line not in diff)"
  else
    warn "Could not post $path:$line by any method — kept in local report."
    return 1
  fi
}

# --- Load prior comments (our own, by marker) -------------------------------
PRIOR="$(platform_dispatch list_prior "$PR" 2>/dev/null || printf '[]')"
[ -n "$PRIOR" ] || PRIOR='[]'

# Index prior by fp (first occurrence wins). Duplicates of a still-current fp are
# left as-is; duplicates of a fixed fp are resolved in the resolve pass below.
declare -A P_ID P_AUX P_KIND P_H
while IFS=$'\t' read -r pfp pid paux pkind ph; do
  [ -z "$pfp" ] && continue
  [ -n "${P_ID[$pfp]:-}" ] && continue
  P_ID["$pfp"]="$pid"; P_AUX["$pfp"]="$paux"; P_KIND["$pfp"]="$pkind"; P_H["$pfp"]="$ph"
done < <(printf '%s' "$PRIOR" | jq -r '.[]? | [.fp, (.id|tostring), (.aux|tostring), .kind, .h] | @tsv')

posted=0 updated=0 unchanged=0 resolved=0
declare -A CUR   # fp → 1 for every finding present this run (so we don't resolve them)

# --- Summary (fp = "summary") ------------------------------------------------
SUM_FILE="$(jq -r '.summary.body_file // empty' "$MANIFEST")"
if [ -n "$SUM_FILE" ] && [ -f "$SUM_FILE" ]; then
  CUR[summary]=1
  body="$(cat "$SUM_FILE")"; h="$(_hash12 "$body")"
  FP=summary
  if [ -n "${P_ID[summary]:-}" ] && [ "${P_H[summary]}" = "$h" ]; then
    unchanged=$((unchanged+1))
  elif [ -n "${P_ID[summary]:-}" ] && platform_dispatch update_comment "$PR" "${P_ID[summary]}" "${P_AUX[summary]}" "${P_KIND[summary]}" "$body"; then
    updated=$((updated+1))
  elif platform_dispatch post_summary "$PR" "$body" >/dev/null; then
    posted=$((posted+1))
  else
    warn "Summary post failed (local review kept)."
  fi
fi

# --- Findings ----------------------------------------------------------------
while IFS=$'\t' read -r file line dim title bodyfile; do
  if [ -z "$bodyfile" ] || [ ! -f "$bodyfile" ]; then
    warn "Skipping finding with missing body file: $file:$line"; continue
  fi
  fp="$(finding_fp "$file" "$dim" "$title")"
  CUR["$fp"]=1
  body="$(cat "$bodyfile")"; h="$(_hash12 "$body")"
  FP="$fp"
  if [ -n "${P_ID[$fp]:-}" ]; then
    if [ "${P_H[$fp]}" = "$h" ]; then
      unchanged=$((unchanged+1)); log "· unchanged  $file:$line"
    elif platform_dispatch update_comment "$PR" "${P_ID[$fp]}" "${P_AUX[$fp]}" "${P_KIND[$fp]}" "$body"; then
      updated=$((updated+1)); log "✎ updated    $file:$line"
    else
      warn "Update failed for $file:$line — leaving prior comment, posting fresh."
      _post_new "$PR" "$file" "$line" "$body" && posted=$((posted+1)) || true
    fi
  else
    _post_new "$PR" "$file" "$line" "$body" && posted=$((posted+1)) || true
  fi
done < <(jq -r '.findings[]? | [.file, (.line|tostring), .dimension, .title, .body_file] | @tsv' "$MANIFEST")

# --- Resolve prior findings no longer present (issue fixed) ------------------
# Iterate ALL prior entries; resolve any whose fp is absent from CUR. Never delete.
while IFS=$'\t' read -r pfp pid paux pkind; do
  if [ -z "$pfp" ] || [ "$pfp" = summary ]; then continue; fi   # keep legacy (empty) + summary
  if [ -n "${CUR[$pfp]:-}" ]; then continue; fi                 # still current → keep
  if platform_dispatch resolve_comment "$PR" "$pid" "$paux" "$pkind" 2>/dev/null; then
    resolved=$((resolved+1)); log "✅ resolved   fp=$pfp (no longer detected)"
  else
    warn "Could not resolve prior comment fp=$pfp (left in place, not deleted)."
  fi
done < <(printf '%s' "$PRIOR" | jq -r '.[]? | [.fp, (.id|tostring), (.aux|tostring), .kind] | @tsv')

printf '♻ Reconcile: %d posted, %d updated, %d unchanged, %d resolved (0 deleted)\n' \
  "$posted" "$updated" "$unchanged" "$resolved"
