# Architecture

Implementation reference for `supensour-agent`: repo layout, configuration model,
plugin manifests, and how to extend skills. For install/usage see the [README](../README.md).

## Layout

```
.claude-plugin/        plugin.json (namespace "supensour") + marketplace.json
.cursor-plugin/        plugin.json (Cursor)
plugin.json            root manifest (Antigravity)
lib/core.sh            helpers shared by every skill (config, watermark, gitignore, cmd allowlist,
                       tool guards, glob dialect)
scripts/validate.sh    static repo self-check — run before committing (see Validation below)
scripts/smoke.sh       executes the scripts on this machine (OS differences validate.sh can't see)
.github/workflows/     CI: validate + smoke on linux/macos/windows, plus shellcheck
skills/<skill>/        SKILL.md (router) + roles/ + rules/<lang>/ + templates/ + scripts/
agents/                subagent definitions (Claude Code only) — no `model:` pinned
schemas/               JSON Schema (draft-07) for the config files
examples/              project-config.template.yaml (copied into repos by init-config.sh)
supensour-config.yaml  repo-baked settings (watermark)
```

## Plugin manifests

One repo, four consumers. Each reads its own manifest; all point at the shared `skills/` dir.

| Platform | Manifest | Notes |
|---|---|---|
| Claude Code | `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` | marketplace name `supensour`, plugin `supensour`, source `./` |
| GitHub Copilot | *(reuses `.claude-plugin/marketplace.json`)* | Copilot CLI reads this file as a fallback marketplace location |
| Antigravity | root `plugin.json` | schema `additionalProperties:false` → `name`+`description` only; `skills/` auto-discovered |
| Cursor | `.cursor-plugin/plugin.json` | `skills: "./skills/"`; enables `/add-plugin <git-url>` |

## Configuration

Three config files, each with a JSON Schema in [schemas/](../schemas/). The top-of-file
`# yaml-language-server: $schema=…` modeline gives editors (VS Code "YAML" extension) type
hints + validation — point it at the raw GitHub URL or a local absolute path.

### Global platform catalog — `~/.supensour/config/supensour.yaml`

Lists the git platforms skills can target.

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/supensour/supensour-agent/master/schemas/global-config.schema.json
platform:
  default: gitlab-ce
  platforms:
    gitlab-ce:
      type: gitlab
      host: https://git.example.com
      token_env: GITLAB_TOKEN
      token_env_alternatives:
        - MY_GITLAB_TOKEN
    github:
      type: github
      host: https://github.com
      token_env: GITHUB_TOKEN
      cli: gh
```

### Per-repo hints (optional) — `<repo>/.supensour/config/config.yaml`

Lets skills skip detection. `init-config.sh` in either skill copies
[examples/project-config.template.yaml](../examples/project-config.template.yaml) here on first run (all
values commented out); both skills share that one template, so neither drifts:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/supensour/supensour-agent/master/schemas/project-config.schema.json
git:
  platform: gitlab-ce                  # key into the global catalog → skip platform auto-detect
  token_env: MY_GITLAB_TOKEN           # override the platform's token_env for this repo
  base_branch:                         # default diff base → skip base detection
project:
  language: vue                        # default --lang for review-code / create-tests
  test_type: unit                      # default --type for create-tests
  test_command: "npm run test:unit -- run {spec} --coverage=false"          # create-tests
  test_command_coverage: "npm run test:unit -- run {spec} --coverage {coverage_args}"
```

`test_command*` let create-tests skip build-tool detection. Placeholders: `{spec}`, `{source}`,
`{coverage_args}` (vue) and `{classes}` (springboot). Omitted → detection: the `package.json` script that
runs vitest → `npx vitest run`; `pom.xml` → `mvn`; `build.gradle[.kts]` → `./gradlew`.

Precedence: CLI flag > per-repo config > global catalog `default` > auto-detect.

### Repo-baked settings — `supensour-config.yaml` (repo root)

Plugin-baked settings (not per-user / per-target-repo). Currently the attribution **watermark**
shown on skill output (PR/MR comments, generated tests, local report, console):

```yaml
watermark_template: "Generated with skill {skillName} · suprayan@supensour · github.com/supensour/supensour-agent"
watermark_url: "https://github.com/supensour/supensour-agent"   # {skillName} link target in markdown
skills:           # optional per-skill overrides (future config lives here too)
  review-code:
    # watermark_template: "Reviewed by {skillName} · suprayan@supensour"
    # watermark_url: "https://github.com/supensour/supensour-agent/tree/master/skills/review-code"
  create-tests:
```

