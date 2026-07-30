#!/usr/bin/env bash
# shellcheck disable=SC2034  # identity vars and platform fields (HOST/API_VERSION/CLI) are consumed by lib/core.sh and the platform-*.sh libs
# common.sh — review-code specifics on top of the shared core.
# Sourced by every top-level script and by the platform-*.sh libs.
#
# Shared helpers (logging, global/project config readers, watermark/author resolution,
# .gitignore maintenance, command allowlist) live in <plugin-root>/lib/core.sh — edit
# them there, not here. This file adds: the comment marker/fingerprint scheme, platform
# + token + repo resolution, and platform dispatch.
#
# Config:
#   - Global  ~/.supensour/config/supensour.yaml   → platform catalog (default + platforms).
#   - Project <repo>/.supensour/config/config.yaml → per-repo hints to skip detection:
#       git.platform, git.token_env, git.base_branch, project.language.
# Platform precedence: --platform flag > project git.platform > global `default` > auto-detect.
# Token precedence:    project git.token_env > platform token_env > token_env_alternatives.
#
# Logging goes to STDERR so STDOUT stays clean for machine-readable output.

# --- Marker & watermark -----------------------------------------------------
# Hidden HTML-comment marker embedded in every comment/summary this skill posts.
# Used to identify our own prior comments on a PR/MR so a re-run can reconcile
# (dedup / update-in-place / resolve-when-fixed) them — never delete them.
#
# Marker carries two ids so a later run can act without re-deleting:
#   fp  finding fingerprint  — stable identity of a finding (file+dimension+title),
#                             line-independent so a moved finding still matches.
#   h   body content hash    — changes only when the finding wording/fix changes,
#                             so an unchanged finding is skipped, a changed one updated.
# Summary comment uses fp=summary.
MARKER_PREFIX="supensour:review-code"
# Legacy plain marker (pre-fp). Kept so old comments are still recognized as ours
# and never treated as a stranger's comment. Matching uses the prefix, not this exact string.
MARKER="<!-- ${MARKER_PREFIX} -->"

# Visible attribution watermark. Configurable via <repo-root>/supensour-config.yaml
# (`watermark_template` + `watermark_url`, or per-skill `skills.review-code.*`).
# Placeholder {skillName} → "supensour:review-code". Two rendered forms are set at
# end of file: WATERMARK (plain, for console) and WATERMARK_MD ({skillName} as a
# markdown link to watermark_url, for the .md report + PR/MR comments).
SKILL_KEY="review-code"
SKILL_NAME="supensour:review-code"
WATERMARK_DEFAULT="Reviewed with skill {skillName} · suprayan@supensour · github.com/supensour/supensour-agent"
WATERMARK_URL_DEFAULT="https://github.com/supensour/supensour-agent"
AUTHOR_DEFAULT="supensour-agent@review-code"

# 12-char content hash. Portable across macOS (shasum), Linux (sha1sum or shasum) and
# Git Bash (shasum). Resolve the binary FIRST: an `A && A-run || B-run` chain would run
# B after A had already consumed stdin, silently producing an empty hash — i.e. a wrong
# comment fingerprint, which means duplicate PR comments.
_sha_cmd() {
  local c
  for c in shasum sha1sum sha1; do
    command -v "$c" >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }
  done
  return 1
}
_hash12() {
  local sha out
  sha="$(_sha_cmd)" || die "No SHA-1 tool found (shasum / sha1sum). Install one: $(_install_hint shasum)"
  out="$("$sha" <<<"$1")"
  printf '%s' "${out%% *}" | cut -c1-12
}

# finding_fp <file> <dimension> <title> → stable, line-independent finding id.
finding_fp() { _hash12 "$1"$'\n'"$2"$'\n'"$3"; }

# marker_line <fp> <body-hash> → hidden HTML-comment marker for one comment.
marker_line() { printf '<!-- %s fp=%s h=%s -->' "$MARKER_PREFIX" "$1" "$2"; }

# decorate_body <body> → body + blank line + visible watermark + hidden marker.
# The marker's fp comes from $FP (set by the caller; defaults to "summary"); the
# body hash is computed here over the raw body (excludes watermark/marker), so the
# same finding hashes identically across runs and reconcile can skip it unchanged.
# Posted comments render markdown, so use the linked form (WATERMARK_MD).
decorate_body() {
  local body="$1" fp="${FP:-summary}" h
  h="$(_hash12 "$body")"
  printf '%s\n\n🤖 %s\n%s' "$body" "$WATERMARK_MD" "$(marker_line "$fp" "$h")"
}

