# Role — analyst (executor)

Entered by the skill with `--executor <source-file>`: you own **exactly one target**. You do the thinking —
read the source, decide the cases, write a plan precise enough that a cheaper model can transcribe it —
then dispatch a writer, verify, and report one line upward.

Read `SKILL.md` + this file + the rules for your target. Never read `roles/orchestrator.md` or
`roles/writer.md`.

## Step 0 — Guard

`--type integration` → print `Integration tests not yet supported — only --type unit.` and stop. (The
orchestrator checks this too, but a user can invoke `--executor` directly.)

## Step 1 — Load conventions (once, for this target only)

One parallel batch:

- `rules/generic.md` (always)
- `rules/<lang>/index.md`
- `rules/<lang>/types/<type>.md`
- only the `rules/<lang>/cases/*.md` whose topic the target actually exhibits (e.g. rejected promises).

Then, in one batch:

```bash
bash "<skill-dir>/scripts/spec-path.sh" <lang> <source-file>   # → <src>\t<spec-path>\t<new|append>
bash "<skill-dir>/scripts/watermark.sh"                        # → the verbatim watermark text
bash "<skill-dir>/scripts/watermark.sh" --author               # → author value (Java @author tag)
bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec-path> --reset-only [--budget <n>]
wc -l <source-file>                                            # feeds the split decision in Step 4
```

`--reset-only` opens this target's run ledger without spending a run. **Every** run of this spec — yours
and every writer's — goes through `run-tests.sh`, which counts them against the budget (default 4, or
`--runs <n>` from the dispatch prompt). It resolves the same command `test-command.sh` prints, so you never
hand-write a runner command and never bypass the counter.

## Run budget — the one number that bounds this target

| Who | Allowance |
|---|---|
| **Total, all roles** | **4 runs** (`--runs <n>` / `CT_RUN_BUDGET` to change) |
| Writer, per dispatch | 2 runs |
| Writer dispatches | max 2 |
| Plan revisions | max 1 |
| Your own verification / repair run | only if the budget still has room |

`run-tests.sh` exits **5** when the budget is gone and runs nothing. That is not a retry signal: report
`PASS`, `PARTIAL` or `FAIL` from what you already know (Step 5).

Read the target source. Then:

- **`append`** (the spec already exists) → read that spec **in full**: you need its imports, helpers,
  setup and existing case names to avoid duplicates and collisions.
- **`new`** → read **one** neighboring existing spec (nearest sibling under the test root) to learn
  concrete project style — one file, not three.

Style precedence:

- **Appending to an existing spec** → match that file's style even where it diverges from these rules.
- **New spec file** → these rules win; follow neighbor style only where it doesn't conflict.

## Step 2 — Derive the cases

1. Identify public functions/methods, branches (`if/else`, ternary, `switch`, `try/catch`, guards, early
   returns), edge inputs, error paths.
2. Use the keyed coverage numbers from the dispatch prompt: cover what's **missing**, don't re-cover
   what's already green. No spec yet → cover everything reachable.
   **No numbers in your prompt** (a user invoked `--executor` directly) and the spec exists → get them
   yourself, scoped to this one file, before planning — this costs one run from the budget:
   ```bash
   bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec-path> --coverage <source-file>
   ```
   Spec doesn't exist → treat the target as 0% covered and skip the run.
3. **Minimum viable**: enough cases to hit the threshold plus genuinely risky edge/error paths. No
   redundant permutations, no tests of the framework.
4. Map each case to what it covers (line/branch/function) — that mapping goes in the plan and is how the
   writer knows the case is load-bearing.
5. **Note what no test can reach**, now, before writing the plan: a branch guarded by a condition that
   can't occur through the public API, a defensive `default:` over an exhaustive union, a
   platform/env-specific path, generated or framework-owned code. Record `file:line` + one clause of why.
   You are not required to reach the threshold on code that isn't reachable — that's a `PARTIAL` in Step 5,
   decided here by reading, **not** by writing a probe case to see whether it moves the number.

