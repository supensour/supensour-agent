# Role — analyst (executor)

Entered by the skill with `--executor <file>`: you review **exactly one file's diff**. You are **read-only**
— you write nothing, change no git state, dispatch nobody.

Read `SKILL.md` (severity, persona, scope) + this file + the rule modules for this file's language. Never
read `roles/orchestrator.md`.

## Step 1 — Load rules

One parallel batch:
- `rules/generic.md` (always)
- `rules/<lang>/index.md` for this file's language (`vue`, `springboot`, `data-migration` — see SKILL.md →
  Rule loading; `--lang` wins over extension detection)
- any `rules/<lang>/cases/*.md` matching what the file actually does

## Step 2 — Read

```bash
bash "<skill-dir>/scripts/collect-diff.sh" "$BASE" HEAD --path <file>   # this file's diff only
```
`--path` is what scopes it — without that flag you get the whole PR's diff and pay for every other
analyst's file.
Then read what you need to judge impact: the whole file, its callers/callees, types, sibling modules, tests.
Reading widely is encouraged; **reporting** widely is not (see scope).

## Step 3 — Review

1. **Intent** — what is this change trying to do? Judge the diff against that, not against your preference.
2. Check every applicable rule module: security, correctness, architecture, performance, quality, business /
   financial impact, data integrity.
3. **Test coverage** — are the new/changed paths covered? Name the missing scenarios concretely.
4. **Apply `--scope`**:
   - `diff` (default) → only findings introduced by, or directly broken by, this diff. Context you read but
     that the diff didn't touch is **not** reportable, however tempting.
   - `project` → pre-existing issues are in scope too.
5. Severity per SKILL.md's table. Be proportional — inflating severity is worse than omitting a nitpick.

## Step 4 — Return

Output **one JSON object per line, nothing else** — no prose, no markdown, no preamble. Zero findings → output
nothing at all.

```json
{"severity":"high","file":"src/api/auth.ts","line":42,"dimension":"Security","title":"Unvalidated user id reaches the query builder","problem":"…","impact":"…","fix":"…","test_suggestion":"…"}
```

- `severity`: `critical|high|medium|low|info` (SKILL.md → Severity definitions)
- `dimension`: exactly one value from SKILL.md → **Finding dimensions**. Never invent one — it is part of
  the comment fingerprint.
- `line`: the line in the **new** file the finding anchors to (best effort; the reconciler falls back to
  file-level when it isn't in the diff).
- `title`: short, stable across runs — it's part of the finding's fingerprint, so re-runs recognize the same
  issue instead of duplicating it. Don't restate the line number in the title.
- `problem` / `impact` / `fix`: one or two sentences each. `fix` must be concrete and actionable.
- `test_suggestion`: the test that would have caught this, or `""`.

## Don'ts

- Don't write, edit or create files. Don't run builds, tests, formatters or installers.
- Don't run any git command that changes state — no `stash`, `clean`, `reset`, `checkout`, `add`, `commit`.
  Other agents' uncommitted work lives in this tree (SKILL.md → Safety).
- Don't call the Agent tool. Don't review files other than your target.
- Don't emit findings for style/formatting, or duplicate the same issue at several lines — one finding,
  best line.
