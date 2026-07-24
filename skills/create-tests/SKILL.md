---
name: create-tests
description: Generate tests for changed or specified source files across languages (Vue/Vitest, Spring Boot/JUnit5, extensible). Per-language conventions and test types (unit now; integration later). Writes minimum-viable specs following the project's naming/location conventions and can run them with scoped coverage. Use for "write tests for this", "create unit tests", "add test coverage for my diff".
argument-hint: "[--lang <key>] [--type unit|integration] [--files <glob>] [--base <branch>] [--coverage <target>] [--proposal] [--clean <branch>] [--clean-all] [--help]"
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# create-tests

Test-generation skill. Reads source files and emits **minimum-viable** tests following each language's
conventions. Supports Vue (Vitest) and Spring Boot (JUnit 5), extensible to any language.

> **Scripts do the CLI work.** Target detection and test running live in `scripts/`. Call them as
> `bash "<skill-dir>/scripts/<name>.sh" …` rather than re-emitting commands.

## Invocation

```
/create-tests                              # unit tests for changed source files (vs base)
/create-tests --files src/utils/money.ts   # tests for specific files
/create-tests --lang springboot            # force language
/create-tests --type unit                  # test type (default; integration = later)
/create-tests --coverage 100               # target/focus for coverage
/create-tests --proposal                   # save proposed specs under .supensour/create-tests/ (default: write to disk)
/create-tests --clean                      # delete saved proposals for current branch
/create-tests --clean feature/RANCH-1      # delete saved proposals for a branch
/create-tests --clean-all                  # delete all saved proposals
/create-tests --help                       # print usage and exit
```

**Utility flags run a script and stop** — no tests generated:
- `--help` → `bash "<skill-dir>/scripts/help.sh"`, print output, stop.
- `--clean [branch]` → `bash "<skill-dir>/scripts/clean.sh" [branch]` (default: current branch), stop.
- `--clean-all` → `bash "<skill-dir>/scripts/clean.sh" --all`, stop.

`clean` removes `<repo>/.supensour/create-tests/<branch>/` (saved proposals); `--clean-all` removes the
whole `.supensour/create-tests/` tree.

## Input

| Flag | Default | Description |
|------|---------|-------------|
| `--lang <key>` | auto-detect | Force language ruleset: `vue`, `springboot`. Auto-detected from file extensions otherwise |
| `--type <unit\|integration>` | `unit` (or `project.test_type` config hint) | Test type. Only `unit` is supported now; `integration` → note "not yet supported" and stop |
| `--files <glob>` | changed files | One or more globs (repeatable). Default = source files changed vs `--base` |
| `--base <branch>` | auto-detect | Diff base for changed-file detection (`origin/HEAD` → `main`/`master`/`develop`) |
| `--coverage <target>` | — | Coverage focus, e.g. `100`, `branches` — guides which cases to emphasize |
| `--proposal` | off | Save proposed specs under `.supensour/create-tests/` for review instead of writing to convention paths. Off → write spec files directly |
| `--clean [branch]` | current branch | Delete saved proposals for a branch, then stop |
| `--clean-all` | — | Delete all saved proposals (`.supensour/create-tests/`), then stop |
| `--help` | — | Print usage (`scripts/help.sh`) and stop |

## Process

### Step 0 — Resolve scope

0. **Ensure config exists** — create the per-repo config from a template if absent (idempotent):
   ```bash
   bash "<skill-dir>/scripts/init-config.sh"   # creates <repo>/.supensour/config/config.yaml if missing
   ```
1. Resolve `--type`: explicit flag → `project.test_type` config hint → default `unit`:
   ```bash
   bash -c '. "<skill-dir>/scripts/lib/common.sh"; proj_get project test_type'
   ```
   If `integration` → print `Integration tests not yet supported — only --type unit.` and exit.
