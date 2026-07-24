#!/usr/bin/env bash
# help.sh — print create-tests usage. Invoked for `/create-tests --help`.
set -euo pipefail

cat <<'EOF'
create-tests — generate minimum-viable tests for changed or specified source files.

Usage:
  /create-tests [options]

Options:
  --lang <key>             Force ruleset: vue, springboot (default: auto-detect from extensions).
  --type <unit|integration> Test type (default: unit; integration not yet supported).
  --files <glob>           Source files to test (repeatable; default: files changed vs --base).
  --base <branch>          Diff base for changed-file detection (default: auto-detect).
  --coverage <target>      Coverage focus, e.g. 100, branches — guides which cases to emphasize.
  --proposal               Save proposed specs under .supensour/create-tests/ instead of writing
                           to convention paths (default: write spec files directly).
  --clean [branch]         Delete saved proposals for a branch (default: current), then exit.
  --clean-all              Delete all saved proposals (.supensour/create-tests/), then exit.
  --help                   Show this help.
EOF
