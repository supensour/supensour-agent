#!/usr/bin/env bash
# lang-vue.sh — Vue / JS-TS (Vitest) language implementation for create-tests.
# Uniform interface: vue_spec_path / vue_run_tests / vue_coverage_scan. Sourced by common.sh.

# vue_spec_path <source-file> → conventional spec path.
# Detects the project's test root + spec extension from existing specs; defaults to
# test/unit/specs and .spec.ts. Maps src/<rel>.<ext> → <root>/<rel><spec-ext>.
vue_spec_path() {
  local src="$1" root rel base
  root="$(_vue_test_root)"
  base="$(_vue_spec_ext)"
  rel="${src#src/}"
  rel="${rel%.*}"
  printf '%s/%s%s' "$root" "$rel" "$base"
}

# _vue_spec_hits → existing spec files in the repo (best-effort).
_vue_spec_hits() { git ls-files 2>/dev/null | grep -E '\.spec\.(t|j)sx?$' || true; }

# _vue_test_type → the test type this run targets: CT_TEST_TYPE > project.test_type > unit.
_vue_test_type() {
  local t="${CT_TEST_TYPE:-}"
  [ -z "$t" ] && t="$(proj_get project test_type 2>/dev/null || true)"
  printf '%s' "${t:-unit}"
}

# _vue_preferred_roots <type> → roots to prefer for that test type, best first.
# Unit specs belong under test/unit/specs; integration gets its own tree so the two
# never mix (and so a future --type integration lands in test/integration/**).
_vue_preferred_roots() {
  case "$1" in
    integration) printf 'test/integration tests/integration test/e2e tests/e2e' ;;
    *)           printf 'test/unit/specs test/unit tests/unit' ;;
  esac
}

# _vue_root_of <spec-path> → the known test root that spec lives under ("" if none).
_vue_root_of() {
  case "$1" in
    test/unit/specs/*)    printf 'test/unit/specs' ;;
    test/unit/*)          printf 'test/unit' ;;
    tests/unit/*)         printf 'tests/unit' ;;
    test/integration/*)   printf 'test/integration' ;;
    tests/integration/*)  printf 'tests/integration' ;;
    test/*)               printf 'test' ;;
    tests/*)              printf 'tests' ;;
    *) : ;;                # custom root or co-located — handled by _vue_lcp_root
  esac
}

# _vue_lcp_root — longest common directory prefix of specs outside the known roots and
# outside src/ (i.e. a project with its own test tree like spec/js/**). Empty if the only
# specs are co-located with sources, since those have no shared root to reuse.
_vue_lcp_root() {
  local hit dir lcp="" first=1
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    [ -n "$(_vue_root_of "$hit")" ] && continue
    case "$hit" in src/*) continue ;; esac
    dir="$(dirname "$hit")"
    if [ "$first" = 1 ]; then lcp="$dir"; first=0; continue; fi
    while [ -n "$lcp" ] && [ "${dir#"$lcp"/}" = "$dir" ] && [ "$dir" != "$lcp" ]; do
      lcp="$(dirname "$lcp")"; [ "$lcp" = "." ] && lcp=""
    done
  done < <(_vue_spec_hits)
  printf '%s' "$lcp"
}

# _vue_test_root → where new specs go, in priority order:
#   1. a preferred root for this test type that already exists in the repo
#      (unit → test/unit/specs → test/unit → tests/unit; integration → test/integration → …)
#   2. the known root MOST existing specs share (ties → shortest path), so a repo with its
#      own convention keeps it instead of following whichever spec sorted first
#   3. the common prefix of a custom test tree (e.g. spec/js/**)
#   4. the type's default root
_vue_test_root() {
  local type p root counted
  type="$(_vue_test_type)"

  for p in $(_vue_preferred_roots "$type"); do
    [ -d "$p" ] && { printf '%s' "$p"; return; }
  done

  counted="$(
    _vue_spec_hits | while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      root="$(_vue_root_of "$hit")"
      [ -n "$root" ] && printf '%s\n' "$root"
    done | sort | uniq -c | sort -k1,1nr -k2,2 | head -n1
  )"
  root="$(printf '%s' "$counted" | awk '{print $2}')"
  [ -n "$root" ] && { printf '%s' "$root"; return; }

  root="$(_vue_lcp_root)"
  [ -n "$root" ] && { printf '%s' "$root"; return; }

  case "$type" in
    integration) printf 'test/integration' ;;
    *)           printf 'test/unit/specs' ;;
  esac
}

# _vue_spec_ext → prevailing spec extension across existing specs, else .spec.ts.
# Any .spec.ts/.spec.tsx present wins .spec.ts; an all-JS project (.spec.js/.spec.jsx
# only) gets .spec.js — matches rules/vue/index.md's naming convention.
_vue_spec_ext() {
  local hits
  hits="$(_vue_spec_hits)"
  [ -z "$hits" ] && { printf '.spec.ts'; return; }
  if printf '%s\n' "$hits" | grep -qE '\.spec\.tsx?$'; then
    printf '.spec.ts'
  else
    printf '.spec.js'
  fi
}

# --- Test command resolution -------------------------------------------------
# Precedence: <repo>/.supensour/config/config.yaml (project.test_command /
# project.test_command_coverage) → the package.json script that runs vitest →
# `npx vitest run`. Placeholders: {spec} {source} {coverage_args} {reporter_args}.
#
# {reporter_args} is where the coverage gate injects its machine-readable reporter
# (json-summary + a temp reportsDirectory). Put it wherever flags belong in your
# command — that matters when the command isn't a plain flag-terminated one (pipes,
# `&&`, wrappers), because otherwise the gate has to append the flags at the very end.

# _vue_npm_script → name of the package.json script that runs vitest, else "".
_vue_npm_script() {
  [ -f package.json ] || return 0
  if command -v node >/dev/null 2>&1; then
    node -e '
      let p = {};
      try { p = require("./package.json") } catch (e) { process.exit(0) }
      const s = p.scripts || {};
      for (const k of ["test:unit", "test:vitest", "test"]) {
        if (s[k] && /vitest/.test(s[k])) { console.log(k); process.exit(0) }
      }
      const k = Object.keys(s).find((k) => /vitest/.test(s[k]));
      if (k) console.log(k);
    ' 2>/dev/null
  else
    grep -oE '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*vitest[^"]*"' package.json 2>/dev/null \
      | head -n1 | sed -E 's/^"([^"]*)".*/\1/'
  fi
}

