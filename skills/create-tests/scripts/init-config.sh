#!/usr/bin/env bash
# init-config.sh
# Creates the per-repo config from a template if absent. Idempotent — never
# overwrites an existing file. create-tests uses only the project config
# (project.language, git.base_branch); the global platform catalog is review-code's.
#   - project <repo>/.supensour/config/config.yaml (commented per-repo hints)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ensure_project_config
