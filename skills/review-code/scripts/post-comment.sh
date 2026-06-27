#!/usr/bin/env bash
# post-comment.sh <mode> ...   — post review output to a PR/MR.
#
#   summary <PR> <body-file> [--platform K] [--head SHA]
#       Post the top-level review summary. Prints the comment URL/id.
#
#   inline  <PR> <path> <line> <body-file> [--platform K] [--head SHA]
#       Post an inline finding with fallback chain:
#         line  → file-level (top of file) → top-level summary comment.
#       Prints the level actually used: line | file | summary | failed.
#
# Body is read from a file (findings contain multi-line diff blocks). A hidden
# marker is appended by the platform lib so the comment can be pruned later.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MODE="${1:-}"; shift || true
OVERRIDE=""; HEAD_SHA="${HEAD_SHA:-}"
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) OVERRIDE="$2"; shift 2 ;;
    --head)     HEAD_SHA="$2"; shift 2 ;;
    *) POS+=("$1"); shift ;;
  esac
done
export HEAD_SHA

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
    if platform_dispatch post_inline "$PR" "$PATH_" "$LINE" "$BODY"; then
      echo line
    elif platform_dispatch post_file "$PR" "$PATH_" "$BODY"; then
      warn "Line $PATH_:$LINE not commentable — posted as file-level comment."
      echo file
    elif platform_dispatch post_summary "$PR" "$BODY"; then
      warn "Inline + file-level failed for $PATH_:$LINE — posted to top-level summary."
      echo summary
    else
      warn "Failed to post comment for $PATH_:$LINE."
      echo failed
    fi
    ;;
  *)
    die "post-comment.sh: unknown mode '$MODE' (summary|inline)"
    ;;
esac