# watermark_banner — one-line console attribution to stderr (call once per run).
# Console is plain text → use WATERMARK (no markdown link).
watermark_banner() { printf '🤖 %s\n' "$WATERMARK" >&2; }

# --- Paths ------------------------------------------------------------------
# SKILL_DIR = skills/review-code (parent of scripts/). Resolved from this file.
_COMMON_SRC="${BASH_SOURCE[0]}"
LIB_DIR="$(cd "$(dirname "$_COMMON_SRC")" && pwd)"
SCRIPTS_DIR="$(cd "$LIB_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
export SKILL_DIR SCRIPTS_DIR LIB_DIR MARKER MARKER_PREFIX

# --- Shared core ------------------------------------------------------------
# Provides: log/warn/die, _clean_val, cfg_* / proj_* readers, ensure_project_config,
# ensure_gitignore, watermark resolution (resolve_attribution), run_checked.
_CORE="$SKILL_DIR/../../lib/core.sh"
[ -f "$_CORE" ] || { printf '✖ Missing shared lib: %s (incomplete install of the supensour plugin)\n' "$_CORE" >&2; exit 1; }
# shellcheck disable=SC1090
. "$_CORE"

# Split a curl response captured with `-w '\n%{http_code}'`:
#   _body → everything except the final line; _code → the final line (HTTP status).
_body() { sed '$d'; }
_code() { tail -n1; }

# Config readers come from lib/core.sh:
#   cfg_file / cfg_default / cfg_field / cfg_list  → ~/.supensour/config/supensour.yaml
#     platform:
#       default: <key>
#       platforms:
#         <key>:                       # 4-space indent
#           type: ...                  # 6-space indent
#           token_env_alternatives:
#             - X                      # 8-space indent
#   proj_cfg_file / proj_get                       → <repo>/.supensour/config/config.yaml

# --- Platform resolution ----------------------------------------------------
# init_platform [override-key]
# Sets: PLATFORM_KEY PLATFORM_TYPE HOST API_VERSION TOKEN_ENV CLI TOKEN
#       OWNER REPO WORKSPACE PROJECT_PATH PROJ_BASE_BRANCH PROJ_LANGUAGE
# and sources the matching platform-<type>.sh.
init_platform() {
  local override="${1:-}"
  # Every platform lib parses API JSON with jq. Fail here with an install hint rather
  # than `jq: command not found` from inside a request, possibly after a worktree exists.
  require_cmd jq curl
  # Per-repo hints (skip detection).
  PROJ_LANGUAGE="$(proj_get project language 2>/dev/null || true)"
  PROJ_BASE_BRANCH="$(proj_get git base_branch 2>/dev/null || true)"
  local proj_platform proj_token_env
  proj_platform="$(proj_get git platform 2>/dev/null || true)"
  proj_token_env="$(proj_get git token_env 2>/dev/null || true)"

  # Platform key: --platform flag > project git.platform > global default.
  PLATFORM_KEY="$override"
  [ -z "$PLATFORM_KEY" ] && PLATFORM_KEY="$proj_platform"
  [ -z "$PLATFORM_KEY" ] && PLATFORM_KEY="$(cfg_default 2>/dev/null || true)"

  if [ -n "$PLATFORM_KEY" ] && cfg_file >/dev/null 2>&1; then
    PLATFORM_TYPE="$(cfg_field "$PLATFORM_KEY" type)"
    HOST="$(cfg_field "$PLATFORM_KEY" host)"
    API_VERSION="$(cfg_field "$PLATFORM_KEY" api_version)"
    TOKEN_ENV="$(cfg_field "$PLATFORM_KEY" token_env)"
    CLI="$(cfg_field "$PLATFORM_KEY" cli)"
  fi

  # Fall back to auto-detect from the remote URL when type still unknown.
  [ -z "${PLATFORM_TYPE:-}" ] && PLATFORM_TYPE="$(_autodetect_type)"
  [ -z "${PLATFORM_TYPE:-}" ] && die "Cannot resolve platform. Set --platform, configure ~/.supensour/config/supensour.yaml, or add .supensour/config/config.yaml."

  # Project git.token_env overrides the platform's token_env for this repo.
  [ -n "$proj_token_env" ] && TOKEN_ENV="$proj_token_env"

  _resolve_token
  _resolve_repo_info
  export PROJ_LANGUAGE PROJ_BASE_BRANCH

  local lib="$LIB_DIR/platform-${PLATFORM_TYPE}.sh"
  [ -f "$lib" ] || die "No platform lib for type '$PLATFORM_TYPE' ($lib). Add it to extend support."
  # shellcheck disable=SC1090
  . "$lib"
}

