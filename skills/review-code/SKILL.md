---
name: review-code
description: Architect-level code review of a branch/PR diff across languages (Vue, Spring Boot, extensible). Reviews security, architecture, performance, quality, business/financial impact, and test gaps. Diff-scoped by default. Outputs a local report and optionally posts inline comments to GitHub/GitLab CE/Bitbucket PRs (pruning its own prior comments first). Use for "review this PR/MR", "review my diff", "code review before merge".
argument-hint: "[--branch <branch>] [--push] [--push-saved <path>] [--clean <branch>] [--clean-all] [--platform <key>] [--base <branch>] [--files <glob>] [--severity <list>] [--lang <key>] [--scope diff|project] [--help]"
allowed-tools: Read, Grep, Glob, Bash, WebFetch, AskUserQuestion, Agent
---

# review-code

Code review skill. Reviews diffs like a 10-year architect — security, architecture, performance, quality, business impact. Supports Vue, Spring Boot, extensible to any language.

> **Scripts do the CLI work.** All git/platform/API commands are in `scripts/` (see `platforms/detect.md` + `platforms/comment.md`). `$SKILL_DIR` = this skill's directory. Invoke scripts rather than re-emitting commands — they print compact JSON/TSV to parse. Resolve once:
> `SKILL_DIR="$(dirname "$(readlink -f path/to/this/SKILL.md)")"` — in practice the harness knows this skill's directory; call scripts as `bash "<skill-dir>/scripts/<name>.sh" …`.

## Invocation

```
/review-code                          # review current branch's PR (diff-scoped)
/review-code --branch feature/RANCH-1 # review another branch's PR
/review-code --push                   # also post comments to PR (prunes own prior comments first)
/review-code --platform gitlab-ce     # override platform detection
/review-code --base main              # explicit base branch
/review-code --files src/api/         # scope to specific paths
/review-code --severity critical,high # filter output severity
/review-code --scope project          # review whole project, not just the diff
/review-code --push-saved             # push a previously saved local review to PR/MR
/review-code --clean                  # delete saved local reviews for current branch
/review-code --clean feature/RANCH-1  # delete saved local reviews for a branch
/review-code --clean-all              # delete all saved local reviews
/review-code --help                   # print usage and exit
```

**Utility flags run a script and stop** — no review is performed:
- `--help` → `bash "<skill-dir>/scripts/help.sh"`, print output, stop.
- `--clean [branch]` → `bash "<skill-dir>/scripts/clean.sh" [branch]` (default: current branch), stop.
- `--clean-all` → `bash "<skill-dir>/scripts/clean.sh" --all`, stop.

`clean` removes `<repo>/.supensour/review-code/<branch>/` (saved comments + JSON) and any kept worktrees
for that branch; `--clean-all` removes the whole `.supensour/review-code/` tree.

## Input

| Flag | Default | Description |
|------|---------|-------------|
| `--branch <branch>` | current branch | Source branch to review. Its open PR/MR is located and reviewed |
| `--push` | off | Post findings as PR comments now. If PR/MR/token unavailable, falls back to saved local copy |
| `--push-saved [path]` | off | Push previously saved local review to PR/MR. No path → latest saved review for `SRC` (`--branch` or current) |
| `--platform <key>` | auto | Platform key from `~/.supensour/config/supensour.yaml` |
| `--base <branch>` | auto-detect | Base branch to diff against |
| `--files <glob>` | all changed | Scope review to matching paths |
| `--severity <list>` | all | Filter: `critical`, `high`, `medium`, `low`, `info` |
| `--lang <key>` | auto-detect | Force language ruleset: `vue`, `springboot`, `data-migration`, `generic` |
| `--scope <diff\|project>` | `diff` | `diff`: only flag issues in/caused by the diff. `project`: review the whole project |
| `--clean [branch]` | current branch | Delete saved local reviews (comments + kept worktrees) for a branch, then stop |
| `--clean-all` | — | Delete all saved local reviews (`.supensour/review-code/`), then stop |
| `--help` | — | Print usage (`scripts/help.sh`) and stop |

Local copy of every review **always saved** (regardless of `--push`), so findings never lost when PR/MR not available yet. See "Local persistence" below.

