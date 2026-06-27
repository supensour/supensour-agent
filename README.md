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

All skills are language-agnostic and tunable via parameters (`--lang`, `--severity`,
`--framework`, …) plus per-language rule files.

## Install

**Recommended — [supensour-cli](https://github.com/supensour/supensour-cli):** one command
installs the skills into any supported AI tool at global scope.

```bash
git clone https://github.com/supensour/supensour-cli
cd supensour-cli && bash install.sh

supensour install            # all detected tools
supensour install claude     # or a single tool: claude | copilot | antigravity | cursor
```

Update later with `supensour update [tool]`.

<details>
<summary>Manual install (Claude Code)</summary>

```
/plugin marketplace add https://github.com/supensour/supensour-agent
/plugin install supensour@supensour
```

Update after changes are pushed:

```
/plugin marketplace update supensour
/reload-plugins
/reload-skills
```
</details>

After installing, the skills appear as `/review-code` and `/create-tests`
(`/supensour:review-code` in Claude Code — see the note above).

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — repo layout, configuration model, plugin manifests, extending.

## License

MIT — see [LICENSE](LICENSE).
