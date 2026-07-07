#!/usr/bin/env bash
# post-comment.sh <mode> ...   — post review output to a PR/MR.
#
#   summary <PR> <body-file> [--platform K] [--head SHA]
#       Post the top-level review summary. Prints the comment URL/id.
#
#   inline  <PR> <path> <line> <body-file> [--platform K] [--head SHA] [--fp ID]
#       Post an inline finding with fallback chain:
#         line → file-level (top of file) → standalone comment.
#       The last tier is its OWN separate normal comment (used when the line can't be
#       found / is outside the diff context) — NOT merged into the aggregated summary
#       comment. Prints the level actually used: line | file | comment | failed.
#
# Body is read from a file (findings contain multi-line diff blocks). A hidden
# marker (with the finding fingerprint from --fp / $FP) is appended by the platform lib
# so a later run can reconcile the comment — dedup / update / resolve — never delete.
# Pass --fp for a finding so its fallback comment is tracked separately from the summary
# (default "summary"). For a full review push use reconcile-comments.sh.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MODE="${1:-}"; shift || true
OVERRIDE=""; HEAD_SHA="${HEAD_SHA:-}"
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) OVERRIDE="$2"; shift 2 ;;
    --head)     HEAD_SHA="$2"; shift 2 ;;
    --fp)       FP="$2"; shift 2 ;;
    *) POS+=("$1"); shift ;;
  esac
done
export HEAD_SHA FP

init_platform "$OVERRIDE"
require_token || { echo failed; exit 0; }

case "$MODE" in
  summary)
    PR="${POS[0]:?summary <PR> <body-file>}"; BODYFILE="${POS[1]:?body-file required}"
    BODY="$(cat "$BODYFILE")"
    platform_dispatch post_summary "$PR" "$BODY"
    ;;
  inline)
    PR="${POS[0]:?inline <PR> <path> <line> <body-file>}"
    PATH_="${POS[1]:?path required}"; LINE="${POS[2]:?line required}"; BODYFILE="${POS[3]:?body-file required}"
    BODY="$(cat "$BODYFILE")"
    # line → file-level → standalone comment. The finding is NEVER merged into the
    # aggregated summary comment; the last tier is its own separate normal comment,
    # used when the line can't be found / is outside the diff context.
    if platform_dispatch post_inline "$PR" "$PATH_" "$LINE" "$BODY"; then
      echo line
    elif platform_dispatch post_file "$PR" "$PATH_" "$BODY"; then
      warn "Line $PATH_:$LINE not commentable — posted as file-level comment."
      echo file
    elif platform_dispatch post_summary "$PR" "$BODY" >/dev/null; then
      warn "Line $PATH_:$LINE not in diff — posted as a standalone comment."
      echo comment
    else
      warn "Failed to post $PATH_:$LINE by any method — kept in local report."
      echo failed
    fi
    ;;
  *)
    die "post-comment.sh: unknown mode '$MODE' (summary|inline)"
    ;;
esac