## Review scope (`--scope`, default `diff`)

- **`diff` (default)** — Review the changes. **Read freely** around the diff — related functions in other
  files, callers, callees, types — to understand intent and impact. But only **raise findings that are
  introduced by, or directly broken by, the diff.** Do **not** report pre-existing issues in untouched
  code, even when you read it for context. If a diff change breaks or depends on existing code, that
  *is* diff-attributable → report it.
- **`project`** — Lift the restriction. Review the whole project; pre-existing issues are in scope.

This rule is threaded into every Step 1 subagent and the Step 2 cross-file pass.

## Process

### Preflight — working tree check

First resolve the source branch `SRC` (Step 0.0): `--branch` flag, else current branch.

A worktree is **required** when either holds:
- **`SRC` ≠ currently checked-out branch** — Step 3 build/test must run `SRC`'s code, not whatever is checked out. Always isolate in a worktree checked out to `SRC`.
- **Working tree is dirty** (`git status --porcelain` non-empty) — don't mutate the user's uncommitted work.

Check state with the script (mechanical only — it never prompts):
```bash
bash "<skill-dir>/scripts/worktree.sh" status "$SRC"   # → {current, src, dirty, needs_worktree}
```

Otherwise (`SRC` == current branch AND tree clean) → proceed to Step 0 directly. No stash needed.

When a worktree is needed:
- If **dirty** (and `SRC` == current) → **stop and ask the user** (AskUserQuestion):
  1. **Use a new worktree (recommended)** — review committed state in isolation, working tree untouched.
  2. **Abort** — exit. User commits/stashes manually, re-runs.

  Do not silently stash. Do not proceed in the dirty tree.
- If **`SRC` ≠ current branch** → create the worktree automatically (the user explicitly asked for another branch).

**Worktree creation** (script handles path + `origin/<SRC>` fallback):
```bash
WT="$(bash "<skill-dir>/scripts/worktree.sh" ensure "$SRC")"   # prints worktree path
```
- Run all subsequent steps (0–5) **from `$WT`**, not the original tree.
- Local persistence still writes to the **original repo's** `.supensour/review-code/` (not inside the throwaway worktree), so saved reviews survive cleanup.
- **Cleanup** after review — conditional. Add `.supensour/review-code/` to `.gitignore`.
  - Comments pushed successfully (or no push requested and no pending local copy) → `bash "<skill-dir>/scripts/worktree.sh" remove "$WT"`.
  - **Comments NOT pushed but a local copy was saved** → **keep the worktree**. It preserves the exact reviewed HEAD for a later `--push-saved`. Tell user: `📂 Worktree kept at <WT> — review not pushed. Re-run --push-saved from there, then remove with: scripts/worktree.sh remove <WT>`.
  - Save the worktree path into the saved JSON (`worktree` field) so `--push-saved` reuses it and removes it after a successful push.
- If `worktree.sh ensure` fails (path exists, locked), report error and fall back to the abort option — never continue in the dirty tree.

> With a worktree, Step 3's stash discipline is a safety backstop only (tree is clean there).

### Step 0 — Context gathering

0. **Resolve source branch** `SRC` — `--branch` flag if provided, else current branch (`git rev-parse --abbrev-ref HEAD`). If `--branch` given but no such branch exists locally or on remote, error and exit.
0b. **Ensure config exists** — create any missing config from a template (idempotent):
   ```bash
   bash "<skill-dir>/scripts/init-config.sh"   # creates ~/.supensour/config/supensour.yaml + <repo>/.supensour/config/config.yaml if absent
   ```
   Prints `📝 Created …` for each file it writes (global catalog is prefilled from the detected remote; review/edit host + token_env).
