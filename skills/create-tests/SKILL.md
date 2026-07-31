---
name: create-tests
description: Generate tests for changed or specified source files across languages (Vue/Vitest, Spring Boot/JUnit5, extensible). Per-language conventions and test types (unit now; integration later). Writes minimum-viable specs following the project's naming/location conventions and can run them with scoped coverage. Use for "write tests for this", "create unit tests", "add test coverage for my diff".
argument-hint: "[--lang <key>] [--type unit|integration] [--files <glob>] [--base <branch>] [--coverage <n>] [--pool <n>] [--runs <n>] [--analyst-model <key>] [--writer-model <key>] [--no-split] [--executor <file>] [--explain] [--clean <branch>] [--clean-all] [--help]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent, Skill
---

# create-tests

Test-generation skill. Reads source files and emits **minimum-viable** tests following each language's
conventions. Supports Vue (Vitest) and Spring Boot (JUnit 5), extensible to any language.

> **Scripts do the CLI work.** Target detection, coverage scanning, path mapping and test running live in
> `scripts/`. Call them as `bash "<skill-dir>/scripts/<name>.sh" …` rather than re-emitting commands.
>
> **Load only your role's file.** This file is the router; the process lives in `roles/`. Never read a
> role file that isn't yours — that's the whole point of the split.

## Invocation

```
/create-tests                              # unit tests for changed source files (vs base)
/create-tests --files src/utils/money.ts   # tests for specific files
/create-tests --lang springboot            # force language
/create-tests --type unit                  # test type (default; integration = later)
/create-tests --coverage 90                # numeric gate threshold, every metric (default 100)
/create-tests --pool 4                     # max concurrent analysts (default: min(10, 30% of cores))
/create-tests --runs 6                     # test runs allowed per target, all roles (default 4)
/create-tests --analyst-model sonnet       # model for analysts (default: sonnet; alias --agent-model)
/create-tests --writer-model haiku         # model for writers (default: sonnet)
/create-tests --no-split                   # analyst writes the spec itself, no writer hop
/create-tests --executor src/utils/money.ts  # analyst mode: one file, no target detection
/create-tests --explain                    # print resolved config (targets, gate, commands, models) and stop
/create-tests --clean                      # delete saved plans for current branch
/create-tests --clean feature/RANCH-1      # …for a branch
/create-tests --clean-all                  # …for every branch
/create-tests --help                       # print usage and exit
```

**Utility flags run a script and stop** — no tests generated:
- `--help` → `bash "<skill-dir>/scripts/help.sh"`, print output, stop.
- `--clean [branch]` → `bash "<skill-dir>/scripts/clean.sh" [branch]` (default: current branch), stop.
- `--clean-all` → `bash "<skill-dir>/scripts/clean.sh" --all`, stop.

`clean` removes `<repo>/.supensour/create-tests/<branch>/` (the analyst plan files for that branch);
`--clean-all` removes the whole `.supensour/create-tests/` tree. Plans are scratch — deleting them never
touches generated specs.

## Input

