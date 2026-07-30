#!/usr/bin/env bash
# verify.sh [--skip-tests] [--print] — build & test verification for a review.
#
# Runs, in order: install → build → whole test suite. Each command comes from the repo
# config if set (project.install_command / build_command / test_command_all), else from
# the detected build tool (package.json → npm, pom.xml → mvn, build.gradle → gradlew).
# Every command goes through the shared allowlist and is echoed before it runs.
#
#   --skip-tests   run install + build only (the caller found medium+ findings)
#   --print        print the resolved commands and exit without running anything
#
# Output: one TSV line per step on STDOUT —
#   <step>\t<command|->\t<PASS|FAIL|SKIPPED|NONE>\t<exit-code|->
# Runner output goes to STDERR so the table stays parseable. Exit code: 0 when nothing
# failed, 1 when a step failed (the caller reports it as a critical finding).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SKIP_TESTS=0 PRINT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=1; shift ;;
    --print)      PRINT_ONLY=1; shift ;;
    *) shift ;;
  esac
done

TOOL="$(detect_build_tool)"
if [ -z "$TOOL" ]; then
  warn "No recognized build system (package.json / pom.xml / build.gradle) — verification skipped."
  printf 'build-system\t-\tNONE\t-\n'
  exit 0
fi
log "▶ build tool: $TOOL"

INSTALL="$(project_command install)"
BUILD="$(project_command build)"
TEST_ALL="$(project_command test_all)"

# These three are whole-project commands — nothing substitutes {spec}/{coverage_args} here,
# so a placeholder means a per-file command was pasted into a gate key. Say so loudly; the
# command still runs verbatim (it's the user's config, not ours to rewrite).
for _pair in "install_command:$INSTALL" "build_command:$BUILD" "test_command_all:$TEST_ALL"; do
  case "${_pair#*:}" in
    *'{'*'}'*) warn "project.${_pair%%:*} contains a placeholder — whole-project commands take none; it will run literally. Use test_command / test_command_coverage for per-file runs." ;;
  esac
done

if [ "$PRINT_ONLY" -eq 1 ]; then
  printf 'install\t%s\t-\t-\n'  "${INSTALL:--}"
  printf 'build\t%s\t-\t-\n'    "${BUILD:--}"
  printf 'test\t%s\t-\t-\n'     "${TEST_ALL:--}"
  exit 0
fi

FAILED=0

# run_step <label> <command> <skipped-reason-or-empty>
# Empty command → NONE (nothing defined for this step, not an error).
run_step() {
  local label="$1" cmd="$2" skip="${3:-}"
  if [ -z "$cmd" ]; then
    printf '%s\t-\tNONE\t-\n' "$label"
    return 0
  fi
  if [ -n "$skip" ]; then
    printf '%s\t%s\tSKIPPED\t-\n' "$label" "$cmd"
    log "↷ $label skipped — $skip"
    return 0
  fi
  assert_allowed_cmd "$cmd"
  log "▶ $cmd"
  if eval "$cmd" >&2; then
    printf '%s\t%s\tPASS\t0\n' "$label" "$cmd"
  else
    local rc=$?
    printf '%s\t%s\tFAIL\t%d\n' "$label" "$cmd" "$rc"
    FAILED=1
    return 1
  fi
}

# A failed install or build makes the later steps meaningless — stop there.
if ! run_step install "$INSTALL"; then
  printf 'build\t%s\tSKIPPED\t-\n' "${BUILD:--}"
  printf 'test\t%s\tSKIPPED\t-\n'  "${TEST_ALL:--}"
  exit 1
fi
if ! run_step build "$BUILD"; then
  printf 'test\t%s\tSKIPPED\t-\n' "${TEST_ALL:--}"
  exit 1
fi

if [ "$SKIP_TESTS" -eq 1 ]; then
  run_step test "$TEST_ALL" "medium+ findings to address first"
else
  run_step test "$TEST_ALL" || true
fi

[ "$FAILED" -eq 0 ] || exit 1
