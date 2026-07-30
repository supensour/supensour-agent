#!/usr/bin/env bash
# shellcheck disable=SC2034  # identity vars (SKILL_*/WATERMARK_*/AUTHOR_*) are consumed by lib/core.sh after sourcing
# common.sh — create-tests specifics on top of the shared core.
# Sourced by every top-level script and by the lang-*.sh libs.
#
# Shared helpers (logging, config readers, watermark/author resolution, .gitignore
# maintenance, command allowlist) live in <plugin-root>/lib/core.sh — edit them there,
# not here. This file adds: skill identity/defaults, language detection, lang dispatch.
#
# Logging goes to STDERR so STDOUT stays clean for machine-readable output.

# --- Paths ------------------------------------------------------------------
_COMMON_SRC="${BASH_SOURCE[0]}"
LIB_DIR="$(cd "$(dirname "$_COMMON_SRC")" && pwd)"
SCRIPTS_DIR="$(cd "$LIB_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
export SKILL_DIR SCRIPTS_DIR LIB_DIR

# --- Skill identity + attribution defaults ----------------------------------
# All overridable in <plugin-root>/supensour-config.yaml (top-level or
# skills.create-tests.*). {skillName} → SKILL_NAME.
SKILL_KEY="create-tests"
SKILL_NAME="supensour:create-tests"
WATERMARK_DEFAULT="Generated with skill {skillName} · suprayan@supensour · github.com/supensour/supensour-agent"
WATERMARK_URL_DEFAULT="https://github.com/supensour/supensour-agent"
AUTHOR_DEFAULT="supensour-agent@create-tests"

# --- Shared core ------------------------------------------------------------
_CORE="$SKILL_DIR/../../lib/core.sh"
[ -f "$_CORE" ] || { printf '✖ Missing shared lib: %s (incomplete install of the supensour plugin)\n' "$_CORE" >&2; exit 1; }
# shellcheck disable=SC1090
. "$_CORE"

resolve_attribution
# WATERMARK_TEXT kept as an alias — scripts/watermark.sh and the rules refer to it.
WATERMARK_TEXT="$WATERMARK"
export WATERMARK_TEXT

# --- Language detection -----------------------------------------------------
# detect_lang <path> → vue | springboot | "" (unknown). Extension-based; mirrors the
# review-code map minus config-only extensions (.xml carries no unit-testable code).
detect_lang() {
  case "$1" in
    *.vue|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) printf 'vue' ;;
    *.java|*.kt)                              printf 'springboot' ;;
    *) : ;;
  esac
}

# detect_lang_for_set <file...> → the dominant language across files (first match wins).
detect_lang_for_set() {
  local f l
  for f in "$@"; do l="$(detect_lang "$f")"; [ -n "$l" ] && { printf '%s' "$l"; return 0; }; done
  return 1
}

# --- Dispatch ---------------------------------------------------------------
# load_lang <lang> — source the matching lang-<lang>.sh.
load_lang() {
  local lang="$1" lib="$LIB_DIR/lang-${1}.sh"
  [ -n "$lang" ] || die "No language given/detected. Use --lang vue|springboot."
  [ -f "$lib" ] || die "No lang lib for '$lang' ($lib). Add it to extend support."
  # shellcheck disable=SC1090
  . "$lib"
  LANG_KEY="$lang"
}

# lang_dispatch <fn-suffix> [args...] → calls <lang>_<fn-suffix>.
# e.g. lang_dispatch run_tests <spec> <src> → vue_run_tests <spec> <src>
lang_dispatch() {
  local fn="${LANG_KEY}_$1"; shift
  if ! declare -F "$fn" >/dev/null; then
    die "Language '$LANG_KEY' does not implement '$fn'."
  fi
  "$fn" "$@"
}