2. Resolve target source files with the script:
   ```bash
   bash "<skill-dir>/scripts/detect-targets.sh" [--files <glob>...] [--base <branch>] [--lang <key>]
   ```
   Prints one source path per line (existing tests/specs filtered out). Empty → `No source files to test.` and exit.
   The script reads per-repo hints from `<repo>/.supensour/config/config.yaml` to skip detection:
   `--lang` defaults to `project.language`, `--base` to `git.base_branch` (then `origin/HEAD`).
3. Resolve `--lang`: explicit flag → project `project.language` hint → auto-detect from the target
   extensions (the script already filters per `--lang`; for a mixed set, group targets by language).

### Step 1 — Load conventions

Load in one parallel batch:
- `rules/generic.md` (always)
- `rules/<lang>/index.md` (language entry)
- `rules/<lang>/types/<type>.md` (e.g. `rules/vue/types/unit.md`)
- Any relevant `rules/<lang>/cases/*.md` whose topic matches the target's behavior (e.g. async/promise
  rejection code → `rules/vue/cases/handling-rejected-promises.md`).

Before writing, **read one neighboring existing test** in the project to learn its concrete style. How
to apply it depends on the target:
- **Adding to an existing test file** → match that file's concrete style even where it diverges from this
  skill's rules — stay consistent with the surrounding code you're extending.
- **Creating a new test file** → this skill's rules and conventions take priority. Follow neighboring
  style only where it doesn't conflict with them; on any conflict, the skill rules win.

### Step 2 — Generate (executor pool per target)

Targets are independent — dispatch one subagent per source file (group tiny related files) through a
**bounded executor pool with a queue**, not fixed batches:

1. **Size the pool**: `min(10, floor(host_cores * 0.3))`, minimum 1.
   ```bash
   cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu); pool=$(( cores*30/100 )); pool=$(( pool<1 ? 1 : pool )); pool=$(( pool>10 ? 10 : pool ))
   ```
2. **Report before dispatch** — list every target file and the resolved pool size, e.g.:
   ```
   Targets (4): src/utils/money.ts, src/composables/useOrderList.js, src/components/Order.vue, src/utils/date.js
   Pool size: 3 (cores=8, cap=min(10, 30%))
   ```
3. **Fill the pool, then top it up on every completion** — queue all targets FIFO, dispatch `min(pool,
   queue.length)` subagents at once (one Agent call per target, backgrounded). The instant any subagent
   finishes, immediately dispatch the next queued target so the pool stays full — never wait for the rest
   of the current pool to finish, and never leave a slot idle while targets remain queued. Report each
   dispatch (`dispatching <file> (<k>/<total>)`) and each completion (`<file> done (<k>/<total>)`) as they
   happen. Drain until the queue is empty and every in-flight subagent has returned.

Each subagent receives: the source file, the loaded conventions, the `--coverage` target.

Per target, the subagent:
1. Reads the source; identifies public functions/methods, branches, edge + error paths.
2. Derives **minimum-viable** cases — enough to cover uncovered lines/branches/functions + critical
   edge/error cases. No redundant permutations.
3. Emits a complete, runnable spec following the language convention (imports real, no placeholder asserts).
4. Computes the spec's target path via the language lib mapping (see below).
5. Applies the **watermark** — placement depends on whether the target file is new or pre-existing.
   Get the text from `bash "<skill-dir>/scripts/watermark.sh"` (configurable). A file counts as
   **skill-created** if it already contains the watermark (search the file for `supensour:create-tests`).
   - **New test file/class** → watermark as the file/class header.
   - **Adding tests to an existing file NOT created by this skill** → watermark per **new test unit**
     (Java: above the new method; Vue: above each new `it()`/`test()`), not as a file header — never
     edit/rewrite the existing parts.
   - **Existing skill-created file** → header already present; just add tests, no per-unit marks.
   See `rules/<lang>/types/unit.md` for the exact per-language form.

### Step 3 — Place or propose

- **Default (no `--proposal`)**: write each spec to its convention path:
  ```bash
  # path is derived by the language lib; e.g. vue: test/unit/specs/<rel>.spec.ts,
  # springboot: src/test/java/<pkg>/<Class>Test.java
  ```
  Don't overwrite an existing spec without surfacing it — if the target spec already exists, show a diff
  / append cases rather than clobbering.