1. **Resolve platform + PR/MR + base** with the scripts (sequential — each needs the prior):
   ```bash
   bash "<skill-dir>/scripts/detect-platform.sh" [--platform <key>]      # → platform JSON
   PRS_JSON="$(bash "<skill-dir>/scripts/fetch-pull-request.sh" --branch "$SRC" [--platform <key>])"   # → [{number,url,title,source,base}, ...]
   ```
   `fetch-pull-request.sh` returns a JSON **array** of all open PR/MRs for `SRC` (`source` = source branch, `base` = target branch). The `detect-platform.sh` JSON also includes `base_branch` + `language` from the per-repo `.supensour/config/config.yaml` (empty if unset). Branch on the count:
   - **0 PRs** → **stop and ask** (AskUserQuestion):
     1. **Review against the default branch (recommended)** — diff `SRC` vs the repo default/base, local review only (no push; re-run `--push-saved` when a PR exists).
     2. **Abort** — exit without reviewing.
   - **1 PR** → use it. **Report** to the user: PR number, URL, title, and the branch flow `[source] -> [target]`. Capture its number, URL, title, **base**.
   - **>1 PR** → **stop and ask** (AskUserQuestion) which to review — one option per PR labelled
     `#<number> — <title> · [source] -> [target]`, plus an **Abort** option. Use the chosen PR for the rest of the run.
   (No token but a PR exists → continue local review, skip push.)
2. **Detect base branch** — priority: `--base` flag → project `git.base_branch` (from detect JSON) → PR/MR `base` from the fetch → repo default (`git symbolic-ref refs/remotes/origin/HEAD` → else `main`/`master`/`develop`).
3. **Collect diff** for `SRC` with the script:
   ```bash
   bash "<skill-dir>/scripts/collect-diff.sh" "$BASE" "$SRC"   # name-status + full diff
   ```
4. Detect languages from changed file extensions. **Load matching rule modules in one parallel batch** (`rules/generic.md` + any of `rules/vue.md` / `rules/springboot.md` / `rules/data-migration.md` — independent reads).

### Step 1 — Diff analysis (parallel)

Changed files are independent — **fan out across parallel subagents**, one per file (or per small group of related files for large diffs). Launch all subagents in a single batch.

Each subagent receives: the file's diff, the loaded rule modules (generic + language-specific), the severity definitions, and the **`--scope` rule**. It returns structured findings (`severity, file, line, dimension, title, problem, impact, fix, test_suggestion`).

Per file, the subagent:
1. Understands **intent** — what is the change trying to do?
2. Reads surrounding context (other files, callers/callees) to understand impact.
3. Checks against all applicable rule modules (generic + language-specific).
4. Assesses test coverage — new code paths covered? Flags gaps with suggested test scenarios.
5. **Applies scope** — under `--scope diff` (default), reports only diff-attributable findings; context-only code is not flagged. Under `--scope project`, flags pre-existing issues too.

Collect all subagent results into a single findings list (barrier) before Step 2.

> Concurrency: cap concurrent subagents (≈8). Group tiny related files into one subagent. Subagents are read-only — safe in parallel.

### Step 2 — Cross-file analysis

Sequential — **barrier**: needs all Step 1 findings. Analyze cross-cutting concerns (same scope rule applies):

- Breaking changes across module boundaries
- Consistency of patterns across the diff (naming, error handling, API contracts)
- Missing migrations, config changes, or dependency updates implied by code changes
- Potential race conditions or state management issues across components

### Step 3 — Build & test verification

After analysis, verify the change builds and passes. Detect project type from root files. Run from repo root.

**Working tree safety — stash discipline:**
- Review operates on the committed diff (`<base>...HEAD`). Build/test may need a clean tree.
- **Initialize `STASHED=0`** (default: nothing stashed).
- Unique fingerprint: `FP="review-code-$(date +%Y%m%d-%H%M%S)-$$"`. Stash message embeds it: `git stash push -u -m "$FP"`.
- `git status --porcelain`: clean → leave `STASHED=0`; dirty → `git stash push -u -m "$FP"`, set `STASHED=1`.
- **Only pop if `STASHED=1`.** Never pop a stash this run did not create. Pop by fingerprint, not position:
  ```bash
  REF=$(git stash list | grep -F "$FP" | head -n1 | sed -E 's/^(stash@\{[0-9]+\}):.*/\1/')
  [ -n "$REF" ] && git stash pop "$REF"
  ```
- Restore in cleanup too (on error, still pop by fingerprint when `STASHED=1`). Empty `$REF` → warn, do not blind-pop.

