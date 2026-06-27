#!/usr/bin/env bash
# watermark.sh [--banner|--plain]
# Prints the resolved watermark text (configurable via <repo-root>/supensour-config.yaml).
#   (default)  → markdown form, {skillName} linked to watermark_url (report footer / .md embedding).
#   --banner   → plain console form prefixed with 🤖 (final user-facing line of a run).
#   --plain    → plain form, no markdown link, no 🤖 prefix.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

case "${1:-}" in
  --banner) printf '🤖 %s\n' "$WATERMARK" ;;
  --plain)  printf '%s\n' "$WATERMARK" ;;
  *)        printf '%s\n' "$WATERMARK_MD" ;;
esac