| Flag | Default | Description |
|------|---------|-------------|
| `--lang <key>` | auto-detect | Force language ruleset: `vue`, `springboot`. Auto-detected from file extensions otherwise |
| `--type <unit\|integration>` | `unit` (or `project.test_type` config hint) | Test type. Only `unit` is supported now; `integration` → note "not yet supported" and stop |
| `--files <glob>` | changed files | One or more globs (repeatable) — see [Glob syntax](#glob-syntax). Default = source files changed vs `--base` |
| `--base <branch>` | auto-detect | Diff base for changed-file detection (`origin/HEAD` → `main`/`master`/`develop`) |
| `--coverage <n>` | `100` | **Numeric only.** The coverage bar, applied to **every** metric (vue: statements/branches/functions/lines; springboot: instructions/branches/methods/lines). Used both as the skip-gate threshold and as what the analyst writes cases to reach |
| `--pool <n>` | `min(10, floor(cores * 0.3))`, min 1 | Max concurrent analyst subagents, global across language groups. `1` = one target at a time |
| `--runs <n>` | `4` | Test runs allowed **per target**, counted across the analyst and every writer by `scripts/run-tests.sh`. Prevents a target from costing many full test+coverage cycles; raise it when a real gap needs more attempts |
| `--analyst-model <key>` | `sonnet` | Model for analyst subagents. `inherit` = session model. Alias: `--agent-model` |
| `--writer-model <key>` | `sonnet` | Model for writer subagents. `inherit` = session model. Cheaper tiers (`haiku`) are viable — the plan is near-transcription |
| `--no-split` | off | Skip the writer hop: the analyst writes the spec itself at `--analyst-model` |
| `--executor <file>` | off | **Analyst mode**: handle exactly this one target (see [Roles](#roles)). Dispatched analysts invoke the skill this way |
| `--explain` | off | Print the resolved run config — language, targets, coverage-gate verdicts, resolved test commands, pool size, models — and stop before dispatch. No subagents, no writes |
| `--clean [branch]` | current branch | Delete saved plans for a branch, then stop |
| `--clean-all` | — | Delete everything under `.supensour/create-tests/`, then stop |
| `--help` | — | Print usage (`scripts/help.sh`) and stop |

Models are passed as the Agent call's `model` parameter — never pinned in the agent definitions, so the
skill stays host-agnostic.

## Glob syntax

`--files` (and review-code's `--files` / `collect-diff.sh --path`) share one dialect, implemented once in
`lib/core.sh` (`normalize_globs` / `expand_globs`) — shell-like, **not** git's default pathspec:

| Pattern | Matches |
|---|---|
| `*` | any run of characters, **does not cross `/`** — `src/*.ts` |
| `**` | any number of path segments — `src/**/*.vue` |
| `?` | exactly one character |
| `[abc]` | one character from the set |
| `{a,b}` | alternatives — `src/**/*.{ts,vue}` (expanded by us; git pathspec has no braces) |
| `src/api` or `src/api/` | a directory means its whole subtree (`src/api/**`) |

Matching unions tracked files, untracked files on disk, and a literal path — a brand-new source file that
git has never seen is the common case for `--files`. Quote patterns so the shell doesn't expand them first;
an unquoted `{a,b}` is expanded by your shell into separate arguments, which still works.

**How tests are run** (all roles use the same resolution — never hand-write a runner command):
```bash
bash "<skill-dir>/scripts/test-command.sh" <lang> coverage --spec <spec>... --source <src>...  # print it
bash "<skill-dir>/scripts/run-tests.sh"    <lang> <spec> [--coverage <source-file>]            # run it
```

`run-tests.sh` is the **only** way a spec is run while generating — the plan's `Run:` line is that command.
It keeps a per-target ledger under `.supensour/create-tests/<branch>/.runs/` and refuses past `--runs <n>`
(default 4) with exit 5, because each role can only see its own cap (writer: 2 runs, analyst: 2 dispatches)
and the per-target total was otherwise unbounded. A raw `npx vitest` / `mvn` invocation bypasses the counter
— don't.

## Outcomes

Every target ends as exactly one of these, and the difference matters to the next run:

| Outcome | Tests | Coverage | Meaning |
|---|---|---|---|
| `PASS` | green | at threshold | Done |
| `PARTIAL` | **green** | short of threshold | The remaining code is **not reachable by a test** — an impossible guard, a defensive `default:`, a platform-specific path. Reported with `uncovered=<file>:<line>` + why. A delivered spec, never re-dispatched |
| `FAIL` | failing/erroring | — | A test fails, or the spec couldn't be produced. Reported with the reason, failing case names and the plan path |

`PARTIAL` exists so unreachable code isn't laundered into either lie: `PASS` would claim a bar was met,
`FAIL` would send the next run chasing a number no test can move. The analyst decides it **by reading the
source** — never by writing a probe case to see whether the number budges, then reverting it.
Resolution order: `project.test_command` / `project.test_command_coverage` in
`<repo>/.supensour/config/config.yaml` → the `package.json` script that runs vitest (`test:unit`,
`test:vitest`, `test`, else any script mentioning vitest) → `npx vitest run`; for springboot, `pom.xml` →
`mvn`, `build.gradle[.kts]` → `./gradlew`. Placeholders in the config commands:

| Placeholder | Expands to |
|---|---|
| `{spec}` | test file(s), space-joined |
| `{classes}` | test class name(s), comma-joined (springboot) |
| `{coverage_args}` | one scope flag per source (`--coverage.include=a --coverage.include=b`) |
| `{reporter_args}` | the gate's machine-readable reporter (`--coverage.reporter=json-summary --coverage.reportsDirectory=<tmp>`); empty on plain runs. Omit it and the gate appends the flags at the end — a piped/chained command must place it itself |
| `{source}` | bare source path(s) — safe only when the run scopes a **single** source; the gate scopes many, so it wants `{coverage_args}` |

Per-stack examples live in the generated config and in
[`examples/project-config.template.yaml`](../../examples/project-config.template.yaml).

**Spec location** follows the test type, not just whatever exists: `unit` → `test/unit/specs` (then
`test/unit`, `tests/unit`), `integration` → `test/integration` (then `tests/integration`, `test/e2e`). If none
of those dirs exist, the root that **most** existing specs share wins (ties → shortest path), else the type's
default. `spec-path.sh --type <t>` / `test-command.sh --type <t>` override the resolved type.

## Roles

Three roles, one chain: **orchestrator → analyst (one per target) → writer (one per attempt)**. Each role
reads this file plus **only its own** role file, and nothing else.

| Role | Entered by | Reads | Process | Model |
|------|-----------|-------|---------|-------|
| **Orchestrator** | `/create-tests` without `--executor` | no rules, no source, no plans, no specs | [`roles/orchestrator.md`](roles/orchestrator.md) | whatever the user is on |
| **Analyst** | the skill with `--executor <file>` | `rules/*`, the source, one neighbor spec (+ the target spec when appending) | [`roles/analyst.md`](roles/analyst.md) | `--analyst-model` (default `sonnet`) |
| **Writer** | dispatch prompt from an analyst (agent `supensour-test-writer`) | the plan file + the source | [`roles/writer.md`](roles/writer.md) | `--writer-model` (default `sonnet`) |

Token discipline that makes this worth it:
- The orchestrator never ingests a plan or a spec body — its context stays flat no matter how many targets.
- Rules are loaded **once per target**, by the analyst only. The writer loads **no rules at all**: the plan
  carries the concrete form (exact spec path, watermark line verbatim, imports, case titles, mocks).
- Every report between roles is one fixed-format line. No prose, no spec bodies, no restating the plan.

Agent types: `supensour-test-analyst`, `supensour-test-writer`. If the host doesn't resolve them (non
Claude Code plugin hosts), dispatch `general-purpose` with the same prompt and the same `model` parameter —
behavior is identical.

## Safety — never destroy other agents' work

Concurrent agents share one working tree, so one destructive command can delete every spec written so far.
Hard rules for **all roles**:

- **Banned, no exceptions**: `git clean`, `git reset --hard`, `git checkout -- .`, `git restore`,
  `git stash`, `git rm`, branch/ref switching, `rm -rf`, and any command that deletes or reverts files the
  run did not itself create. Cleaning up untracked junk is **never** part of this skill's job.
- **Protect on write**: the moment a spec is written, index it so `git clean -fd` cannot reach it:
  ```bash
  bash "<skill-dir>/scripts/protect.sh" <spec-path>...   # git add -N (intent-to-add, content stays unstaged)
  ```
  Writer/analyst run it on their own spec; the orchestrator re-runs it over every reported spec at the end.
- **Integrity check**: `protect.sh` prints `✖ MISSING <path>` and exits `3` for any path absent from disk.
  A spec reported as written but missing is an incident: report it explicitly (which files, when), then
  re-dispatch those targets — never silently succeed. It prints `⚠ UNPROTECTED <path>` when a spec can't be
  indexed (usually gitignored) — surface that in the run summary; that file is still deletable.
- Fixing a failing spec means editing that spec. Never "reset the repo to a clean state" to recover.
- `.gitignore` changes go through the script, never by hand:
  ```bash
  bash "<skill-dir>/scripts/gitignore.sh" '.supensour/create-tests/'   # idempotent, logs what it appends
  ```
  (`plan-path.sh` already calls it for you.)
- Commands from a target repo's `project.test_command*` are **allowlisted** before they run (`npm`, `yarn`,
  `pnpm`, `bun`, `npx`, `node`, `vitest`, `jest`, `mvn`, `gradle`, `gradlew`, `make`). Anything else aborts
  with the offending word — a cloned repo can't make this skill run arbitrary shell. Extend deliberately via
  `SUPENSOUR_ALLOWED_CMDS` if you trust the repo.
- **Dispatch rule**: only the orchestrator and the analyst may call the Agent tool — the orchestrator
  dispatches analysts, an analyst dispatches **at most 3 writers for its own single target, one at a
  time**. Writers never dispatch. Nobody touches a file outside its own target's spec.

## Rule loading (analyst only)

1. Always load `rules/generic.md`.
2. Resolve language from extensions (or `--lang`):
   - `.vue`, `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` → `vue`
   - `.java`, `.kt` → `springboot`
3. Load `rules/<lang>/index.md` + `rules/<lang>/types/<type>.md` + matching `rules/<lang>/cases/*`.

## Conventions summary (see rules/ for detail)

| Language | Framework | Spec name | Location | Run |
|----------|-----------|-----------|----------|-----|
| vue | Vitest + @vue/test-utils | `<name>.spec.ts` | mirror source under test root (e.g. `test/unit/specs/`) | `npm run test:unit -- run <spec> --coverage --coverage.include=<src>` |
| springboot | JUnit 5 + Mockito | `<Class>Test.java` | `src/test/java/` mirroring package | `mvn test -Dtest=<Class>` |

## Extending

- **New language**: create `rules/<lang>/index.md` + `rules/<lang>/types/unit.md` (+ `cases/` as needed),
  and `scripts/lib/lang-<lang>.sh` exposing `<lang>_spec_path`, `<lang>_run_tests` and
  `<lang>_coverage_scan` (same signatures as `lang-vue.sh` / `lang-springboot.sh`; a `coverage_scan` that
  emits `GENERATE` for every input is a valid no-op). Register the extensions in `detect_lang` in
  `scripts/lib/common.sh`. No other file changes — `lang_dispatch` routes by language.
- **New test type**: add `rules/<lang>/types/<type>.md` and accept the `--type` value.
- **New role**: add `roles/<role>.md` and a matching `agents/supensour-test-<role>.md` (no `model:` in the
  frontmatter — the dispatcher passes it).

## Edge cases

- **No targets**: `No source files to test.` and exit.
- **All targets already covered**: coverage gate returns all `SKIP` → report and exit, no subagents.
- **Coverage scan unusable** (no build system, failing existing specs, no JaCoCo/`json-summary`, no
  `node`): every target is marked `GENERATE` — the gate never skips on missing data.
- **Mixed languages in target set**: group by language for the gate; the dispatch pool stays **global**
  (one pool for the whole run, not one per group). The analyst resolves rules per target anyway.
- **`--type integration`**: not yet supported — note and exit (structure is ready under `types/`).
  Both the orchestrator **and** the analyst check this, so a direct `--executor` call bails too.
- **Spec already exists**: surface it; append cases instead of overwriting silently. The analyst reads the
  existing spec before planning (`new|append` in every report line).
- **Source files under a test path** (e.g. `src/tests/factory.js`): `detect-targets.sh` skips them and logs
  `⚠ skipped N candidate(s) matching test paths: …` — pass them via `--files` if they really are sources.
- **Spec vanished after being reported written**: destructive-git incident — report which files and
  re-dispatch those targets. Do not report success.
- **Writer keeps failing**: bounded — 2 runs per dispatch, ≤2 plan revisions, then the analyst repairs the
  spec itself, then `FAIL` with exact output. Never an open loop.
- **`--executor` with more than one file**: unsupported — one analyst, one target.
