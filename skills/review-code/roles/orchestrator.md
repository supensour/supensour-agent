# Role — orchestrator

Entered by `/review-code` **without** `--executor`. You resolve the PR/base/diff, dispatch one analyst per
changed file, do the cross-file pass, verify the build, and produce + persist + push the report.

Read `SKILL.md` (flags, roles, severity, persona, safety) + this file + the rule modules for the diff's
languages. Never read `roles/analyst.md`.

## Preflight — working tree isolation

Resolve the source branch `SRC` first: `--branch` if given, else current branch.

A worktree is **required** when either holds:
- **`SRC` ≠ currently checked-out branch** — verification must run `SRC`'s code, not whatever is checked out.
- **Working tree is dirty** — never mutate the user's uncommitted work (see SKILL.md → Safety: no stash,
  no clean, ever).

```bash
bash "<skill-dir>/scripts/worktree.sh" status "$SRC"   # → {current, src, dirty, needs_worktree}
```

`SRC` == current AND tree clean → proceed to Step 0 in place.

When a worktree is needed:
- **Dirty** (and `SRC` == current) → **stop and ask** (AskUserQuestion):
  1. **Use a new worktree (recommended)** — review committed state in isolation, working tree untouched.
  2. **Abort** — user commits/stashes manually, re-runs.

  Never stash on the user's behalf. Never proceed in the dirty tree.
- **`SRC` ≠ current** → create the worktree automatically (the user explicitly asked for another branch).

```bash
WT="$(bash "<skill-dir>/scripts/worktree.sh" ensure "$SRC")"   # prints worktree path
```
- `ensure` ignores `.supensour/review-code/` before it creates anything — the worktree is never
  briefly visible as untracked. Don't pre-call `gitignore.sh` here.
- Run every later step **from `$WT`**.
- Persistence still writes to the **original repo's** `.supensour/review-code/`, so saved reviews survive
  worktree cleanup.
- **Cleanup** — conditional:
  - Comments pushed (or nothing pending) → `bash "<skill-dir>/scripts/worktree.sh" remove "$WT"`.
  - **Not pushed but a local copy saved** → **keep** the worktree; it preserves the reviewed HEAD for a later
    `--push-saved`. Tell the user: `📂 Worktree kept at <WT> — review not pushed. Re-run --push-saved from
    there, then remove with: scripts/worktree.sh remove <WT>`.
  - Record the path in the saved JSON (`worktree` field).
- `worktree.sh ensure` fails → report it, offer Abort, and if the user continues, **skip Step 3
  verification**. Do not clean/stash to force it.

## Step 0 — Context

0. **Resolve `SRC`** (above). `--branch` given but absent locally and on remote → error, exit.
1. **Ensure config exists** (idempotent):
   ```bash
   bash "<skill-dir>/scripts/init-config.sh"   # ~/.supensour/config/supensour.yaml + <repo>/.supensour/config/config.yaml
   ```
2. **Resolve platform + PR/MR + base** (sequential — each needs the prior):
   ```bash
   bash "<skill-dir>/scripts/detect-platform.sh" [--platform <key>]      # → platform JSON (incl. base_branch, language hints)
   PRS_JSON="$(bash "<skill-dir>/scripts/fetch-pull-request.sh" --branch "$SRC" [--platform <key>])"
   ```
   `fetch-pull-request.sh` returns a JSON **array** of open PR/MRs for `SRC`. Branch on the count:
   - **0** → **stop and ask**: (1) review against the default branch, local only; (2) abort.
   - **1** → use it. Report number, URL, title, `[source] -> [target]`. Capture its **base**.
   - **>1** → **stop and ask** which, one option per PR (`#<n> — <title> · [source] -> [target]`) + Abort.

   (No token but a PR exists → continue local review, skip push.)
3. **Base branch** priority: `--base` → project `git.base_branch` → PR/MR `base` → repo default
   (`origin/HEAD` → `main`/`master`/`develop`).
4. **Collect diff** — pass `--files` straight through as `--path`; never filter the file list by hand:
   ```bash
   bash "<skill-dir>/scripts/collect-diff.sh" "$BASE" "$SRC" [--path <glob>...]   # name-status + full diff
   ```
   Globs are the shared dialect (`* ? [] ** {a,b}`, bare directory = subtree — SKILL.md → Input).
   Empty result → `No changes to review.`, exit.
5. **Load rules** for the detected languages in one parallel batch (`rules/generic.md` +
   `rules/<lang>/index.md` per SKILL.md → Rule loading).
