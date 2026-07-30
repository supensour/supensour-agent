#!/usr/bin/env bash
# core.sh — helpers shared by every supensour skill.
#
# Sourced by each skill's scripts/lib/common.sh, which sets these first:
#   SKILL_KEY              e.g. create-tests            (key in supensour-config.yaml → skills.<key>)
#   SKILL_NAME             e.g. supensour:create-tests  ({skillName} placeholder value)
#   WATERMARK_DEFAULT      built-in template, used when supensour-config.yaml is absent
#   WATERMARK_URL_DEFAULT  built-in link target for the markdown watermark form
#   AUTHOR_DEFAULT         built-in attribution author
# and which must define SKILL_DIR before sourcing (paths below resolve from it).
#
# After sourcing, resolve_attribution() sets: WATERMARK, WATERMARK_MD, AUTHOR_TEXT.
#
# Logging goes to STDERR so STDOUT stays clean for machine-readable output.
# Keep this file dependency-free (POSIX-ish bash + awk/sed) — it runs from any repo.

# --- Logging ----------------------------------------------------------------
log()  { printf '%s\n' "$*" >&2; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die()  { printf '✖ %s\n' "$*" >&2; exit 1; }

# --- Platform detection -----------------------------------------------------
# Supported everywhere bash runs: Linux, macOS, and Windows via Git Bash / WSL.
# os_kind → macos | debian | rhel | arch | alpine | linux | windows | unknown
# (WSL reports as its distro, which is correct — it *is* Linux.)
os_kind() {
  case "${OS:-}${MSYSTEM:-}" in
    *Windows_NT*|*MINGW*|*MSYS*) printf 'windows'; return ;;
  esac
  case "$(uname -s 2>/dev/null || true)" in
    Darwin)            printf 'macos'; return ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows'; return ;;
    Linux) : ;;
    *) printf 'unknown'; return ;;
  esac
  local id=""
  [ -r /etc/os-release ] && id="$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release)"
  case "$id" in
    debian|ubuntu|linuxmint|pop|raspbian) printf 'debian' ;;
    rhel|fedora|centos|rocky|almalinux|amzn) printf 'rhel' ;;
    arch|manjaro|endeavouros)             printf 'arch' ;;
    alpine)                                printf 'alpine' ;;
    *)                                     printf 'linux' ;;
  esac
}

# cpu_cores → usable core count on any supported OS (Windows exports
# NUMBER_OF_PROCESSORS but ships neither nproc nor sysctl outside MSYS coreutils).
cpu_cores() {
  local n=""
  n="$(nproc 2>/dev/null || true)"
  [ -z "$n" ] && n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  [ -z "$n" ] && n="${NUMBER_OF_PROCESSORS:-}"
  case "$n" in ''|*[!0-9]*) n=1 ;; esac
  printf '%s' "$n"
}

# --- External tool guards ---------------------------------------------------
# Scripts must fail with an actionable message, not `jq: command not found` from
# somewhere deep in a platform lib — by then a worktree may already exist.
#
# _install_hint <cmd> → how to install it on THIS machine (one command, not a menu).
_install_hint() {
  local cmd="$1" os; os="$(os_kind)"
  case "$os:$cmd" in
    macos:*)          printf 'brew install %s' "$cmd" ;;
    debian:*)         printf 'sudo apt-get install -y %s' "$cmd" ;;
    rhel:*)           printf 'sudo dnf install -y %s' "$cmd" ;;
    arch:*)           printf 'sudo pacman -S --needed %s' "$cmd" ;;
    alpine:*)         printf 'sudo apk add %s' "$cmd" ;;
    windows:jq)       printf 'winget install jqlang.jq  (or: scoop install jq · choco install jq)' ;;
    windows:node)     printf 'winget install OpenJS.NodeJS  (or: https://nodejs.org)' ;;
    windows:git|windows:curl) printf 'winget install Git.Git — Git for Windows ships bash + curl' ;;
    windows:gh)       printf 'winget install GitHub.cli' ;;
    windows:bash)     printf 'install Git for Windows (Git Bash) or enable WSL: wsl --install' ;;
    *:node)           printf 'https://nodejs.org' ;;
    *:gh)             printf 'https://cli.github.com' ;;
    *)                printf 'install %s with your package manager' "$cmd" ;;
  esac
}