Resolution (each key independently): `skills.<skill>.<key>` > top-level `<key>` > built-in default.
`{skillName}` → e.g. `supensour:review-code`. In markdown output (the `.md` report + PR/MR comments),
`{skillName}` renders as a link to `watermark_url`; the console banner stays plain text.

Skills resolve this file via `$SKILL_DIR/../../supensour-config.yaml`. Plugin installs preserve the
dir structure, so it still resolves from the installed location.

## Shared library — `lib/core.sh`

One copy of everything both skills need, sourced by each skill's `scripts/lib/common.sh`:
logging, YAML scalar readers for all three config files (`cfg_*`, `proj_*`), `ensure_project_config`,
`ensure_gitignore`, watermark/author resolution (`resolve_attribution`), the command allowlist
(`assert_allowed_cmd` / `run_checked`), external-tool guards (`require_cmd` / `deps_report`) and the shared
glob dialect (`normalize_globs` / `glob_pathspec` / `expand_globs`). A skill's `common.sh` only sets its
identity (`SKILL_KEY`, `SKILL_NAME`, `*_DEFAULT`) and adds skill-specific dispatch. **Edit shared behavior
there, not in a skill.**

External tools: `require_cmd` dies with an install hint before any work starts (review-code's
`init_platform` guards `jq` + `curl`, since every platform lib needs both); `scripts/deps.sh` in each skill
reports the same set as TSV for `--explain`, exiting 3 when a required tool is missing. Nothing may fail with
a bare `command not found` after a worktree or a spec already exists.

Glob dialect — one implementation, both skills' `--files` and `collect-diff.sh --path`: `*` (does not cross
`/`), `**`, `?`, `[abc]`, `{a,b}`, and a bare directory meaning its subtree. Git's default pathspec lets `*`
cross `/` and has no braces, so patterns go through `:(glob)` pathspecs; matching unions tracked files,
untracked files on disk and literal paths (a brand-new source file is the common `--files` case).

Command allowlist: `project.test_command*` comes from the *target* repo's config, so it's untrusted input.
Only known build entrypoints run (`npm`, `yarn`, `pnpm`, `bun`, `npx`, `node`, `vitest`, `jest`, `mvn`,
`gradle`, `gradlew`, `make`); override with `SUPENSOUR_ALLOWED_CMDS` when you trust the repo.

## Roles and subagents

Both skills split their process by role so each model pays only for the context it needs. `SKILL.md` is a
thin router; the process lives in `skills/<skill>/roles/`.

