---
name: review-code
description: Architect-level code review of a branch/PR diff across languages (Vue, Spring Boot, extensible). Reviews security, architecture, performance, quality, business/financial impact, and test gaps. Diff-scoped by default. Outputs a local report and optionally posts inline comments to GitHub/GitLab CE/Bitbucket PRs, reconciling its own prior comments (dedup unchanged, update changed, resolve fixed) and never deleting them. Use for "review this PR/MR", "review my diff", "code review before merge".
argument-hint: "[--branch <branch>] [--push] [--push-saved <path>] [--clean <branch>] [--clean-all] [--platform <key>] [--base <branch>] [--files <glob>] [--severity <list>] [--lang <key>] [--scope diff|project] [--pool <n>] [--analyst-model <key>] [--executor <file>] [--explain] [--help]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, WebFetch, AskUserQuestion, Agent, Skill
---

# review-code

Code review skill. Reviews diffs like a 10-year architect — security, architecture, performance, quality,
business impact. Supports Vue, Spring Boot, extensible to any language.

> **Scripts do the CLI work.** All git/platform/API commands live in `scripts/` (see `platforms/detect.md`
> + `platforms/comment.md`). Call them as `bash "<skill-dir>/scripts/<name>.sh" …` rather than re-emitting
> commands — they print compact JSON/TSV to parse.
>
> **Load only your role's file.** This file is the router; the process lives in `roles/`. Never read a role
> file that isn't yours — that's the point of the split.

## Invocation

```
/review-code                          # review current branch's PR (diff-scoped)
/review-code --branch feature/RANCH-1 # review another branch's PR
/review-code --push                   # also post comments to PR (reconciles: dedup/update/resolve — never deletes)
/review-code --platform gitlab-ce     # override platform detection
/review-code --base main              # explicit base branch
/review-code --files src/api/         # scope to specific paths (repeatable glob)
/review-code --severity critical,high # filter output severity
/review-code --scope project          # review whole project, not just the diff
/review-code --pool 4                 # max concurrent analysts (default: min(8, 30% of cores))
/review-code --analyst-model sonnet   # model for analysts (default: sonnet)
/review-code --executor src/api/auth.ts  # analyst mode: review one file, no dispatch
/review-code --explain                # print resolved config (platform, PR, base, files, models) and stop
/review-code --push-saved             # push a previously saved local review to PR/MR
/review-code --clean                  # delete saved local reviews for current branch
/review-code --clean feature/RANCH-1  # …for a branch
/review-code --clean-all              # …for every branch
/review-code --help                   # print usage and exit
```

**Utility flags run a script and stop** — no review is performed:
- `--help` → `bash "<skill-dir>/scripts/help.sh"`, print output, stop.
- `--clean [branch]` → `bash "<skill-dir>/scripts/clean.sh" [branch]` (default: current branch), stop.
- `--clean-all` → `bash "<skill-dir>/scripts/clean.sh" --all`, stop.
- `--explain` → `bash "<skill-dir>/scripts/explain.sh"` resolves the mechanical part (external deps, git
  state, platform, build/test commands, pool) as TSV; the orchestrator renders it and adds PR/MR, file set,
  languages and models (`roles/orchestrator.md` Step 0.6). Stops before Step 1 — no subagents, no writes.

## External dependencies

```bash
bash "<skill-dir>/scripts/deps.sh"   # TSV: <cmd>  <ok|MISSING|absent (optional)>  <path|install hint>
```