# --- bash version floor -----------------------------------------------------
# This repo uses bash 4 features (associative arrays in the comment reconciler,
# `shopt -s globstar` in the glob expander). macOS still ships bash 3.2 as /bin/bash,
# where `declare -A` is rejected and `${map[$key]}` silently degrades to arithmetic
# indexing — i.e. wrong dedup, not a crash. Fail loudly here instead, in the file
# everything sources. Linux, WSL and Git Bash (4.4+) all satisfy it.
SUPENSOUR_BASH_MIN="${SUPENSOUR_BASH_MIN:-4}"
require_bash() {
  local want="${1:-$SUPENSOUR_BASH_MIN}" have="${BASH_VERSINFO[0]:-0}"
  [ "$have" -ge "$want" ] && return 0
  printf '✖ bash %s+ required, found %s (%s).\n' \
    "$want" "${BASH_VERSION:-unknown}" "${BASH:-bash}" >&2
  printf '     Install a newer bash: %s\n' "$(_install_hint bash)" >&2
  printf '     Then run the skill from that shell (macOS keeps 3.2 at /bin/bash for licensing reasons).\n' >&2
  exit 1
}
require_bash

# require_cmd <cmd>... — die on the first one missing, naming who needs it.
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 && continue
    die "Required command '$c' not found (needed by ${SKILL_NAME:-this skill}).
     Install: $(_install_hint "$c")"
  done
}

# deps_report <cmd>... — TSV `<cmd>\t<ok|MISSING>\t<path|install hint>` for --explain.
# Never fails: reporting a missing tool is the point.
deps_report() {
  local c p
  for c in "$@"; do
    if p="$(command -v "$c" 2>/dev/null)"; then
      printf '%s\tok\t%s\n' "$c" "$p"
    else
      printf '%s\tMISSING\t%s\n' "$c" "$(_install_hint "$c")"
    fi
  done
}

# --- YAML scalar helpers ----------------------------------------------------
# Trim a scalar YAML value: drop a trailing ` # comment`, surrounding quotes, whitespace.
_clean_val() {
  sed -E 's/[[:space:]]+#.*$//; s/\r//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'"'"']//; s/["'"'"']$//'
}

# --- Plugin paths -----------------------------------------------------------
# PLUGIN_ROOT = the plugin/repo root (two levels above a skill dir).
plugin_root() { (cd "$SKILL_DIR/../.." && pwd); }

# --- Global config: ~/.supensour/config/supensour.yaml (platform catalog) ---
cfg_file() {
  [ -f "$HOME/.supensour/config/supensour.yaml" ] && { printf '%s' "$HOME/.supensour/config/supensour.yaml"; return 0; }
  return 1
}

# `platform.default` key.
cfg_default() {
  local f; f="$(cfg_file)" || return 1
  awk '/^  default:/{sub(/^  default:/,""); print; exit}' "$f" | _clean_val
}

# cfg_field <platform-key> <field> — scalar inside platform.platforms.<key>.
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

# --- Repo root ---------------------------------------------------------------
# One accessor, so every skill builds `<root>/.supensour/…` the same way. Note the
# shape difference under Git Bash: `git rev-parse --show-toplevel` prints `C:/src/repo`
# while `pwd` prints `/c/src/repo`. Both open the same files, so always *build* paths
# from one accessor and never string-compare a git path against a pwd-derived one.
repo_root() { git rev-parse --show-toplevel 2>/dev/null || true; }

# --- Project config: <repo>/.supensour/config/config.yaml -------------------
proj_cfg_file() {
  local root; root="$(repo_root)"
  [ -n "$root" ] && [ -f "$root/.supensour/config/config.yaml" ] && {
    printf '%s' "$root/.supensour/config/config.yaml"; return 0; }
  return 1
}

# proj_get <section> <field> — scalar from the project config (section = git|project).
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

