#!/usr/bin/env bash
# test-command.sh <lang> <coverage|plain> --spec <spec>... [--source <src>...]
# Prints the exact command this project uses to run those tests — the same resolution
# run-tests.sh and the coverage gate use (project config → detected build tool).
# The analyst puts this verbatim in a plan's `Run:` line so the writer never guesses.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --type) export CT_TEST_TYPE="$2"; shift 2 ;;
    *) break ;;
  esac
done

LANG_ARG="${1:-}"; MODE="${2:-coverage}"; shift 2 || true
[ -n "$LANG_ARG" ] || die "usage: test-command.sh [--type <t>] <lang> <coverage|plain> --spec <spec>... [--source <src>...]"

SPECS=() SRCS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)   shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do SPECS+=("$1"); shift; done ;;
    --source) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do SRCS+=("$1"); shift; done ;;
    *) shift ;;
  esac
done
[ "${#SPECS[@]}" -gt 0 ] || die "test-command.sh: at least one --spec is required"

load_lang "$LANG_ARG"
case "$LANG_ARG" in
  vue)        vue_test_command "$MODE" "${SPECS[*]}" "${SRCS[*]:-}" ;;
  springboot) springboot_test_command "$MODE" "${SPECS[@]}" ;;
  *)          lang_dispatch test_command "$MODE" "${SPECS[*]}" "${SRCS[*]:-}" ;;
esac
printf '\n'