**create-tests** — orchestrator → analyst (one per target, via `--executor <file>`) → writer (one per
attempt, transcribes the analyst's plan):

| Role | File | Reads | Model |
|---|---|---|---|
| orchestrator | `roles/orchestrator.md` | scripts only — no rules, source, plans or spec bodies | the user's session model |
| analyst | `roles/analyst.md` | `rules/*`, the target source, one neighbor spec (or the target spec when appending) | `--analyst-model` (default `sonnet`) |
| writer | `roles/writer.md` | the plan file + the target source (zero rules files) | `--writer-model` (default `sonnet`) |

Plans are files under `.supensour/create-tests/<branch>/.plans/`, so the orchestrator's context never grows
with target count; inter-role reports are single fixed-format lines.

**review-code** — orchestrator → analyst (one per changed file, via `--executor <file>`):

| Role | File | Reads | Model |
|---|---|---|---|
| orchestrator | `roles/orchestrator.md` | scripts + rules for the cross-file pass; never a file's review body | the user's session model |
| analyst | `roles/analyst.md` | `rules/<lang>/`, the file's diff, surrounding context. **Read-only** | `--analyst-model` (default `sonnet`) |

Analysts return one JSON finding per line, so the orchestrator's context grows with findings, not with file
contents.

Agent definitions live in `agents/` (`supensour-test-analyst`, `supensour-test-writer`,
`supensour-review-analyst` — name them `supensour-<skill-domain>-<role>`), declared via
`"agents": "./agents/"` in `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json` (the Antigravity
root manifest is `additionalProperties: false` — name + description only, so it can't declare them). They
deliberately **omit** `model:` — the dispatcher passes the model, keeping the skill host-agnostic. A host
that doesn't resolve the agent type falls back to `general-purpose` with the same prompt and `model`.

Working-tree safety: every generated spec is `git add -N`'d the moment it's written
(`scripts/protect.sh`), and destructive git commands are banned for all roles — a stray `git clean -fd`
would otherwise delete every peer agent's untracked spec.

## Portability contract

Supported: **Linux, macOS, Windows via Git Bash or WSL**. One implementation, no per-OS branches beyond
`os_kind()`. Rules, all enforced by `scripts/validate.sh` check 14 and by CI:

| Rule | Why |
|---|---|
| **bash ≥ 4** (`require_bash` in `lib/core.sh`, runs at source time) | The reconciler needs associative arrays; macOS ships 3.2, where `${map[$key]}` silently degrades to arithmetic indexing — wrong dedup, no crash. Fail loudly instead |
| **No GNU-only flags** — no `sed -i`, `readlink -f`, `stat -c`, `find -printf`, `grep -P`, `sort -V`, `xargs -r`, `date -d` | macOS/BSD userland either rejects them or means something else |
| **No symlinks** — `ln -s` is banned in scripts *and* in role docs | Windows needs admin rights / Developer Mode; Git Bash silently substitutes a copy. `save-latest.sh` writes a copy on purpose |
| **LF only** (`.gitattributes` pins `*.sh eol=lf`) | A CRLF checkout turns the shebang into `bash\r` → "bad interpreter" for every script |
| **No package manager assumed** — hints come from `_install_hint` via `os_kind()` | brew · apt-get · dnf · pacman · apk · winget/scoop, picked per machine |
| **Core counts via `cpu_cores()`** | `nproc` (Linux) → `sysctl -n hw.ncpu` (macOS) → `$NUMBER_OF_PROCESSORS` (Windows) |
| **Build paths from `repo_root()`, never string-compare path shapes** | Under Git Bash `git rev-parse --show-toplevel` gives `C:/src/repo` while `pwd` gives `/c/src/repo`; both open the same files, but they are not equal strings |
| **`jq`/`curl` are guarded, not assumed** | `init_platform` calls `require_cmd jq curl`; create-tests avoids both entirely (awk + node) |

## Validation

```bash
bash scripts/validate.sh            # static checks; errors + warnings; non-zero on any error
bash scripts/validate.sh --strict   # warnings fail too (used in CI)
bash scripts/smoke.sh               # executes the scripts for real on this machine
```

`validate.sh` greps; `smoke.sh` runs. The second is what catches an OS difference a grep can't see — a BSD
flag, a missing tool, Git Bash path shapes — including a check that `require_bash` actually rejects the
system bash 3.2 when one is present. [`.github/workflows/validate.yml`](../.github/workflows/validate.yml)
runs both on ubuntu + macos + windows (matrix, `shell: bash`) plus `shellcheck -S warning`.

Static only — nothing is installed and no skill runs. It checks:

1. every `*.sh` parses (`bash -n`)
2. every JSON manifest/schema parses
3. the project-config template's keys all exist in `schemas/project-config.schema.json`
4. every `scripts/<name>.sh` referenced by a `SKILL.md` / `roles/*.md` exists **in that skill**
5. every `rules/…` / `roles/…` path those files reference exists
6. agent defs: filename matches frontmatter `name`, `description` + `tools` present, **no pinned `model:`**
7. every `subagent_type` a role dispatches has a matching `agents/<name>.md`
8. flags agree across a skill's Input table ↔ `argument-hint` ↔ `scripts/help.sh` *(warning)*
9. both plugin manifests carry the same `version`
10. `watermark_template` values use `{skillName}` instead of a hardcoded skill name *(warning)*
11. scoped command keys (`test_command*`) carry `{spec}`/`{classes}`; whole-project keys
    (`install_command`, `build_command`, `test_command_all`) carry no placeholder at all
12. every `--flag` a `SKILL.md` / role / platform doc hands to a `scripts/*.sh` is parsed by that script
13. platform libs are at dispatch parity (every `platform_dispatch <fn>` implemented by all of them),
    `init_platform` still calls `require_cmd jq`, and nothing runs `jq`/`curl` unguarded
14. the portability contract above: `.gitattributes` pins LF, no CRLF in tracked files, no `ln -s`, no
    GNU-only flags, bash-4 constructs only where `require_bash` has run, install hints beyond Homebrew,
    and no embedded `open()` without `encoding=` (Windows Python defaults to cp1252)

Checks 4–7 and 12–13 are the ones that catch the drift a human review misses: a renamed script, a moved
rules file, a role dispatching an agent type that was never defined, a doc passing a flag the script
silently ignores (which is how a per-file analyst ends up reading the whole diff), or a platform lib that
lost a function the dispatcher still calls.

## Extending

**Add a language to a skill**: create `skills/<skill>/rules/<lang>/index.md` (+ optional `cases/*.md`, and
for create-tests `types/<type>.md` plus `scripts/lib/lang-<lang>.sh`). It loads additively on top of
`rules/generic.md`; register the extension map in the skill's SKILL.md (and in `detect_lang` for
create-tests). Both skills use the same `rules/<lang>/` layout.

**Add a role**: `skills/<skill>/roles/<role>.md` + `agents/supensour-<domain>-<role>.md` (no `model:` in the
frontmatter — the dispatcher passes it).
