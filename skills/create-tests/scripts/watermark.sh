#!/usr/bin/env bash
# watermark.sh [--banner|--author]
# Prints values resolved from <repo-root>/supensour-config.yaml.
#   (default)  → the watermark line, for the generated-spec header comment.
#   --banner   → console form prefixed with 🤖 (final user-facing line of a run).
#   --author   → the attribution author (e.g. for a Java @author tag).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

case "${1:-}" in
  --banner) printf '🤖 %s\n' "$WATERMARK_TEXT" ;;
  --author) printf '%s\n' "$AUTHOR_TEXT" ;;
  *)        printf '%s\n' "$WATERMARK_TEXT" ;;
esac