## Step 3 — Write the plan file

```bash
PLAN="$(bash "<skill-dir>/scripts/plan-path.sh" <spec-path>)"
```

Write the plan to `$PLAN`. It is the writer's **only** instruction source, so it must be complete and
near-transcription — but still compact (aim ≤120 lines; the point is precision, not prose):

```
# Plan — <source-file>
Destination: <spec-path>
Mode: new-file | append-to-existing
Watermark: |
  <the exact comment line(s) to paste, already in the target language's comment syntax>
Watermark placement: file-header | per-case | none (file already skill-created)
Run: bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec-path> --coverage <source-file> [--budget <n>]
Unreachable: <file>:<line> — <why no test can reach it>   # omit the line when there is none
Imports:
  <exact import lines, in the project's order>
Mocks:
  - vi.mock('vue-router') → useRouter: () => ({ push: pushMock })
  - <shape of every mock/stub, declared before use>
Setup:
  - beforeEach: <exact calls>
  - factory: <name>(<args>) → <exact mount/construct call>
Structure:
  describe('<subject>')
    describe('<group>')                   # e.g. prop#code, function#handleGoBack, method#save
      it('<expected outcome> when <condition>')      → covers <line/branch/function>
        arrange: <exact fixture values>
        act: <exact call/interaction>
        assert: <exact expectation(s)>
Style notes (from <neighbor spec>): <≤4 bullets>
Do not: add/remove/rename cases, restructure, edit any other file
```

Rules for the plan:

- Exact identifiers, exact fixture values, exact assertion targets. If you'd have to guess, resolve it now
  by reading the source — don't push ambiguity to the writer.
- **`Run:` must be the `run-tests.sh` form with `--coverage`** — coverage-scoped because the writer has to
  report per-metric numbers, and via the script because that is what counts runs against the budget. Carry
  `--budget <n>` through when the dispatch prompt gave you `--runs <n>`, so the writer shares your ledger.
- **`Unreachable:`** — carry Step 2.5's findings so the writer doesn't invent a case trying to cover them,
  and so a later run of this skill doesn't re-litigate the same lines.
- **Watermark**: paste ready-to-use comment text, since the writer loads no rules. Per language:
  - JS/TS/Vue → `// <watermark text>` (file header, or above each added `it()`).
  - Java/Kotlin, **new class** → Javadoc block above the class:
    `/**`, ` * <watermark text>`, ` *`, ` * @author <watermark.sh --author>`, ` */`.
  - Java/Kotlin, **method added to an existing class** → a single `// <watermark text>` above the method.
- Append mode: list only the **new** cases and where they go (`after it('…')`), plus "never edit existing
  cases". Per-case watermark placement applies unless the file already contains `supensour:create-tests`
  (then the header exists — set placement `none`).
- **Do not paste the plan into the dispatch prompt or your report.** The file is the handoff.

## Step 4 — Get the spec written

**Write it yourself** (no writer dispatch) when any holds — measure, don't estimate:

- `--no-split` was passed;
- `wc -l <source-file>` < 80;
- the plan has ≤3 `it(...)` cases.

Then do the writer's job yourself: write the spec, `protect.sh`, run the plan's `Run:` command once.

Otherwise dispatch a writer (`subagent_type: supensour-test-writer`, `model: <--writer-model>`), one at a
time, **max 2 dispatches** for this target (2 runs each = the whole 4-run budget in the worst case):

```
Repo: <repo-root>
Skill dir: <skill-dir>
You are the WRITER. Read, in order:
  1. <skill-dir>/roles/writer.md
  2. <plan-path>
  3. <source-file>
Read nothing else — no rules files, no other specs, no SKILL.md.
Implement the plan exactly: same cases, same titles, same order. Then:
  bash "<skill-dir>/scripts/protect.sh" <spec-path>
  <exact Run: command from the plan>        # max 2 runs; exit 5 = budget gone, stop
Report exactly one line:
  WRITER <spec-path> | attempt <n> | PASS|FAIL|BUDGET | <metric>=<n> … | <failing case names or -> | <≤20 lines of exact runner output or ->
```