6. **`--explain`** → one script resolves everything mechanical; don't re-derive it in prose:
   ```bash
   bash "<skill-dir>/scripts/explain.sh" [--branch "$SRC"] [--base "$BASE"] [--platform <key>] [--pool <n>]
   # TSV: <section>  <key>  <value>   — sections: deps, git, platform, commands, pool
   ```
   Render it as a table, then append what only you know: PR/MR (from step 2), changed-file count + list,
   detected languages + rule modules, analyst model, worktree path, push mode. **Stop** — no dispatch, no
   writes. A `MISSING` row in `deps` means `--push`/PR lookup will fail; say so explicitly.

## Step 1 — Dispatch analysts (bounded pool)

Changed files are independent. One analyst per file (group tiny related files), through a pool:

1. **Pool size**: `--pool <n>` if given (clamp `>= 1`), else `min(8, floor(cores * 0.3))`, min 1; cap at the
   number of queued files. One pool for the whole run.
   ```bash
   cores=$(bash -c '. "<skill-dir>/scripts/lib/common.sh"; cpu_cores')   # nproc · sysctl · NUMBER_OF_PROCESSORS
   pool=$(( cores*30/100 )); pool=$(( pool<1 ? 1 : pool )); pool=$(( pool>8 ? 8 : pool ))
   ```
2. **Report before dispatch**: file count + list, pool size, analyst model, scope mode.
3. **Fill, then top up on every completion** — queue FIFO, dispatch `min(pool, queue.length)` at once
   (`subagent_type: supensour-review-analyst`, `model: <--analyst-model>`, backgrounded). The instant one
   finishes, dispatch the next. Log `reviewing <file> (k/total)` / `<file> done (k/total, n findings)`.
4. **Dispatch prompt** — don't paraphrase the rules; make the analyst load the skill itself:
   ```
   Repo: <repo-root or worktree path>
   Invoke the skill `supensour:review-code` with arguments:
     --executor <file> [--lang <lang>] --scope <diff|project> [--base <base>]
   You are the ANALYST for exactly this one file. Follow roles/analyst.md in that skill.
   Return findings as one JSON object per line (schema in roles/analyst.md) and nothing else.
   ```
5. Collect all findings (barrier — Step 2 needs the full set).

## Step 2 — Cross-file pass

Sequential, needs all Step 1 findings. Same `--scope` rule. Look for what a per-file analyst cannot see:

- Breaking changes across module boundaries
- Inconsistent patterns across the diff (naming, error handling, API contracts)
- Missing migrations, config changes or dependency updates implied by the code changes
- Race conditions / state-management issues spanning components

## Step 3 — Build & test verification

One script owns the commands — never hand-write `npm`/`mvn`/`gradle` invocations here:

```bash
bash "<skill-dir>/scripts/verify.sh"               # install → build → whole test suite
bash "<skill-dir>/scripts/verify.sh" --skip-tests  # install + build only (gate below)
bash "<skill-dir>/scripts/verify.sh" --print       # show the resolved commands, run nothing
```

It resolves each step from the repo config when set (`project.install_command`,
`project.build_command`, `project.test_command_all` — all unscoped, no `{spec}`), else from the detected
build tool (`package.json` → npm, `pom.xml` → mvn, `build.gradle[.kts]` → `./gradlew`). Every command passes
the shared allowlist and is echoed before running, so a repo config can't smuggle in arbitrary shell.

Output is a TSV table on stdout — runner output goes to stderr:
```
install   npm ci                  PASS      0
build     npm run build           PASS      0
test      npm run test            SKIPPED   -
```
`NONE` = nothing defined for that step (no `build` script, Maven needs no separate install) — not a failure.
A failed install or build marks the later steps `SKIPPED`; the script exits non-zero.

- **Findings gate**: count `medium`+`high`+`critical`. >0 → call it with `--skip-tests` and note
  `Tests skipped — N medium+ findings to address first` (install + build still run). ==0 → run it plain.
- **Working-tree rule**: the tree must already be clean — a worktree guarantees that. **Never stash, clean
  or reset to make verification possible.** Dirty tree and no worktree → skip this step entirely with
  `Verification skipped — working tree not isolated`.
- No recognized build system → the script emits `build-system - NONE -` and warns; report
  `No recognized build system — verification skipped`.
- Quote exact error output on failure. Build failures are 🔴 critical findings.

## Step 4 — Output + persistence

