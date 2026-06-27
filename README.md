# supensour-agent

Reusable AI-agent skills for software-development workflows. Packaged as a Claude
Code plugin (namespace `supensour`); skill bodies are plain Markdown so other AI
agents can reuse them too.

## Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `review-code` | `supensour:review-code` | Generic, parameterized code review of a diff/branch/files. |
| `create-tests` | `supensour:create-tests` | Generic, parameterized test generation. |

All skills are language-agnostic and extensible via parameters (`--lang`,
`--severity`, `--framework`, …) and per-language rule files in `skills/<skill>/rules/`.

## Install (Claude Code)

```
/plugin marketplace add https://github.com/supensour/supensour-agent
/plugin install supensour@supensour-agent
```

Skills then appear as `supensour:review-code` and `supensour:create-tests`.

### Update

Pull the latest version after changes are pushed to the repo:

```
/plugin marketplace update supensour-agent
/reload-plugins
/reload-skills
```

This re-syncs the marketplace from the repo's default branch (`master`). Restart the session (or
re-run `/plugin install`) if a skill's metadata changed.

## Layout

```
.claude-plugin/        plugin.json (namespace "supensour") + marketplace.json
skills/<skill>/        SKILL.md + rules/ + templates/
```

## Configuration

**Global platform catalog** — `~/.claude/config/supensour.yaml` (lists the git platforms skills can use):

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

**Per-repo hints** (optional) — `<repo>/.supensour/config/config.yaml` lets skills skip detection
(see [examples/project-config.yaml](examples/project-config.yaml)):

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/supensour/supensour-agent/master/schemas/project-config.schema.json
git:
  platform: gitlab-ce                  # key into the global catalog → skip platform auto-detect
  token_env: MY_GITLAB_TOKEN           # override the platform's token_env for this repo
  base_branch:                         # default diff base → skip base detection
project:
  language: vue                        # default --lang for review-code / create-tests
  test_type: unit                      # default --type for create-tests
```

Precedence: CLI flag > per-repo config > global catalog `default` > auto-detect.

**Repo config** — [supensour-config.yaml](supensour-config.yaml) at the repo root holds plugin-baked
settings (not per-user / per-target-repo). Currently the attribution **watermark** shown on skill output
(PR/MR comments, generated tests, local report, console):

```yaml
watermark_template: "Generated with skill {skillName} · suprayan@supensour · github.com/supensour/supensour-agent"
skills:           # optional per-skill overrides (future config lives here too)
  review-code:
    # watermark_template: "Reviewed by {skillName} · suprayan@supensour"
  create-tests:
```

Resolution: `skills.<skill>.watermark_template` > top-level `watermark_template` > built-in default.
`{skillName}` → e.g. `supensour:review-code`.

**Schemas** for all three config files live in [schemas/](schemas/) (JSON Schema draft-07). The top-of-file
`# yaml-language-server: $schema=…` modeline gives editors (VS Code "YAML" extension) type hints +
validation. Point it at the raw GitHub URL once published, or a local absolute path.

## Extending

Add a language to a skill: drop `skills/<skill>/rules/<lang>.md`. It loads
additively on top of `rules/generic.md`.

## License

MIT — see [LICENSE](LICENSE).
