# Platform detection

> **Executable source:** `scripts/detect-platform.sh` + `scripts/lib/common.sh`.
> This doc explains the logic; the script does it. Don't re-emit the commands —
> run the script and read its JSON.

```bash
bash "$SKILL_DIR/scripts/detect-platform.sh" [--platform <key>]
# → {"type","key","host","cli","token_env","token_present","owner","repo","workspace","project_path"}
```

## Config files

- **Global catalog** — `~/.supensour/config/supensour.yaml`: top-level `platform:` holding `default` +
  `platforms:` (key → definition). Per platform: `type`, `host`, `api_version`, `token_env`
  (+ `token_env_alternatives` block list), `cli`. Schema: `schemas/global-config.schema.json`.
  ```yaml
  platform:
    default: gitlab-ce
    platforms:
      gitlab-ce:
        type: gitlab
        host: https://git.example.com
        token_env: GITLAB_TOKEN
        token_env_alternatives:
          - MY_GITLAB_TOKEN
  ```
- **Per-repo hints** — `<repo>/.supensour/config/config.yaml` (nested), all optional, each skips a
  detection. Schema: `schemas/project-config.schema.json` (see `examples/project-config.yaml`):
  ```yaml
  git:
    platform: gitlab-ce                  # key into the global catalog → skip platform auto-detect
    token_env: MY_GITLAB_TOKEN           # override the platform's token_env for this repo
    base_branch: develop                 # default diff base → skip base detection
  project:
    language: vue                        # default --lang (review-code / create-tests)
  ```

Associate the schemas in editors with a top-of-file modeline:
`# yaml-language-server: $schema=<raw-URL or local path to the schema>`.

## Platform resolution order (in `init_platform`)

1. `--platform <key>` flag.
2. Project `git.platform` (from `.supensour/config/config.yaml`).
3. Global catalog `default` key.
4. Auto-detect from `git remote get-url origin` hostname:

   | Hostname contains | Type |
   |-------------------|------|
   | `github.`         | github |
   | `gitlab.`         | gitlab |
   | `bitbucket.`      | bitbucket |

## Token resolution

Precedence: **project `git.token_env`** → platform `token_env` → each `token_env_alternatives` entry.
First env var that is set wins. Missing token → `token_present:false`; the skill keeps the local review
and skips push/prune (see SKILL.md edge cases).

## Base branch & language hints

`detect-platform.sh` also emits `base_branch` and `language` from the per-repo config (empty if unset).
Use them to skip detection: base-branch priority becomes `--base` → project `git.base_branch` → PR target
→ repo default; `--lang` defaults to project `project.language`.

## Repo identity

`_resolve_repo_info` parses the origin URL into `OWNER`, `REPO`, `WORKSPACE` (Bitbucket), and
`PROJECT_PATH` (URL-encoded `namespace%2Fproject`, used directly as the GitLab project id).

## PR/MR detection

`scripts/fetch-pull-request.sh --branch <SRC>` finds **all** open PR/MRs whose **source branch = SRC** and
prints a JSON array `[{number, url, title, source, base}, ...]` (`source` = source branch, `base` =
target branch; `[]` if none; the skill asks the user to pick when more than one). Per-platform queries
live in `lib/platform-*.sh`
(`*_fetch_pr`): GitHub `pulls?head=owner:SRC&state=open`, GitLab
`merge_requests?source_branch=SRC&state=opened`, Bitbucket `pullrequests?q=source.branch.name=...`.

## Extending to a new platform

Add `scripts/lib/platform-<type>.sh` implementing `<type>_fetch_pr`, `_post_summary`, `_post_inline`,
`_post_file`, `_delete_prior` (same signatures as existing libs). Register its hostname in
`_autodetect_type` in `common.sh`. No other file changes — `platform_dispatch` routes by `type`.
