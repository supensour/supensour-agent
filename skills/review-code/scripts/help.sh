#!/usr/bin/env bash
# help.sh — print review-code usage. Invoked for `/review-code --help`.
set -euo pipefail

cat <<'EOF'
review-code — architect-level code review of a branch/PR diff.

Usage:
  /review-code [options]

Options:
  --branch <branch>      Source branch to review (default: current branch).
  --base <branch>        Base branch to diff against (default: auto-detect).
  --files <glob>         Scope review to matching paths (repeatable).
  --severity <list>      Filter output: critical,high,medium,low,info.
  --lang <key>           Force ruleset: vue, springboot, data-migration, generic.
  --scope <diff|project> diff (default): only diff-attributable findings; project: whole repo.
  --platform <key>       Git platform key from ~/.supensour/config/supensour.yaml.
  --push                 Also post findings as PR/MR comments (prunes own prior comments first).
  --push-saved [path]    Post a previously saved local review (no path → latest for the branch).
  --clean [branch]       Remove saved local reviews for a branch (default: current branch).
  --clean-all            Remove all saved local reviews for every branch.
  --help                 Show this help.

Notes:
  A local copy of every review is always saved to .supensour/review-code/<branch>/,
  so findings survive a missing PR/MR and can be pushed later with --push-saved.
EOF
