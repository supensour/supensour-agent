#!/usr/bin/env bash
# init-config.sh
# Creates any missing supensour config from a template. Idempotent — never
# overwrites an existing file. Run at the start of a review.
#   - global  ~/.supensour/config/supensour.yaml      (platform catalog, prefilled from remote)
#   - project <repo>/.supensour/config/config.yaml (commented per-repo hints)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ensure_global_config
ensure_project_config
