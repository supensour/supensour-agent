#!/usr/bin/env bash
# detect-platform.sh [--platform <key>]
# Resolves the active platform and prints it as one JSON line:
#   {"type","key","host","cli","token_env","token_present","owner","repo",
#    "workspace","project_path","base_branch","language"}
# base_branch + language come from the per-repo .supensour/config/config.yaml hints
# (empty when not set). Logging/warnings go to stderr; stdout is the JSON only.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) OVERRIDE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

init_platform "$OVERRIDE"

jq -nc \
  --arg type "$PLATFORM_TYPE" \
  --arg key "${PLATFORM_KEY:-}" \
  --arg host "${HOST:-}" \
  --arg cli "${CLI:-}" \
  --arg token_env "${TOKEN_ENV:-}" \
  --argjson token_present "$( [ -n "${TOKEN:-}" ] && echo true || echo false )" \
  --arg owner "${OWNER:-}" \
  --arg repo "${REPO:-}" \
  --arg workspace "${WORKSPACE:-}" \
  --arg project_path "${PROJECT_PATH:-}" \
  --arg base_branch "${PROJ_BASE_BRANCH:-}" \
  --arg language "${PROJ_LANGUAGE:-}" \
  '{type:$type, key:$key, host:$host, cli:$cli, token_env:$token_env, token_present:$token_present, owner:$owner, repo:$repo, workspace:$workspace, project_path:$project_path, base_branch:$base_branch, language:$language}'