# project_config_template → <plugin-root>/examples/project-config.template.yaml, if shipped.
project_config_template() {
  local t; t="$(plugin_root)/examples/project-config.template.yaml"
  [ -f "$t" ] && { printf '%s' "$t"; return 0; }
  return 1
}

# ensure_project_config — create <repo>/.supensour/config/config.yaml if absent, by copying
# the shared template (all values commented) minus its `##` maintainer notes.
ensure_project_config() {
  local root; root="$(repo_root)"
  [ -z "$root" ] && return 0
  local f="$root/.supensour/config/config.yaml" t
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")"
  if t="$(project_config_template)"; then
    sed '/^[[:space:]]*##/d' "$t" > "$f"
  else
    warn "project-config template not found — writing a minimal config."
    cat > "$f" <<'EOF'
# yaml-language-server: $schema=https://raw.githubusercontent.com/supensour/supensour-agent/master/schemas/project-config.schema.json
# Supensour per-repo hints (optional). Uncomment + set to skip detection.
git:
  # platform:
  # token_env:
  # base_branch:
project:
  # language:
  # test_type:
  # test_command:
  # test_command_coverage:
EOF
  fi
  log "📝 Created $f — uncomment hints as needed."
}

# --- .gitignore maintenance -------------------------------------------------
# ensure_gitignore <pattern>... — append each missing pattern to the repo-root
# .gitignore and say so. Never creates the file (a repo without one is a choice);
# warns instead so the caller can surface it.
ensure_gitignore() {
  local root gi p added=0
  root="$(repo_root)"
  [ -z "$root" ] && return 0
  gi="$root/.gitignore"
  if [ ! -f "$gi" ]; then
    warn "No .gitignore at repo root — these stay untracked: $*"
    return 0
  fi
  for p in "$@"; do
    grep -qxF "$p" "$gi" 2>/dev/null && continue
    printf '%s\n' "$p" >> "$gi"
    log "📝 appended '$p' to .gitignore"
    added=$((added + 1))
  done
  return 0
}

# --- Path globs (--files / --path) ------------------------------------------
# ONE glob dialect for every skill, shell-like:
#   *        any run of characters, does not cross `/`
#   **       any number of path segments (`src/**/*.ts`)
#   ?        one character
#   [abc]    character class
#   {a,b}    alternatives (expanded here — git pathspec has no braces)
# A pattern with no wildcard that names a directory means "everything under it".
#
# Two consumers, same dialect: expand_globs (concrete files, for create-tests targets)
# and glob_pathspec (git pathspec args, for `git diff -- …` in review-code).

# brace_expand <pattern> — one line per alternative; recurses for multiple/nested groups.
brace_expand() {
  local p="$1" pre rest body post alt
  case "$p" in
    *'{'*'}'*) ;;
    *) printf '%s\n' "$p"; return 0 ;;
  esac
  pre="${p%%\{*}"
  rest="${p#*\{}"
  body="${rest%%\}*}"
  post="${rest#*\}}"
  local IFS=','
  for alt in $body; do
    brace_expand "$pre$alt$post"
  done
}

# normalize_globs <glob>... — brace-expand, then turn a wildcard-free directory
# (`src/api`, `src/api/`) into a subtree glob (`src/api/**`). One line per pattern.
normalize_globs() {
  local g p
  for g in "$@"; do
    [ -z "$g" ] && continue
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$p" in
        *[*?\[]*) : ;;                                   # already a glob
        */)       p="${p%/}/**" ;;                        # trailing slash → subtree
        *)        [ -d "$p" ] && p="$p/**" ;;             # existing dir → subtree
      esac
      printf '%s\n' "$p"
    done < <(brace_expand "$g")
  done
}

# glob_pathspec <glob>... — print one git pathspec per line, `:(glob)` magic so `*`
# stops at `/` and `**` spans segments (git's default wildmatch lets `*` cross `/`).
glob_pathspec() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && printf ':(glob)%s\n' "$p"
  done < <(normalize_globs "$@")
}

