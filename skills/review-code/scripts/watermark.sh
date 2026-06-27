#!/usr/bin/env bash
# watermark.sh [--banner]
# Prints the resolved watermark text (configurable via <repo-root>/supensour-config.yaml).
#   (default)  → the watermark line (for the report footer / embedding).
#   --banner   → console form prefixed with 🤖 (final user-facing line of a run).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

case "${1:-}" in
  --banner) printf '🤖 %s\n' "$WATERMARK" ;;
  *)        printf '%s\n' "$WATERMARK" ;;
esac