- **`--proposal`**: save specs to disk under `.supensour/create-tests/` instead of the convention path,
  for review before a real write:
  1. Resolve the proposal dir **once per run** (not per target):
     ```bash
     DIR="$(bash "<skill-dir>/scripts/proposal-dir.sh")"   # .../.supensour/create-tests/<branch>/<timestamp>
     ```
  2. For each target, write the **full** proposed spec content to `"$DIR/<spec-path>"`, where
     `<spec-path>` is the same convention-relative path from Step 2.4 (mirrors the real destination,
     just rooted under `$DIR`) — create parent dirs as needed. If the target spec already exists in the
     project, write the full resulting file (existing content + new cases), not just a fragment.
  3. Write `"$DIR/manifest.md"` — a table of `source file | proposed path | new file / updates existing`.
  4. Print a summary only (not the full spec bodies): target count, `$DIR`, and the manifest path, e.g.
     `💾 Proposed 4 spec(s) saved to .supensour/create-tests/<branch>/<timestamp>/ (see manifest.md)`.
  5. Add `.supensour/create-tests/` to `.gitignore` if not already present.

### Step 4 — Verify (optional)

Run the generated test(s) and report pass/coverage:
```bash
bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec-or-class> [--coverage <source-file>]
# vue        → npm run test:unit -- run <spec> --coverage --coverage.include="<src>"
# springboot → mvn test -Dtest=<Class>
```
Run **once** to verify the final result / check coverage — not after every edit. Report failures with
exact output; fix and re-run only as needed.

As the final user-facing line of the run, print the console watermark:
`bash "<skill-dir>/scripts/watermark.sh" --banner`.

## Rule loading

1. Always load `rules/generic.md`.
2. Resolve language from extensions (or `--lang`):
   - `.vue`, `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` → `vue`
   - `.java`, `.kt` → `springboot`
3. Load `rules/<lang>/index.md` + `rules/<lang>/types/<type>.md` + matching `rules/<lang>/cases/*`.

## Extending

- **New language**: create `rules/<lang>/index.md` + `rules/<lang>/types/unit.md` (+ `cases/` as needed),
  and `scripts/lib/lang-<lang>.sh` exposing `<lang>_spec_path` and `<lang>_run_tests` (same signatures
  as `lang-vue.sh` / `lang-springboot.sh`). Register the extensions in `detect_lang` in
  `scripts/lib/common.sh`. No other file changes — `lang_dispatch` routes by language.
- **New test type**: add `rules/<lang>/types/<type>.md` and accept the `--type` value (e.g.
  `integration` → `types/integration.md` with slice/`@SpringBootTest` or component-mount conventions).

## Conventions summary (see rules/ for detail)

| Language | Framework | Spec name | Location | Run |
|----------|-----------|-----------|----------|-----|
| vue | Vitest + @vue/test-utils | `<name>.spec.ts` | mirror source under test root (e.g. `test/unit/specs/`) | `npm run test:unit -- run <spec> --coverage --coverage.include=<src>` |
| springboot | JUnit 5 + Mockito | `<Class>Test.java` | `src/test/java/` mirroring package | `mvn test -Dtest=<Class>` |

## Edge cases

- **No targets**: `No source files to test.` and exit.
- **Mixed languages in target set**: group by language; run Step 1–2 per language group.
- **`--type integration`**: not yet supported — note and exit (structure is ready under `types/`).
- **Spec already exists**: surface it; propose added/updated cases instead of overwriting silently.
- **No build system at root** (`run-tests.sh`): script warns (`No package.json`/`No pom.xml`); generation
  still succeeds, verification is skipped.
- **`--proposal` runs pile up**: each run creates a new `.supensour/create-tests/<branch>/<timestamp>/`
  dir. Use `--clean [branch]` / `--clean-all` to prune.