`git`, `jq` and `curl` are **required** — every platform lib parses API JSON with `jq` and calls the API
with `curl`, so `init_platform` checks them and dies with an install hint rather than failing mid-request.
`gh` is optional (GitHub PR lookup fallback when no token is set). Exit 3 = a required tool is missing.

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
| `--files <glob>` | all changed | One or more globs (repeatable) — scope the review to matching paths. Passed to `collect-diff.sh --path`, never filtered by hand. Dialect: `*` (not across `/`), `**`, `?`, `[abc]`, `{a,b}`; a bare directory means its subtree. Shared with create-tests (`lib/core.sh` → `normalize_globs`) |
| `--severity <list>` | all | Filter: `critical`, `high`, `medium`, `low`, `info` |
| `--lang <key>` | auto-detect | Force language ruleset: `vue`, `springboot`, `data-migration`, `generic` |
| `--scope <diff\|project>` | `diff` | `diff`: only flag issues in/caused by the diff. `project`: review the whole project |
| `--pool <n>` | `min(8, floor(cores * 0.3))`, min 1 | Max concurrent analyst subagents, global across the run |
| `--analyst-model <key>` | `sonnet` | Model for analyst subagents. `inherit` = session model. Alias: `--agent-model` |
| `--executor <file>` | off | **Analyst mode**: review exactly this one file (see [Roles](#roles)). Dispatched analysts invoke the skill this way |
| `--explain` | off | Print the resolved run config and stop |
| `--clean [branch]` | current branch | Delete saved local reviews (comments + kept worktrees) for a branch, then stop |
| `--clean-all` | — | Delete all saved local reviews (`.supensour/review-code/`), then stop |
| `--help` | — | Print usage (`scripts/help.sh`) and stop |

Models are passed as the Agent call's `model` parameter — never pinned in the agent definitions, so the
skill stays host-agnostic.

Local copy of every review is **always saved** (regardless of `--push`), so findings are never lost when a
PR/MR isn't available yet — see `roles/orchestrator.md` → Local persistence.

## Roles

Two roles, one chain: **orchestrator → analyst (one per changed file)**.

| Role | Entered by | Reads | Process | Model |
|------|-----------|-------|---------|-------|
| **Orchestrator** | `/review-code` without `--executor` | scripts + `rules/*` for the summary pass; never a full file's review body | [`roles/orchestrator.md`](roles/orchestrator.md) | the user's session model |
| **Analyst** | the skill with `--executor <file>` | `rules/*` for its language, the file's diff, surrounding context | [`roles/analyst.md`](roles/analyst.md) | `--analyst-model` (default `sonnet`) |

Agent type: `supensour-review-analyst`. If the host doesn't resolve it (non Claude Code plugin hosts),
dispatch `general-purpose` with the same prompt and the same `model` parameter — behavior is identical.

Analysts return **structured findings only** (one JSON object per finding), never prose, so the
orchestrator's context grows with findings, not with file contents.

## Build & test commands

Step 3 never hand-writes a build command — `scripts/verify.sh` resolves and runs all three steps:

```bash
bash "<skill-dir>/scripts/verify.sh" [--skip-tests] [--print]
# TSV: <step>  <command|->  <PASS|FAIL|SKIPPED|NONE>  <exit|->
```

| Step | Config key (`<repo>/.supensour/config/config.yaml`) | Detected default |
|---|---|---|
| install | `project.install_command` | node → `npm ci`; maven/gradle → none needed |
| build | `project.build_command` | `npm run build` (if the script exists) · `mvn -B clean compile` · `./gradlew build -x test` |
| test | `project.test_command_all` | `npm run test` (if the script exists) · `mvn -B clean verify` · `./gradlew test` |

These are **whole-project** commands — no placeholders. Per-file scoped commands
(`project.test_command`, `project.test_command_coverage`, which take `{spec}`) belong to create-tests; using
one here runs `{spec}` literally and the script warns. Every command passes the shared allowlist
(`npm`, `yarn`, `pnpm`, `bun`, `npx`, `node`, `vitest`, `jest`, `mvn`, `gradle`, `gradlew`, `make`) and is
echoed before it runs, so a cloned repo's config can't execute arbitrary shell. Extend deliberately via
`SUPENSOUR_ALLOWED_CMDS`.

## Review scope (`--scope`, default `diff`)

- **`diff` (default)** — Review the changes. **Read freely** around the diff — related functions in other
  files, callers, callees, types — to understand intent and impact. But only **raise findings that are
  introduced by, or directly broken by, the diff.** Do **not** report pre-existing issues in untouched
  code, even when you read it for context. If a diff change breaks or depends on existing code, that
  *is* diff-attributable → report it.
- **`project`** — Lift the restriction. Review the whole project; pre-existing issues are in scope.

Threaded into every analyst dispatch and the orchestrator's cross-file pass.

## Safety — never destroy work

- **Banned, no exceptions**: `git clean`, `git reset --hard`, `git checkout -- .`, `git restore`,
  `git stash` (including `-u`), `git rm`, branch/ref switching outside a dedicated worktree, and `rm -rf`
  of anything the run didn't create. A `stash -u` sweeps *untracked* files — including specs another skill
  (e.g. `create-tests`) just generated. Nothing this skill does is worth that.
- **Isolation, not mutation**: when the tree is dirty or `SRC` ≠ checked-out branch, work in a git worktree
  (`scripts/worktree.sh`). If a worktree can't be created, **skip build/test verification** and say so —
  never clean or stash the user's tree to make verification possible.
- **Only the orchestrator and the analyst may dispatch** — the orchestrator dispatches analysts; analysts
  never dispatch. Analysts are **read-only**: no writes, no git state changes.
- `.gitignore` updates go through the script, never by hand:
  ```bash
  bash "<skill-dir>/scripts/gitignore.sh" '.supensour/review-code/'
  ```

## Severity definitions

| Level | Icon | Meaning | Action |
|-------|------|---------|--------|
| critical | 🔴 | Security vulnerability, data loss risk, financial exposure | Must fix before merge |
| high | 🟠 | Bug, significant design flaw, missing validation at boundary | Should fix before merge |
| medium | 🟡 | Performance issue, maintainability concern, weak error handling | Fix soon, can merge with plan |
| low | 🟢 | Minor improvement, better naming, slight duplication | Nice to have |
| info | ℹ️ | Observation, architectural note, learning opportunity | No action needed |

## Finding dimensions

Fixed vocabulary — **the only allowed values** for a finding's `dimension`. Every analyst emits one of
these, the report groups by them, and each finding's comment fingerprint is
`hash(file + dimension + title)`. Renaming or adding one changes every fingerprint, so a re-run stops
recognizing its own prior comments and posts duplicates. Treat this list as an interface, not a label.

| Dimension | Covers |
|---|---|
| `Security` | Auth/authz, injection, secrets, unsafe deserialization, XSS/CSRF, exposure |
| `Architecture` | Layering, coupling, contracts, misplaced responsibility, breaking changes |
| `Performance` | N+1, unnecessary work, blocking I/O, allocation/render churn, missing indexes |
| `Quality` | Correctness bugs, error handling, naming, dead/duplicated code, maintainability |
| `Business` | Financial exposure, data integrity, UX-breaking behavior, compliance |
| `Testing` | Missing or misleading coverage for changed paths |

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
   - `.vue`, `.ts`, `.js`, `.tsx`, `.jsx` → also load `rules/vue/index.md`
   - `.java`, `.kt`, `.xml` (pom/spring config) → also load `rules/springboot/index.md`
   - `.java` files matching `migrations/Migration_*.java` → also load `rules/data-migration/index.md`
     (additive to springboot)
3. `--lang` forces specific rulesets (additive to generic). Defaults to the per-repo `project.language`
   hint (`.supensour/config/config.yaml`) when the flag is absent, else auto-detect from extensions.
4. Add a language: create `rules/<lang>/index.md` (plus optional `rules/<lang>/cases/*.md` for recurring
   patterns) and add the extension mapping above. Same layout as create-tests.

## Extending

- **New language**: `rules/<lang>/index.md` (+ `cases/`), and register the extension map above.
- **New platform**: `scripts/lib/platform-<type>.sh` implementing the same functions as
  `platform-github.sh`; register the `type` in the global config schema. `platform_dispatch` routes by type.
- **New role**: `roles/<role>.md` + `agents/supensour-review-<role>.md` at the plugin root (no `model:` in
  the frontmatter — the dispatcher passes it).

## Edge cases

- **Empty diff**: report "No changes to review" and exit.
- **Binary files**: skip with note "Binary file skipped: <path>".
- **Very large diffs (>2000 lines changed)**: focus critical/high. Note reduced depth. Suggest splitting the PR.
- **No PR exists**: local review saved (diff still computed). `--push` warns, keeps local copy. Re-run `--push-saved` later.
- **`--branch` not found**: error `Branch <SRC> not found locally or on origin.` and exit before any worktree/diff work.
- **Platform auth failure**: clear error with setup instructions, keep local copy, continue with local output.
- **`--push-saved` with no saved review**: error `No saved review found for branch <branch>. Run /review-code first.` and exit.
- **`--push-saved` already pushed**: saved JSON has `pushed: true` → warn `Already pushed to <url>. Re-run review to regenerate.` and skip.
- **Dirty working tree**: per Preflight — use a worktree or abort. Never review, clean or stash the dirty tree.
- **Worktree unavailable**: analysis still runs on the committed diff; build/test verification is skipped with a note.
- **Worktree cleanup fails**: warn with the path for manual `worktree.sh remove`. Don't block the report.
- **Worktree kept (unpushed)**: keep + record path in saved JSON. Removed only after a later `--push-saved` succeeds (or manually).
- **`--executor` with more than one file**: unsupported — one analyst, one file.