**Node.js project** (root has `package.json`):
1. `npm ci`. Fails → record build failure, stop verification.
2. `npm run build` if the script exists. Fails → record build failure, stop verification.
3. `npm run test` — **only if zero medium-or-higher findings**. If `test` script absent, note skipped.

**Spring Boot Maven project** (root has `pom.xml`):
1. `mvn clean verify` — **only if zero medium-or-higher findings**.

Gate logic: count `medium`+`high`+`critical` findings. >0 → **skip test/verify**, note `Tests skipped — N medium+ findings to address first` (still run install + build for Node). ==0 → run full test/verify.

Other project types: skip, note `No recognized build system — verification skipped`. Quote exact error output on failure; build failures reported as 🔴 critical.

### Step 4 — Output

**All output formats live in `platforms/comment.md`** — single source for both the local report and PR/MR comments. Do not redefine templates here. Follow `platforms/comment.md`, in order:

1. Top-level summary — header exactly `## 🤖 Code review`, then the findings table.
2. Detailed findings — one block per finding, grouped by dimension.
3. Missing test coverage — table.
4. Build & test verification — table (from Step 3).
5. Watermark footer — end the report with the configurable watermark:
   `🤖 $(bash "<skill-dir>/scripts/watermark.sh")`. PR/MR comments get it automatically via
   `post-comment.sh` (the platform libs wrap each body with `decorate_body`).

Apply `--severity` filter to what's shown. Then persist locally (below).

As the final user-facing line of the run, print the console watermark:
`bash "<skill-dir>/scripts/watermark.sh" --banner`. The watermark text is configurable in
`<repo-root>/supensour-config.yaml` (`watermark_template`, or per-skill `skills.review-code`).

#### Local persistence (always)

Always save the review to disk so it survives a missing PR/MR and can be pushed later:

```
.supensour/review-code/
├── <branch>/                          # sanitized SRC (slashes → -)
│   ├── comments/
│   │   ├── <timestamp>.md             # human-readable report (this output)
│   │   └── <timestamp>.json           # machine-readable findings for deferred push
│   └── latest.json -> comments/<timestamp>.json   # pointer to the most recent review
└── worktrees/                         # throwaway review worktrees (see Preflight)
```

- `<branch>` = sanitized `SRC` (slashes → `-`). `<timestamp>` = `YYYYMMDD-HHMMSS`.
- JSON holds each finding `{severity, file, line, dimension, title, problem, impact, fix, test_suggestion}` plus `{base, head_sha, branch, platform, worktree}` metadata so a later push maps comments to the right lines.
- Add `.supensour/review-code/` to `.gitignore` if not present (ignores reviews + worktrees; keeps `.supensour/config/` committable).
- Print: `💾 Saved review to .supensour/review-code/<branch>/comments/<timestamp>.md`.
- **If the review was not pushed** (default run without `--push`, or `--push` skipped because no PR/MR
  or token), also print how to post it later:
  `↪ Not posted. To push to the PR/MR later: /review-code --push-saved` (uses the latest saved review for this branch).

### Step 5 — PR commenting

Two entry paths:

**A. Live push (`--push`)** — uses findings from this run (Step 4), PR/MR from Step 0.

**B. Deferred push (`--push-saved [path]`)** — skips analysis (Steps 1–4). Loads findings from saved JSON:
- `path` given → use that file. No path → `.supensour/review-code/<SRC>/latest.json`.
- Re-resolve platform + PR/MR (Step 0 scripts). Validate saved `head_sha` vs current `HEAD`; if drifted, warn (`⚠ Saved review was for <old_sha>, HEAD is now <new_sha> — line positions may be stale`) and continue.

Both paths then, **in this order**:

1. **Require PR/MR resolved.** None found → **keep local copy**, warn, skip: `⚠ No open PR/MR for branch — review saved locally. Re-run with --push-saved when PR/MR exists.` Token missing/auth fail → same.
2. **Prune prior comments** (always, before posting) — remove this skill's own earlier comments so re-runs don't stack:
   ```bash
   bash "<skill-dir>/scripts/prune-comments.sh" "$PR" [--platform <key>]   # → 🧹 Removed N stale review comment(s)
   ```
   Auth/permission failure here → warn, continue to post.