Then branch on what came back:

- **`PASS`, every metric at threshold** → Step 5, report `PASS`. Don't re-run to confirm.
- **`PASS`, a metric under threshold** — decide *by reading*, not by running:
  - the gap is coverable and you know which case closes it → **one** plan revision, re-dispatch;
  - the gap is the `Unreachable:` code from Step 2.5 → Step 5, report **`PARTIAL`**. Extra cases that
    can't execute the line are noise, and a probe-then-revert cycle burns the budget for nothing.
- **`FAIL`** →
  1. Read the writer's output lines and the spec (only the failing region if it's large).
  2. Plan defect (wrong mock shape, wrong assertion, missing setup) → **revise the plan file** (append
     `## Revision <n> — <what changed and why>`, edit the affected cases) and re-dispatch. **Max 1
     revision.**
  3. Still failing and the budget has room → repair the spec yourself, once, directly.
  4. Otherwise report `FAIL` with the exact reason and failing case names. Never loop further, never
     delete the spec, never revert anything.
- **`BUDGET`** (writer hit exit 5) → stop dispatching. Report from the last known numbers: `PARTIAL` if the
  last run was green but short of threshold, `FAIL` if tests were failing.

## Step 5 — Place, verify, report

- The spec lives at its convention path (`spec-path.sh`). Don't clobber an existing spec — append cases to
  it and never edit or reformat the cases already there.
- **Do not re-run tests to feel sure.** A writer's `PASS` line with per-metric numbers *is* the
  verification. Run this at most once, only if one of these holds — you wrote the spec yourself, the
  writer's line lacked coverage numbers, or you repaired the spec after the writer's last attempt — **and
  only if the budget has room** (exit 5 = report what you have):
  ```bash
  bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec> --coverage <source-file>
  ```
- Ensure `bash "<skill-dir>/scripts/protect.sh" <spec-path>` has run. If it printed
  `⚠ UNPROTECTED`, say so in your report reason field.

### The three outcomes

| Outcome | Means | Requires |
|---|---|---|
| `PASS` | Tests green, every metric at threshold | — |
| `PARTIAL` | Tests **green**, a metric short of threshold because the remaining code is not reachable by a test | `uncovered=<file>:<line>` + a one-clause reason |
| `FAIL` | A test fails or errors, or the spec could not be produced | reason + failing case names |

`PARTIAL` is a delivered spec, not a failure: the orchestrator counts it separately and never re-dispatches
it. Never dress a failing test up as `PARTIAL`, and never report `FAIL` for coverage you established is
unreachable — that misdirects the next run into chasing a number no test can move.

- Report exactly one line upward, nothing else:
  ```
  <spec-path> | new|append | <n> cases | PASS    | <metric>=<n> …
  <spec-path> | new|append | <n> cases | PARTIAL | <metric>=<n> … | uncovered=<file>:<line> <why> | writers=<n>
  <spec-path> | new|append | <n> cases | FAIL    | <metric>=<n> … | <reason> | plan=<plan-path> | writers=<n>
  ```
  Metric keys are whatever the runner reports for the language (vue:
  `statements/branches/functions/lines`; springboot: `instructions/branches/methods/lines`). `writers=` is
  the number of writer dispatches you spent.

## Don'ts

- No spec bodies, no plan contents, no rule quotes in your report.
- Don't dispatch more than one writer at a time, don't dispatch another analyst, don't re-run target
  detection or the coverage gate.
- **Don't run the spec outside `run-tests.sh`** (no raw `npx vitest`, `mvn`, `gradlew`) — that bypasses the
  ledger, which is the whole reason the ledger exists.
- Don't write a case whose only purpose is to see whether a number moves, and don't revert one afterwards.
  Read the source and decide; a probe cycle costs two runs and proves nothing the source didn't say.
- Don't touch any file except your spec, your plan, and `git add -N` on your spec.
- Never run a destructive git command (see SKILL.md → Safety).
