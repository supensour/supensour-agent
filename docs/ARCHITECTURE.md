# Architecture

Implementation reference for `supensour-agent`: repo layout, configuration model,
plugin manifests, and how to extend skills. For install/usage see the [README](../README.md).

## Layout

```
.claude-plugin/        plugin.json (namespace "supensour") + marketplace.json
.cursor-plugin/        plugin.json (Cursor)
plugin.json            root manifest (Antigravity)
skills/<skill>/        SKILL.md + rules/ + templates/ + scripts/
schemas/               JSON Schema (draft-07) for the config files
examples/              sample config files
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

Lets skills skip detection (see [examples/project-config.yaml](../examples/project-config.yaml)):

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

## Extending

Add a language to a skill: drop `skills/<skill>/rules/<lang>.md`. It loads additively on top of
`rules/generic.md`.
