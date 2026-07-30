# supensour-agent

Reusable AI-agent skills for software-development workflows. Skill bodies are plain
Markdown, so they work across AI coding tools — Claude Code, GitHub Copilot,
Antigravity, and Cursor.

## Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `review-code` | `/review-code` | Generic, parameterized code review of a diff/branch/files. |
| `create-tests` | `/create-tests` | Generic, parameterized test generation. |

> **Claude Code** namespaces plugin skills by the plugin, so invoke them as
> `/supensour:review-code` and `/supensour:create-tests`. Cursor, Antigravity, and
> Copilot use the bare `/review-code` / `/create-tests`.

All skills are language-agnostic and tunable via flags plus per-language rule files under
`skills/<skill>/rules/<lang>/`. Run `/<skill> --help` for the full list; the common ones:

| Flag | Skills | Purpose |
|------|--------|---------|
| `--lang <key>` | both | Force the language ruleset (`vue`, `springboot`, …) instead of detecting it |
| `--files <glob>` | both | Repeatable glob — scope the run to specific paths. `*` (not across `/`), `**`, `?`, `[abc]`, `{a,b}`; a bare directory means its subtree |
| `--base <branch>` | both | Diff base for change detection |
| `--pool <n>` | both | Max concurrent subagents (default ≈30% of cores) |
| `--analyst-model <key>` | both | Model for the per-file subagents (default `sonnet`; `inherit` = your session model) |
| `--writer-model <key>` | create-tests | Model for the spec writer (default `sonnet`) |
| `--coverage <n>` | create-tests | Coverage bar; targets already at/above it are skipped entirely |
| `--severity <list>` | review-code | Filter which findings are reported |
| `--scope diff\|project` | review-code | Diff-attributable findings only (default), or the whole project |
| `--explain` | both | Print the resolved run config and stop — no subagents, no writes |
| `--clean [branch]` / `--clean-all` | both | Remove the skill's saved work dirs |

### Requirements

Works on **Linux, macOS and Windows** — everything is bash + git, so Windows runs it under **Git Bash**
(ships with Git for Windows) or **WSL**. No PowerShell port, nothing to compile.

| | Linux | macOS | Windows |
|---|---|---|---|
| **bash 4+** | preinstalled | ⚠️ `/bin/bash` is 3.2 → `brew install bash` | Git Bash (4.4+) or WSL |
| **git** | preinstalled | preinstalled | Git for Windows |
| **jq**, **curl** — review-code PR/MR lookup + comments | `apt-get install jq` | `brew install jq` | `winget install jqlang.jq` (curl ships with Git) |
| **node** — create-tests Vue coverage gate *(optional)* | any Node ≥18 | any Node ≥18 | any Node ≥18 |

`node` is optional: without it the coverage gate can't read numbers, so every target is generated instead of
skipped — fail-safe, never a silent skip. Everything else fails loudly with the install command for *your*
OS. Check anytime:

```bash
bash skills/<skill>/scripts/deps.sh   # os · bash · git · jq · curl · gh, with paths
```

`/<skill> --explain` prints the same table plus the resolved run config.

Each skill splits its work across roles (`skills/<skill>/roles/`): an orchestrator that resolves scope and
dispatches, and per-file subagents that do the reading. Subagent definitions live in
[`agents/`](agents/) — **Claude Code only**; on Cursor, Antigravity and Copilot the same prompts run on a
generic subagent, so behavior matches but the named agent types don't appear.

## Install CLI

Install [supensour-agent-cli](https://github.com/supensour/supensour-agent-cli) with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/supensour/supensour-agent-cli/master/install-remote.sh | bash
```

Restart your shell afterward (or `export PATH="$HOME/.local/bin:$PATH"`).

## Install skills

```bash
supensour install            # all detected tools
supensour install claude     # or a single tool: claude | copilot | antigravity | cursor
```

Update later with `supensour update [tool]`.

After installing, the skills appear as `/review-code` and `/create-tests`
(`/supensour:review-code` in Claude Code — see the note above).

## Configuration

Optional, all detected automatically when absent:

| File | Scope | Holds |
|------|-------|-------|
| `~/.supensour/config/supensour.yaml` | per user | Git platform catalog (host, token env var) |
| `<repo>/.supensour/config/config.yaml` | per repo | Hints that skip detection: base branch, language, test commands. Created on first run from [`examples/project-config.template.yaml`](examples/project-config.template.yaml) |
| `supensour-config.yaml` | this plugin | Attribution watermark + author, overridable per skill |

Each has a JSON Schema in [`schemas/`](schemas/) — keep the `# yaml-language-server: $schema=…` line for
editor completion and validation.

## Contributing

Before committing a change to this repo, run the self-check:

```bash
bash scripts/validate.sh            # shell syntax, JSON, schema/template drift, broken references
bash scripts/validate.sh --strict   # warnings fail too
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — repo layout, configuration model, roles/subagents, plugin manifests, extending.

## License

MIT — see [LICENSE](LICENSE).