**All formats live in `platforms/comment.md`** — single source for the local report and PR/MR comments. Do
not redefine templates. In order:

1. Summary — header exactly `## 🤖 Code review`, then the findings table.
2. Detailed findings — one block per finding, grouped by dimension.
3. Missing test coverage — table.
4. Build & test verification — table (Step 3).
5. Watermark footer: `🤖 $(bash "<skill-dir>/scripts/watermark.sh")`. PR/MR comments get it automatically
   via `post-comment.sh` (`decorate_body`).

Apply `--severity` to what's shown. Then persist — **always**, regardless of `--push`:

```
.supensour/review-code/
├── <branch>/                          # sanitized SRC (slashes → -)
│   ├── comments/
│   │   ├── <timestamp>.md             # human-readable report
│   │   └── <timestamp>.json           # machine-readable findings for deferred push
│   └── latest.json                    # copy of the newest comments/<timestamp>.json
└── worktrees/                         # throwaway review worktrees
```

Write `latest.json` with the script — **never** `ln -s`, which needs admin rights on Windows and silently
becomes a copy under Git Bash:
```bash
bash "<skill-dir>/scripts/save-latest.sh" ".supensour/review-code/<branch>" "<…>/comments/<timestamp>.json"
```

- JSON: each finding `{severity, file, line, dimension, title, problem, impact, fix, test_suggestion}` plus
  `{base, head_sha, branch, platform, worktree}` metadata.
- Keep reviews out of git via the script (never edit `.gitignore` by hand):
  ```bash
  bash "<skill-dir>/scripts/gitignore.sh" '.supensour/review-code/'
  ```
- Print `💾 Saved review to .supensour/review-code/<branch>/comments/<timestamp>.md`.
- Not pushed → also print `↪ Not posted. To push to the PR/MR later: /review-code --push-saved`.
- Final user-facing line: `bash "<skill-dir>/scripts/watermark.sh" --banner`.

## Step 5 — PR commenting

**A. Live push (`--push`)** — findings from this run. **B. Deferred (`--push-saved [path]`)** — skip Steps
1–4, load saved JSON (`path`, else `.supensour/review-code/<SRC>/latest.json`), re-resolve platform + PR/MR,
and warn if `head_sha` drifted (`⚠ Saved review was for <old>, HEAD is now <new> — line positions may be
stale`).

Then, in order:

1. **Require a PR/MR.** None, or auth fails → keep the local copy, warn, skip:
   `⚠ No open PR/MR for branch — review saved locally. Re-run with --push-saved when PR/MR exists.`
2. **Build the reconcile manifest** — one markdown body file per comment (summary + one per finding, per
   `platforms/comment.md`), then a manifest JSON:
   ```json
   {
     "summary":  { "body_file": "<dir>/summary.md" },
     "findings": [
       { "file": "src/api/auth.ts", "line": 42, "dimension": "Security",
         "title": "SQL injection in user lookup", "body_file": "<dir>/f1.md" }
     ]
   }
   ```
   `file`+`dimension`+`title` is each finding's stable fingerprint — keep titles stable across re-runs.
3. **Reconcile — post without deleting**:
   ```bash
   bash "<skill-dir>/scripts/reconcile-comments.sh" "$PR" <manifest.json> [--platform <key>] [--head <sha>]
   # → ♻ Reconcile: 2 posted, 1 updated, 3 unchanged, 1 resolved (0 deleted)
   ```
   Never deletes. Unchanged findings are skipped, changed ones updated in place, new ones posted (inline →
   file-level → standalone; never merged into the summary), and findings no longer present are resolved.
   Auth/permission failure → warn, keep the local review, never abort hard. Report the reconcile line.

   Branch on the **exit code**, not on the text: `0` = reconcile ran · `4` = no token, nothing posted (keep
   the local copy, tell the user to set `$TOKEN_ENV` and re-run `--push-saved`) · `1` = usage error or the
   platform has no reconcile support. `post-comment.sh` uses the same `4`.
4. On success mark the saved JSON `pushed: true` with the PR/MR URL. If a worktree was kept, remove it now.

## Don'ts

- Don't run a destructive git command — no `stash`, `clean`, `reset --hard`, `checkout -- .` (SKILL.md → Safety).
- Don't review files yourself when an analyst can: your context should hold findings, not file bodies.
- Don't paraphrase rules into dispatch prompts; analysts load the rules themselves.
- Don't skip persistence because a push succeeded — the local copy is always written.
