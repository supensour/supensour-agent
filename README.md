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

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — repo layout, configuration model, plugin manifests, extending.

## License

MIT — see [LICENSE](LICENSE).