_autodetect_type() {
  local url host
  url="$(git remote get-url origin 2>/dev/null || true)"
  [ -z "$url" ] && return 0
  host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://##; s#^[^@]+@##; s#[:/].*$##')"
  case "$host" in
    *github.*)    printf 'github' ;;
    *gitlab.*)    printf 'gitlab' ;;
    *bitbucket.*) printf 'bitbucket' ;;
    *) : ;;
  esac
}

_resolve_token() {
  TOKEN=""
  if [ -n "${TOKEN_ENV:-}" ]; then
    TOKEN="${!TOKEN_ENV:-}"
    [ -n "$TOKEN" ] && return 0
  fi
  # Try token_env_alternatives (block list in the global catalog).
  local a
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    if [ -n "${!a:-}" ]; then TOKEN="${!a}"; TOKEN_ENV="$a"; return 0; fi
  done < <(cfg_list "$PLATFORM_KEY" token_env_alternatives 2>/dev/null || true)
}

# Parse owner/repo/workspace + URL-encoded project path from the origin remote.
_resolve_repo_info() {
  local url path
  url="$(git remote get-url origin 2>/dev/null || true)"
  path="$(printf '%s' "$url" | sed -E 's#(\.git)?$##; s#^[a-z]+://[^/]+/##; s#^[^:]+:##')"
  OWNER="$(printf '%s' "$path" | sed -E 's#/[^/]+$##')"
  REPO="$(printf '%s' "$path" | sed -E 's#.*/##')"
  WORKSPACE="$(printf '%s' "$path" | sed -E 's#/.*$##')"
  PROJECT_PATH="$(printf '%s' "$path" | sed 's#/#%2F#g')"   # GitLab needs URL-encoded path
  export OWNER REPO WORKSPACE PROJECT_PATH
}

# platform_dispatch <fn-suffix> [args...] → calls <type>_<fn-suffix>.
# e.g. platform_dispatch fetch_pr "$SRC" → github_fetch_pr "$SRC"
platform_dispatch() {
  local fn="${PLATFORM_TYPE}_$1"; shift
  if ! declare -F "$fn" >/dev/null; then
    die "Platform '$PLATFORM_TYPE' does not implement '$fn'."
  fi
  "$fn" "$@"
}

# require_token — guard for push/reconcile ops; warns + returns 1 if no token.
require_token() {
  if [ -z "${TOKEN:-}" ]; then
    warn "No token in \$${TOKEN_ENV:-<token_env>}. Set it to push/reconcile comments; keeping local review only."
    return 1
  fi
  return 0
}

# --- Config scaffolding (create-if-missing) ---------------------------------
_remote_host() { git remote get-url origin 2>/dev/null | sed -E 's#^[a-z]+://##; s#^[^@]+@##; s#[:/].*$##'; }
_token_env_for_type() {
  case "$1" in gitlab) printf 'GITLAB_TOKEN' ;; bitbucket) printf 'BITBUCKET_TOKEN' ;; *) printf 'GITHUB_TOKEN' ;; esac
}

# ensure_global_config — create ~/.supensour/config/supensour.yaml if absent (prefilled from the remote).
ensure_global_config() {
  local f="$HOME/.supensour/config/supensour.yaml"
  [ -f "$f" ] && return 0
  local type host key tenv
  type="$(_autodetect_type)"; [ -z "$type" ] && type="github"
  host="$(_remote_host)"; if [ -n "$host" ]; then host="https://$host"; else host="https://github.com"; fi
  key="$type"; tenv="$(_token_env_for_type "$type")"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
# yaml-language-server: \$schema=https://raw.githubusercontent.com/supensour/supensour-agent/master/schemas/global-config.schema.json
# Supensour global platform catalog — review host + token_env for your setup.
platform:
  default: $key
  platforms:
    $key:
      type: $type
      host: $host
      token_env: $tenv
EOF
  log "📝 Created $f — review host + token_env."
}

# ensure_project_config / project_config_template live in lib/core.sh (shared template).

# --- Attribution ------------------------------------------------------------
# Sets WATERMARK (plain, console) and WATERMARK_MD ({skillName} as a markdown link,
# used in the .md report + PR/MR comments) from supensour-config.yaml, plus AUTHOR_TEXT.
resolve_attribution
