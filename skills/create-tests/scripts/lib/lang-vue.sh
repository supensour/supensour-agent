#!/usr/bin/env bash
# lang-vue.sh — Vue / JS-TS (Vitest) language implementation for create-tests.
# Uniform interface: vue_spec_path / vue_run_tests. Sourced by common.sh.

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

# _vue_test_root → directory existing specs live in (best-effort), else default.
_vue_test_root() {
  local hit
  hit="$(_vue_spec_hits | head -n1)"
  if [ -n "$hit" ]; then
    # Use the top two path segments if they look like a test root (test/..., tests/...).
    case "$hit" in
      test/unit/specs/*) printf 'test/unit/specs' ;;
      test/*)            printf 'test' ;;
      tests/*)           printf 'tests' ;;
      *)                 printf '%s' "$(dirname "$hit")" ;;
    esac
  else
    printf 'test/unit/specs'
  fi
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

# vue_run_tests <spec-file> [source-file] → run Vitest; scoped coverage if source given.
# Prints the runner output; exit code = test result.
vue_run_tests() {
  local spec="$1" src="${2:-}"
  [ -f package.json ] || { warn "No package.json — run from the project root."; return 2; }
  if [ -n "$src" ]; then
    npm run test:unit -- run "$spec" --coverage --coverage.include="$src"
  else
    npm run test:unit -- run "$spec"
  fi
}