3. **Post the top-level summary** (first):
   ```bash
   bash "<skill-dir>/scripts/post-comment.sh" summary "$PR" <summary-body-file> [--platform <key>] [--head <sha>]
   ```
4. **Post each finding inline** — `post-comment.sh inline` applies the **line → file-level → summary** fallback automatically (see `platforms/comment.md`). Prints the level used per finding:
   ```bash
   bash "<skill-dir>/scripts/post-comment.sh" inline "$PR" <path> <line> <body-file> [--platform <key>] [--head <sha>]
   ```
   Post inline comments in parallel batches (≈5 concurrent) where the platform is one-call-per-finding (GitLab/Bitbucket), respecting `Retry-After`.
5. On success, mark the saved JSON `pushed: true` with the PR/MR URL (avoid double-posting). Then, if a worktree was kept (`worktree` path still exists), remove it: `bash "<skill-dir>/scripts/worktree.sh" remove <worktree>`.

## Severity definitions

| Level | Icon | Meaning | Action |
|-------|------|---------|--------|
| critical | 🔴 | Security vulnerability, data loss risk, financial exposure | Must fix before merge |
| high | 🟠 | Bug, significant design flaw, missing validation at boundary | Should fix before merge |
| medium | 🟡 | Performance issue, maintainability concern, weak error handling | Fix soon, can merge with plan |
| low | 🟢 | Minor improvement, better naming, slight duplication | Nice to have |
| info | ℹ️ | Observation, architectural note, learning opportunity | No action needed |

## Reviewer persona

Review as a software engineer / architect with 10 years experience:

- **Pragmatic** — flag real problems, not style preferences. No formatting nitpicks.
- **Business-aware** — consider financial impact, user experience, data integrity.
- **Constructive** — every finding includes a concrete fix, not just "this is bad."
- **Proportional** — severity matches actual risk. No crying wolf.
- **Context-sensitive** — understand codebase conventions before flagging deviations.
- **Test-minded** — always ask: "how would I verify this works and keeps working?"
- **Scope-disciplined** — under `--scope diff`, don't drag in pre-existing issues you noticed while reading context.

## Rule loading

1. Always load `rules/generic.md` — applies to all languages.
2. Detect languages from file extensions in the diff:
   - `.vue`, `.ts`, `.js`, `.tsx`, `.jsx` → also load `rules/vue.md`
   - `.java`, `.kt`, `.xml` (pom/spring config) → also load `rules/springboot.md`
   - `.java` files matching `migrations/Migration_*.java` → also load `rules/data-migration.md` (additive to springboot)
3. `--lang` flag forces specific rulesets (additive to generic). Defaults to the per-repo `project.language` hint (`.supensour/config/config.yaml`) when the flag is absent, else auto-detect from extensions.
4. Add a new language: create `rules/<language>.md` following the existing format; add the extension mapping above.

## Edge cases

- **Empty diff**: Report "No changes to review" and exit.
- **Binary files**: Skip with note "Binary file skipped: <path>".
- **Very large diffs (>2000 lines changed)**: Focus critical/high. Note reduced depth. Suggest splitting the PR.
- **No PR exists**: Local review saved (diff still computed). `--push` warns, keeps local copy. Re-run `--push-saved` later.
- **`--branch` not found**: Error `Branch <SRC> not found locally or on origin.` and exit before any worktree/diff work.
- **Platform auth failure**: Clear error with setup instructions, keep local copy, continue with local output.
- **`--push-saved` with no saved review**: Error `No saved review found for branch <branch>. Run /review-code first.` and exit.
- **`--push-saved` already pushed**: If saved JSON has `pushed: true`, warn `Already pushed to <url>. Re-run review to regenerate.` and skip.
- **Stash not ours**: Never pop unless this run created the stash (`STASHED=1`).
- **Dirty working tree**: Per Preflight — ask to use a new worktree or abort. Never review or mutate the dirty tree directly.
- **Worktree cleanup fails**: Warn with the path for manual `worktree.sh remove`. Don't block the report.
- **Worktree kept (unpushed)**: Keep + record path in saved JSON. Removed only after a later `--push-saved` succeeds (or manually).
