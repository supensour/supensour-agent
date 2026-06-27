#!/usr/bin/env bash
# common.sh — shared helpers for review-code scripts.
# Sourced by every top-level script and by the platform-*.sh libs.
# Responsibilities: locate the skill dir, load config (global supensour.yaml +
# project .supensour/config/config.yaml), resolve the platform + token + repo
# identity, and dispatch to the matched platform lib.
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
# Used to identify (and prune) our own prior comments on a PR/MR.
MARKER="<!-- supensour:review-code -->"

# Visible attribution watermark. Configurable via <repo-root>/supensour-config.yaml
# (`watermark_template`, or per-skill `skills.review-code.watermark_template`).
# Placeholder {skillName} → "supensour:review-code". WATERMARK is set at end of file.
SKILL_NAME="supensour:review-code"
WATERMARK_DEFAULT="Generated with {skillName} · suprayan@supensour · github.com/supensour/supensour-agent"

# decorate_body <body> → body + blank line + visible watermark + hidden prune marker.
# Every posted comment/summary body goes through this so attribution is automatic and
# the prune marker is always present (delete_prior matches on $MARKER).
decorate_body() { printf '%s\n\n🤖 %s\n%s' "$1" "$WATERMARK" "$MARKER"; }

# watermark_banner — one-line console attribution to stderr (call once per run).
watermark_banner() { printf '🤖 %s\n' "$WATERMARK" >&2; }

# --- Paths ------------------------------------------------------------------
# SKILL_DIR = skills/review-code (parent of scripts/). Resolved from this file.
_COMMON_SRC="${BASH_SOURCE[0]}"
LIB_DIR="$(cd "$(dirname "$_COMMON_SRC")" && pwd)"
SCRIPTS_DIR="$(cd "$LIB_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
export SKILL_DIR SCRIPTS_DIR LIB_DIR MARKER WATERMARK

# --- Logging ----------------------------------------------------------------
log()  { printf '%s\n' "$*" >&2; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die()  { printf '✖ %s\n' "$*" >&2; exit 1; }

# Split a curl response captured with `-w '\n%{http_code}'`:
#   _body → everything except the final line; _code → the final line (HTTP status).
_body() { sed '$d'; }
_code() { tail -n1; }

# --- Config files -----------------------------------------------------------
# Global: ~/.supensour/config/supensour.yaml (AI-agnostic, not Claude-specific).
cfg_file() {
  [ -f "$HOME/.supensour/config/supensour.yaml" ] && { printf '%s' "$HOME/.supensour/config/supensour.yaml"; return 0; }
  return 1
}

# Project: <repo-root>/.supensour/config/config.yaml  (nested git:/project: schema).
proj_cfg_file() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] && [ -f "$root/.supensour/config/config.yaml" ] && {
    printf '%s' "$root/.supensour/config/config.yaml"; return 0; }
  return 1
}

# Trim a scalar YAML value: drop a trailing ` # comment`, surrounding quotes, and whitespace.
_clean_val() {
  sed -E 's/[[:space:]]+#.*$//; s/\r//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'"'"']//; s/["'"'"']$//'
}

# Global config is nested under a top-level `platform:` key:
#   platform:
#     default: <key>
#     platforms:
#       <key>:                       # 4-space indent
#         type: ...                  # 6-space indent
#         token_env_alternatives:
#           - X                      # 8-space indent

# `platform.default` key.
cfg_default() {
  local f; f="$(cfg_file)" || return 1
  awk '/^  default:/{sub(/^  default:/,""); print; exit}' "$f" | _clean_val
}

# cfg_field <platform-key> <field> — scalar field inside platform.platforms.<key>.
cfg_field() {
  local f key="$1" field="$2"; f="$(cfg_file)" || return 1
  awk -v key="$key" -v field="$field" '
    $0 ~ "^    " key ":[[:space:]]*$" { inblk=1; next }
    inblk && /^    [^[:space:]]/      { inblk=0 }
    inblk && $0 ~ "^      " field ":" {
      sub("^      " field ":", "")
      print; exit
    }
  ' "$f" | _clean_val
}