# _vue_cmd_template <coverage|plain> → the command template to run.
_vue_cmd_template() {
  local mode="$1" t script
  if [ "$mode" = coverage ]; then
    t="$(proj_get project test_command_coverage 2>/dev/null || true)"
  else
    t="$(proj_get project test_command 2>/dev/null || true)"
  fi
  [ -n "$t" ] && { printf '%s' "$t"; return; }

  script="$(_vue_npm_script)"
  if [ -n "$script" ]; then
    if [ "$mode" = coverage ]; then
      printf 'npm run %s -- run {spec} --coverage {coverage_args} {reporter_args}' "$script"
    else
      printf 'npm run %s -- run {spec} --coverage=false' "$script"
    fi
  else
    if [ "$mode" = coverage ]; then
      printf 'npx vitest run {spec} --coverage {coverage_args} {reporter_args}'
    else
      printf 'npx vitest run {spec} --coverage=false'
    fi
  fi
}

# _vue_render <template> <spec-list> <source-list> <coverage-args> <reporter-args> → command.
# A template without {reporter_args} still works: the gate appends the reporter flags
# (fine for flag-terminated commands, wrong for pipes/&& — hence the placeholder).
_vue_render() {
  local cmd="$1" specs="$2" srcs="$3" cov="$4" rep="${5:-}"
  cmd="${cmd//\{spec\}/$specs}"
  cmd="${cmd//\{source\}/$srcs}"
  cmd="${cmd//\{coverage_args\}/$cov}"
  cmd="${cmd//\{reporter_args\}/$rep}"
  printf '%s' "$cmd"
}

# vue_test_command <coverage|plain> <spec-list> [source-list] [reporter-args] → command string.
# Exposed so the analyst can put a verbatim `Run:` line in a plan (no reporter args there).
vue_test_command() {
  local mode="$1" specs="$2" srcs="${3:-}" rep="${4:-}" cov="" s
  for s in $srcs; do cov="$cov --coverage.include=$s"; done
  # Squeeze so an empty {reporter_args} doesn't leave double/trailing spaces in the
  # command the analyst pastes into a plan's `Run:` line.
  _vue_render "$(_vue_cmd_template "$mode")" "$specs" "$srcs" "${cov# }" "$rep" | _vue_squeeze_spaces
}

# _vue_squeeze_spaces — collapse the double spaces left by an empty {reporter_args}.
_vue_squeeze_spaces() { sed -E 's/[[:space:]]{2,}/ /g; s/[[:space:]]+$//'; }

