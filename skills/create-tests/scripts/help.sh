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
  --coverage <n>           Numeric coverage bar applied to EVERY metric (default: 100). Used as the
                           skip-gate threshold and as what the generated cases aim for.
  --pool <n>               Max concurrent analyst subagents (default: min(10, 30% of cores)),
                           global across language groups. --pool 1 = one target at a time.
  --analyst-model <key>    Model for analyst subagents (default: sonnet; 'inherit' = session model).
                           Alias: --agent-model.
  --writer-model <key>     Model for writer subagents (default: sonnet; try haiku — the plan is
                           near-transcription).
  --no-split               Skip the writer hop: the analyst writes the spec itself.
  --explain                Print the resolved run config (language, targets, coverage gate results,
                           test commands, pool, models) and stop. No subagents, no writes.
  --executor <file>        Analyst mode: own exactly this one target (no target detection, no
                           coverage gate). Used by dispatched analyst subagents.
  --clean [branch]         Delete saved plans for a branch (default: current), then exit.
  --clean-all              Delete everything under .supensour/create-tests/, then exit.
  --help                   Show this help.
EOF
