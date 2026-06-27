#!/usr/bin/env bash
# lang-vue.sh — Vue / JS-TS (Vitest) language implementation for create-tests.
# Uniform interface: vue_spec_path / vue_run_tests. Sourced by common.sh.

# vue_spec_path <source-file> → conventional spec path.
# Detects the project's test root from existing specs; defaults to test/unit/specs.
# Maps src/<rel>.<ext> → <root>/<rel>.spec.ts (strips a leading src/ if present).
vue_spec_path() {
  local src="$1" root rel base
  root="$(_vue_test_root)"
  rel="${src#src/}"
  rel="${rel%.*}"
  base=".spec.ts"
  printf '%s/%s%s' "$root" "$rel" "$base"
}

# _vue_test_root → directory existing specs live in (best-effort), else default.
_vue_test_root() {
  local hit
  hit="$(git ls-files 2>/dev/null | grep -E '\.spec\.(t|j)sx?$' | head -n1 || true)"
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