# vue_coverage_scan <source-file>... → keyed TSV per source:
#   <src>\tstatements=<n>\tbranches=<n>\tfunctions=<n>\tlines=<n>\t<SKIP|GENERATE>
# Runs only the existing specs mapped from the given sources, coverage scoped to those
# sources. SKIP when every metric >= ${CT_THRESHOLD:-100}. Fail-safe: any problem
# (no package.json, failing specs, no summary, no JSON parser) → GENERATE for all.
vue_coverage_scan() {
  local srcs=("$@") src spec specs=() cov_srcs=() tmp summary cmd
  local threshold="${CT_THRESHOLD:-100}"

  _vue_scan_all_generate() {
    local s; for s in "${srcs[@]}"; do
      printf '%s\tstatements=-\tbranches=-\tfunctions=-\tlines=-\tGENERATE\n' "$s"
    done
  }

  [ -f package.json ] || { warn "No package.json — coverage scan skipped."; _vue_scan_all_generate; return 0; }

  for src in "${srcs[@]}"; do
    spec="$(vue_spec_path "$src")"
    if [ -f "$spec" ]; then specs+=("$spec"); cov_srcs+=("$src"); fi
  done
  [ "${#specs[@]}" -gt 0 ] || { log "No existing specs for the target set — all targets need generation."; _vue_scan_all_generate; return 0; }

  tmp="$(mktemp -d)"
  local reporter="--coverage.reporter=json-summary --coverage.reportsDirectory=$tmp"
  cmd="$(vue_test_command coverage "${specs[*]}" "${cov_srcs[*]}" "$reporter")"
  # Template without {reporter_args} → append (correct only for flag-terminated commands).
  case "$cmd" in
    *"$reporter"*) : ;;
    *) cmd="$cmd $reporter"
       warn "test_command_coverage has no {reporter_args} placeholder — appending reporter flags at the end." ;;
  esac
  cmd="$(printf '%s' "$cmd" | _vue_squeeze_spaces)"
  assert_allowed_cmd "$cmd"
  log "▶ coverage scan (threshold ${threshold}%): ${#specs[@]} existing spec(s) over ${#srcs[@]} target(s)"
  log "▶ $cmd"
  if ! eval "$cmd" >"$tmp/run.log" 2>&1; then
    warn "Existing specs failed or errored — see $tmp/run.log. Treating all targets as GENERATE."
    _vue_scan_all_generate; return 0
  fi

  summary="$tmp/coverage-summary.json"
  [ -f "$summary" ] || { warn "No coverage-summary.json produced — treating all targets as GENERATE."; _vue_scan_all_generate; return 0; }

  cat > "$tmp/parse.js" <<'JS'
const fs = require('fs');
const [summaryPath, threshold, ...srcs] = process.argv.slice(2);
const min = Number(threshold);
const data = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
const keys = Object.keys(data).filter((k) => k !== 'total');
const norm = (p) => p.replace(/\\/g, '/');
const METRICS = ['statements', 'branches', 'functions', 'lines'];
for (const src of srcs) {
  const want = norm(src);
  const key = keys.find((k) => norm(k) === want || norm(k).endsWith('/' + want));
  if (!key) {
    console.log([src, ...METRICS.map((m) => `${m}=-`), 'GENERATE'].join('\t'));
    continue;
  }
  const m = data[key];
  const pct = (n) => (m[n] && typeof m[n].pct === 'number' ? m[n].pct : 0);
  const cols = METRICS.map((n) => `${n}=${pct(n)}`);
  const full = METRICS.every((n) => pct(n) >= min);
  console.log([src, ...cols, full ? 'SKIP' : 'GENERATE'].join('\t'));
}
JS
  if command -v node >/dev/null 2>&1; then
    node "$tmp/parse.js" "$summary" "$threshold" "${srcs[@]}"
  else
    warn "node not found — cannot parse coverage summary. Treating all targets as GENERATE."
    _vue_scan_all_generate
  fi
}

# vue_run_tests <spec-file> [source-file] → run Vitest; scoped coverage if source given.
# Prints the runner output; exit code = test result.
vue_run_tests() {
  local spec="$1" src="${2:-}" cmd
  [ -f package.json ] || { warn "No package.json — run from the project root."; return 2; }
  if [ -n "$src" ]; then
    cmd="$(vue_test_command coverage "$spec" "$src")"
  else
    cmd="$(vue_test_command plain "$spec")"
  fi
  cmd="$(printf '%s' "$cmd" | _vue_squeeze_spaces)"
  run_checked "$cmd"
}
