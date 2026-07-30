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
bash "<skill-dir>/scripts/test-command.sh" <lang> coverage --spec <spec-path> --source <source-file>
wc -l <source-file>                                            # feeds the split decision in Step 4
```

`test-command.sh` output goes into the plan's `Run:` line verbatim — it already reflects
`project.test_command_coverage`, the project's vitest script, or `mvn`/`gradlew`. Never hand-write a
runner command.

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
   yourself, scoped to this one file, before planning:
   ```bash
   bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec-path> --coverage <source-file>
   ```
   Spec doesn't exist → treat the target as 0% covered and skip the run.
3. **Minimum viable**: enough cases to hit the threshold plus genuinely risky edge/error paths. No
   redundant permutations, no tests of the framework.
4. Map each case to what it covers (line/branch/function) — that mapping goes in the plan and is how the
   writer knows the case is load-bearing.

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
Run: <exact output of test-command.sh — must be the coverage-scoped command>
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
- **`Run:` must be the coverage-scoped command** — the writer has to report per-metric coverage, and it
  can't if the command doesn't collect any.
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
time, **max 3 dispatches** for this target:

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
  <exact run command from the plan>          # max 2 runs total, then stop
Report exactly one line:
  WRITER <spec-path> | attempt <n> | PASS|FAIL | <metric>=<n> … | <failing case names or -> | <≤20 lines of exact runner output or ->
```

On `FAIL`:

1. Read the writer's output lines and the spec file (only the failing region if it's large).
2. Decide: plan defect (wrong mock shape, wrong assertion, missing setup) → **revise the plan file**
   (append `## Revision <n> — <what changed and why>`, edit the affected cases) and re-dispatch the writer.
3. **Max 2 revisions.** Still failing → repair the spec yourself, once, directly.
4. Still failing → report `FAIL` with the exact reason and the failing case names. Never loop further,
   never delete the spec, never revert anything.

## Step 5 — Place, verify, report

- The spec lives at its convention path (`spec-path.sh`). Don't clobber an existing spec — append cases to
  it and never edit or reformat the cases already there.
- **Do not re-run tests to feel sure.** A writer's `PASS` line with per-metric numbers *is* the
  verification. Run this exactly once, and only if one of these holds — you wrote the spec yourself, the
  writer's line lacked coverage numbers, or you repaired the spec after the writer's last attempt:
  ```bash
  bash "<skill-dir>/scripts/run-tests.sh" <lang> <spec> --coverage <source-file>
  ```
- Ensure `bash "<skill-dir>/scripts/protect.sh" <spec-path>` has run. If it printed
  `⚠ UNPROTECTED`, say so in your report reason field.
- Report exactly one line upward, nothing else:
  ```
  <spec-path> | new|append | <n> cases | PASS | <metric>=<n> …
  <spec-path> | new|append | <n> cases | FAIL | <metric>=<n> … | <reason> | plan=<plan-path> | writers=<n>
  ```
  Metric keys are whatever the runner reports for the language (vue:
  `statements/branches/functions/lines`; springboot: `instructions/branches/methods/lines`). `writers=` is
  the number of writer dispatches you spent.

## Don'ts

- No spec bodies, no plan contents, no rule quotes in your report.
- Don't dispatch more than one writer at a time, don't dispatch another analyst, don't re-run target
  detection or the coverage gate.
- Don't touch any file except your spec, your plan, and `git add -N` on your spec.
- Never run a destructive git command (see SKILL.md → Safety).
