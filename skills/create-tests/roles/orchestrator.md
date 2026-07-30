# Role — orchestrator

Entered by `/create-tests` **without** `--executor`. You resolve scope, gate on existing coverage, and
dispatch one analyst per remaining target. You do **not** read source files, rules, plans or specs — your
context must stay flat regardless of target count. Everything else is a script call.

Read `SKILL.md` (flags, safety, roles) + this file. Nothing else.

## Step 1 — Resolve scope

1. **Ensure config exists** (idempotent):
   ```bash
   bash "<skill-dir>/scripts/init-config.sh"   # creates <repo>/.supensour/config/config.yaml if missing
   ```
2. Resolve `--type`: explicit flag → `project.test_type` hint → default `unit`:
   ```bash
   bash -c '. "<skill-dir>/scripts/lib/common.sh"; proj_get project test_type'
   ```
   `integration` → print `Integration tests not yet supported — only --type unit.` and exit.
3. Resolve targets:
   ```bash
   bash "<skill-dir>/scripts/detect-targets.sh" [--files <glob>...] [--base <branch>] [--lang <key>]
   ```
   One source path per line (existing tests/specs filtered out). Empty → `No source files to test.`, exit.
   Per-repo hints fill in `--lang` (`project.language`) and `--base` (`git.base_branch` → `origin/HEAD`).
   The script also warns on stderr about candidates dropped for living under a test path
   (`⚠ skipped N candidate(s) matching test paths: …`) — pass that line through to the user; those may be
   real sources the user can re-add with `--files`.
4. Resolve `--lang` per target group: explicit flag → `project.language` → extension. Mixed set → group by
   language and run the gate once per group. The dispatch pool in Step 3 stays **global** across groups.

## Step 2 — Coverage gate

Never spawn an analyst for a file that is already covered.

```bash
bash "<skill-dir>/scripts/coverage-scan.sh" [--threshold <n>] <lang> <target>...
# keyed TSV per target, metric set differs by language:
#   vue:        <source>  statements=<n>  branches=<n>  functions=<n>  lines=<n>  <SKIP|GENERATE>
#   springboot: <source>  instructions=<n> branches=<n> methods=<n>    lines=<n>  <SKIP|GENERATE>
```

Pass `--threshold <n>` = `--coverage <n>` when given, else omit (script defaults to 100). Read metrics by
**key**, never by column position — the sets differ per language.

The script maps each target to its conventional spec, runs **only** the specs that already exist with
coverage scoped to those sources (vue: Vitest with one `--coverage.include` per source + `json-summary`;
springboot: `mvn`/`gradlew` test for those classes + `jacocoTestReport` → `jacoco.csv`), and scores every
metric.

- `SKIP` = every metric at/above the threshold → drop the target.
- `GENERATE` = below threshold, no spec yet, or unreadable data (fail-safe — never skip on missing data).
- Report the gate, then continue with the `GENERATE` set only:
  ```
  Coverage gate (threshold 100): 6 target(s) → 2 skipped, 4 to generate
    skip     src/utils/date.js        statements=100 branches=100 functions=100 lines=100
    generate src/utils/money.ts       statements=82 branches=64 functions=100 lines=85
    generate src/components/Order.vue  no data (no spec yet)
  ```
- All `SKIP` → `All targets already fully covered — nothing to generate.`, print the console watermark, exit.

**`--explain`** → after the gate, print the resolved run config and **stop**: external deps
(`bash "<skill-dir>/scripts/deps.sh"` — TSV `<cmd> <ok|MISSING|absent (optional)> <path|hint>`), language
group(s), `--type`, threshold, every target with its gate verdict, the spec path each maps to
(`spec-path.sh`), the resolved test command (`test-command.sh <lang> coverage --spec … --source …`), pool
size, analyst + writer models, split mode. No dispatch, no plan files, no writes.

`node` absent is worth surfacing loudly: the Vue coverage gate can't read numbers without it, so every
target falls through to `GENERATE` (fail-safe, not a silent skip).

## Step 3 — Dispatch analysts through a bounded pool

1. **Pool size**: `--pool <n>` if given (clamp `>= 1`, no core cap), else
   `min(10, floor(cores * 0.3))`, min 1. Cap at the number of queued targets. One pool for the whole run —
   mixed-language groups share it, they don't each get their own.
   ```bash
   cores=$(bash -c '. "<skill-dir>/scripts/lib/common.sh"; cpu_cores')   # nproc · sysctl · NUMBER_OF_PROCESSORS
   pool=$(( cores*30/100 )); pool=$(( pool<1 ? 1 : pool )); pool=$(( pool>10 ? 10 : pool ))
   ```
2. **Report before dispatch**:
   ```
   Targets (4): src/utils/money.ts, src/composables/useOrderList.js, src/components/Order.vue, src/utils/date.js
   Pool size: 3 (cores=8, cap=min(10, 30%))       # or: Pool size: 4 (--pool 4)
   Models: analyst=sonnet, writer=sonnet
   ```
3. **Fill, then top up on every completion** — queue targets FIFO, dispatch `min(pool, queue.length)`
   analysts at once (one Agent call per target, backgrounded, `subagent_type: supensour-test-analyst`,
   `model: <--analyst-model>`). The instant one finishes, dispatch the next queued target — never wait for
   the rest of the pool, never leave a slot idle while targets remain. Log `dispatching <file> (k/total)`
   and `<file> done (k/total)`. Drain until the queue is empty and every in-flight agent returned.
4. **Dispatch prompt** — do not paraphrase conventions; make the analyst load the skill itself:
   ```
   Repo: <repo-root>
   Invoke the skill `supensour:create-tests` with arguments:
     --executor <source-file> [--lang <lang>] [--type <type>] [--coverage <n>]
     [--writer-model <key>] [--no-split]
   You are the ANALYST for exactly this one file. Follow roles/analyst.md in that skill.
   Coverage now (from the gate, keyed): <metric>=<n> … — threshold <n> on every metric.
   Report back exactly one line:
     <spec-path> | new|append | <n> cases | PASS|FAIL | <metric>=<n> …
     …and on FAIL only, append: | <reason> | plan=<plan-path> | writers=<n>
   ```
5. **Protect after each completion**: `bash "<skill-dir>/scripts/protect.sh" <reported-spec>`.
   `--pool 1` with a single target → still dispatch the analyst (keeps rules out of your context).

## Step 4 — Close out

1. Integrity check over **all** reported specs:
   ```bash
   bash "<skill-dir>/scripts/protect.sh" <spec>...
   ```
   Any `✖ MISSING` → report the incident (which files) and re-dispatch those targets (once).
   Any `⚠ UNPROTECTED` → list those specs in the summary: they exist but stay untracked (gitignored test
   dir), so a `git clean` elsewhere can still delete them.
2. Summary table: source → spec → cases → PASS/FAIL → coverage, plus counts of skipped-by-gate and failed
   targets. For failed targets include the plan path + writer count the analyst reported, so the run can
   be debugged without re-reading anything. Do not print spec bodies.
3. Final user-facing line: `bash "<skill-dir>/scripts/watermark.sh" --banner`.

## Don'ts

- Don't read `rules/*`, source files, plan files or spec bodies.
- Don't run the full test suite; the gate and the analysts run scoped commands only.
- Don't fix a failing spec yourself — that's the analyst's job; report `FAIL` with the reason it gave.
- Never run a destructive git command (see SKILL.md → Safety).