# expand_globs <glob>... — concrete repo-relative paths matching the globs, deduped.
# Unions three sources because none alone is enough:
#   • git ls-files  → tracked files (also matches paths not present in the work tree)
#   • bash glob     → untracked files (a brand-new source file is the common case);
#                     `git ls-files` exits 0 with no output, so it can't be an `||` guard
#   • literal test  → a quoted path the shell never expanded
expand_globs() {
  local pats=() specs=() p m
  while IFS= read -r p; do [ -n "$p" ] && pats+=("$p"); done < <(normalize_globs "$@")
  [ "${#pats[@]}" -eq 0 ] && return 0
  for p in "${pats[@]}"; do specs+=(":(glob)$p"); done
  {
    git ls-files -- "${specs[@]}" 2>/dev/null || true
    # Subshell: globstar/nullglob stay local to this expansion.
    (
      shopt -s globstar nullglob 2>/dev/null || true
      for p in "${pats[@]}"; do
        for m in $p; do [ -f "$m" ] && printf '%s\n' "$m"; done
        [ -f "$p" ] && printf '%s\n' "$p"
      done
    )
  } | sed 's#^\./##' | sort -u
}

# --- Build-tool detection + whole-project commands --------------------------
# These are the UNSCOPED commands (no {spec}) a PR gate needs: install, build, run the
# whole suite. Scoped, per-file commands are a different pair of keys handled by
# create-tests (project.test_command / test_command_coverage, both take {spec}).
#
# detect_build_tool → node | maven | gradle | "" (none recognized).
detect_build_tool() {
  [ -f package.json ]      && { printf 'node'; return; }
  [ -f pom.xml ]           && { printf 'maven'; return; }
  { [ -f build.gradle ] || [ -f build.gradle.kts ]; } && { printf 'gradle'; return; }
  printf ''
}

# gradle_cmd → ./gradlew when wrapped, else gradle.
gradle_cmd() { [ -x ./gradlew ] && printf './gradlew' || printf 'gradle'; }

# _node_script <name> → prints <name> if package.json defines that script, else "".
_node_script() {
  [ -f package.json ] || return 0
  if command -v node >/dev/null 2>&1; then
    node -e '
      let p = {};
      try { p = require("./package.json") } catch (e) { process.exit(0) }
      const s = p.scripts || {};
      if (s[process.argv[1]]) console.log(process.argv[1]);
    ' "$1" 2>/dev/null
  else
    grep -qE "\"$1\"[[:space:]]*:" package.json 2>/dev/null && printf '%s' "$1"
  fi
}

# project_command <install|build|test_all> → the command to run, or "" when there is
# nothing to run for this step (e.g. no `build` script, Maven needs no install step).
# Resolution: project config key → build-tool default. Config always wins.
#   install  → project.install_command    build   → project.build_command
#   test_all → project.test_command_all
project_command() {
  local step="$1" cfg tool
  case "$step" in
    install)  cfg="$(proj_get project install_command 2>/dev/null || true)" ;;
    build)    cfg="$(proj_get project build_command 2>/dev/null || true)" ;;
    test_all) cfg="$(proj_get project test_command_all 2>/dev/null || true)" ;;
    *) die "project_command: unknown step '$step' (install|build|test_all)" ;;
  esac
  [ -n "${cfg:-}" ] && { printf '%s' "$cfg"; return; }

  tool="$(detect_build_tool)"
  case "$tool:$step" in
    node:install)   printf 'npm ci' ;;
    node:build)     [ -n "$(_node_script build)" ] && printf 'npm run build' ;;
    node:test_all)  [ -n "$(_node_script test)" ] && printf 'npm run test' ;;
    maven:install)  : ;;                       # `mvn` resolves deps as part of compile
    maven:build)    printf 'mvn -B clean compile' ;;
    maven:test_all) printf 'mvn -B clean verify' ;;
    gradle:install) : ;;                       # Gradle resolves deps per task
    gradle:build)   printf '%s build -x test' "$(gradle_cmd)" ;;
    gradle:test_all) printf '%s test' "$(gradle_cmd)" ;;
    *) : ;;
  esac
}