# cfg_list <platform-key> <field> — block-list values (`- item`) inside platform.platforms.<key>.
cfg_list() {
  local f key="$1" field="$2"; f="$(cfg_file)" || return 1
  awk -v key="$key" -v field="$field" '
    $0 ~ "^    " key ":[[:space:]]*$" { inblk=1; next }
    inblk && /^    [^[:space:]]/      { inblk=0 }
    inblk && $0 ~ "^      " field ":"  { inlist=1; next }
    inlist && /^        - /            { sub(/^        - /,""); print; next }
    inlist && /^      [^[:space:]-]/   { inlist=0 }
  ' "$f" | _clean_val
}

# proj_get <section> <field> — scalar from project config (section = git|project).
# Empty (rc 1) if no project config or field absent.
proj_get() {
  local f section="$1" field="$2"; f="$(proj_cfg_file)" || return 1
  awk -v section="$section" -v field="$field" '
    $0 ~ "^" section ":[[:space:]]*$" { inblk=1; next }
    inblk && /^[^[:space:]]/          { inblk=0 }
    inblk && $0 ~ "^  " field ":" {
      sub("^  " field ":", "")
      print; exit
    }
  ' "$f" | _clean_val
}

# --- Platform resolution ----------------------------------------------------
# init_platform [override-key]
# Sets: PLATFORM_KEY PLATFORM_TYPE HOST API_VERSION TOKEN_ENV CLI TOKEN
#       OWNER REPO WORKSPACE PROJECT_PATH PROJ_BASE_BRANCH PROJ_LANGUAGE
# and sources the matching platform-<type>.sh.
init_platform() {
  local override="${1:-}"
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

# require_token — guard for push/prune ops; warns + returns 1 if no token.
require_token() {
  if [ -z "${TOKEN:-}" ]; then
    warn "No token in \$${TOKEN_ENV:-<token_env>}. Set it to push/prune comments; keeping local review only."
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

# ensure_project_config — create <repo>/.supensour/config/config.yaml if absent (commented hints).
ensure_project_config() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -z "$root" ] && return 0
  local f="$root/.supensour/config/config.yaml"
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<'EOF'
# yaml-language-server: $schema=https://raw.githubusercontent.com/supensour/supensour-agent/master/schemas/project-config.schema.json
# Supensour per-repo hints (optional). Uncomment + set to skip detection.
git:
  # platform: gitlab-ce          # key into ~/.supensour/config/supensour.yaml platforms
  # token_env: GITLAB_TOKEN      # override the platform's token_env for this repo
  # base_branch: develop         # default diff base
project:
  # language: vue                # default --lang (review-code / create-tests)
  # test_type: unit              # default --type (create-tests)
EOF
  log "📝 Created $f — uncomment hints as needed."
}

# --- Watermark resolution ---------------------------------------------------
# Repo config: <repo-root>/supensour-config.yaml (sits two levels above SKILL_DIR).
wm_cfg_file() {
  local f="$SKILL_DIR/../../supensour-config.yaml"
  [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  return 1
}
# Top-level `watermark_template:` scalar.
_wm_top() {
  local f; f="$(wm_cfg_file)" || return 1
  awk '/^watermark_template:/{sub(/^watermark_template:/,""); print; exit}' "$f" | _clean_val
}
# Per-skill `skills.<skill>.watermark_template`.
_wm_skill() {
  local f skill="$1"; f="$(wm_cfg_file)" || return 1
  awk -v s="$skill" '
    /^skills:[[:space:]]*$/        { ins=1; next }
    ins && /^[^[:space:]]/         { ins=0 }
    ins && $0 ~ "^  " s ":[[:space:]]*$" { inb=1; next }
    inb && /^  [^[:space:]]/       { inb=0 }
    inb && /^    watermark_template:/ { sub(/^    watermark_template:/,""); print; exit }
  ' "$f" | _clean_val
}
# resolve_watermark — per-skill template > top-level > built-in default, with {skillName} substituted.
resolve_watermark() {
  local t; t="$(_wm_skill review-code 2>/dev/null || true)"
  [ -z "$t" ] && t="$(_wm_top 2>/dev/null || true)"
  [ -z "$t" ] && t="$WATERMARK_DEFAULT"
  printf '%s' "${t//\{skillName\}/$SKILL_NAME}"
}
WATERMARK="$(resolve_watermark)"
export WATERMARK SKILL_NAME