# --- Repo config: <plugin-root>/supensour-config.yaml (watermark/author) ----
wm_cfg_file() {
  local f; f="$(plugin_root)/supensour-config.yaml"
  [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  return 1
}

# Top-level `<key>:` scalar.
_wm_top() {
  local f key="$1"; f="$(wm_cfg_file)" || return 1
  awk -v k="$key" '$0 ~ "^" k ":" {sub("^" k ":",""); print; exit}' "$f" | _clean_val
}

# Per-skill `skills.<skill>.<key>`.
_wm_skill() {
  local f skill="$1" key="$2"; f="$(wm_cfg_file)" || return 1
  awk -v s="$skill" -v k="$key" '
    /^skills:[[:space:]]*$/        { ins=1; next }
    ins && /^[^[:space:]]/         { ins=0 }
    ins && $0 ~ "^  " s ":[[:space:]]*$" { inb=1; next }
    inb && /^  [^[:space:]]/       { inb=0 }
    inb && $0 ~ "^    " k ":"      { sub("^    " k ":",""); print; exit }
  ' "$f" | _clean_val
}

# wm_resolve <key> <default> — skills.<SKILL_KEY>.<key> > top-level <key> > built-in default.
wm_resolve() {
  local key="$1" def="$2" v
  v="$(_wm_skill "$SKILL_KEY" "$key" 2>/dev/null || true)"
  [ -z "$v" ] && v="$(_wm_top "$key" 2>/dev/null || true)"
  [ -z "$v" ] && v="$def"
  printf '%s' "$v"
}

# resolve_attribution — set WATERMARK (plain, console/code comments),
# WATERMARK_MD ({skillName} as a markdown link, for .md + PR/MR comments) and
# AUTHOR_TEXT. Call once, after the skill has set its SKILL_* / *_DEFAULT vars.
resolve_attribution() {
  local tpl url
  tpl="$(wm_resolve watermark_template "${WATERMARK_DEFAULT:-Generated with skill {skillName}}")"
  url="$(wm_resolve watermark_url "${WATERMARK_URL_DEFAULT:-https://github.com/supensour/supensour-agent}")"
  WATERMARK="${tpl//\{skillName\}/$SKILL_NAME}"
  WATERMARK_MD="${tpl//\{skillName\}/[$SKILL_NAME]($url)}"
  AUTHOR_TEXT="$(wm_resolve author "${AUTHOR_DEFAULT:-supensour-agent}")"
  export WATERMARK WATERMARK_MD AUTHOR_TEXT SKILL_NAME SKILL_KEY
}

# --- Safe command execution -------------------------------------------------
# Commands can come from a target repo's .supensour/config/config.yaml, which is
# attacker-controlled when reviewing/testing a repo you don't own. Only allow a
# known set of build-tool entrypoints, and always show what runs.
# The `.bat`/`.cmd` wrappers are here because a config authored on Windows names them
# (`gradlew.bat`), and Git Bash runs them fine.
SUPENSOUR_ALLOWED_CMDS="${SUPENSOUR_ALLOWED_CMDS:-npm yarn pnpm bun npx node vitest jest mvn mvnw ./mvnw mvnw.cmd ./mvnw.cmd gradle gradlew ./gradlew gradlew.bat ./gradlew.bat make}"

# assert_allowed_cmd <command-string> — die unless its first word is allowlisted.
assert_allowed_cmd() {
  local cmd="$1" first allowed
  first="${cmd%% *}"
  for allowed in $SUPENSOUR_ALLOWED_CMDS; do
    [ "$first" = "$allowed" ] && return 0
  done
  die "Refusing to run '$first' — not in the allowlist ($SUPENSOUR_ALLOWED_CMDS).
     It came from .supensour/config/config.yaml (test_command / test_command_coverage).
     Fix the config, or extend SUPENSOUR_ALLOWED_CMDS in the environment if you trust it."
}

# run_checked <command-string> [redirect-target] — allowlist-check, echo, then run.
run_checked() {
  local cmd="$1"
  assert_allowed_cmd "$cmd"
  log "▶ $cmd"
  eval "$cmd"
}
