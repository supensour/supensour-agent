#!/usr/bin/env bash
# validate.sh — repo self-check. Run before committing or releasing:
#   bash scripts/validate.sh            # errors + warnings
#   bash scripts/validate.sh --strict   # warnings count as failures
#
# Checks (all static — nothing is installed, no skill is executed):
#   1. every *.sh parses (bash -n)
#   2. every JSON manifest/schema parses
#   3. the project-config template's keys all exist in project-config.schema.json
#   4. every scripts/<name>.sh referenced by a SKILL.md / roles/*.md exists in that skill
#   5. every rules/ + roles/ path referenced by a SKILL.md / roles/*.md exists
#   6. agent definitions: filename == frontmatter name, tools present, no pinned model
#   7. every subagent_type referenced in a role has a matching agents/*.md
#   8. flags stay in sync: SKILL.md Input table ↔ argument-hint ↔ scripts/help.sh
#   9. plugin manifests agree on version
#  10. watermark templates use {skillName} rather than a hardcoded skill name
#  11. command keys use the right placeholders: scoped keys need {spec}, whole-project
#      keys must have none (a scoped command pasted into a gate key would run one file)
#  12. every flag a SKILL.md / role passes to a scripts/*.sh is parsed by that script
#      (a doc telling an agent to pass an ignored flag silently loses the scoping)
#  13. platform libs are at parity: every `platform_dispatch <fn>` is implemented by all
#      of them, and every jq/curl user reaches a require_cmd guard
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

ERRORS=0 WARNINGS=0 STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

err()  { printf '✖ %s\n' "$*" >&2; ERRORS=$((ERRORS + 1)); }
wrn()  { printf '⚠ %s\n' "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
sect() { printf '\n── %s\n' "$*"; }

have_python() { command -v python3 >/dev/null 2>&1; }

# --- 1. shell syntax --------------------------------------------------------
sect "shell syntax"
count=0
while IFS= read -r f; do
  count=$((count + 1))
  bash -n "$f" 2>/dev/null || err "syntax error: $f"
done < <(find lib skills scripts -name '*.sh' -type f 2>/dev/null | sort)
printf '   %d script(s) parsed\n' "$count"

# --- 2. JSON --------------------------------------------------------------
sect "JSON manifests + schemas"
if have_python; then
  while IFS= read -r f; do
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null \
      || err "invalid JSON: $f"
  done < <(find schemas .claude-plugin .cursor-plugin -name '*.json' -type f 2>/dev/null; ls plugin.json 2>/dev/null)
  printf '   parsed\n'
else
  wrn "python3 not found — skipped JSON, template/schema, flag and version checks"
fi

# --- 3. template keys ⊆ schema --------------------------------------------
sect "project-config template ↔ schema"
if have_python; then
  # A key line is `  key:` or `  # key:` at the section's own indent. Deeper comment
  # indentation (`  #   npm: "…"`) is prose/examples, not a key.
  python3 - <<'PY'
import json, re, sys
tpl = 'examples/project-config.template.yaml'
schema = json.load(open('schemas/project-config.schema.json'))
props = schema['properties']
section, bad = None, []
for raw in open(tpl):
    line = raw.rstrip('\n')
    if line.lstrip().startswith('##'):
        continue
    m = re.match(r'^([a-z_]+):\s*$', line)
    if m:
        section = m.group(1)
        if section not in props:
            bad.append(f'unknown section `{section}:`')
        continue
    m = re.match(r'^  (?:# )?([a-z_]+):', line)
    if m and section in props:
        key = m.group(1)
        if key not in props[section].get('properties', {}):
            bad.append(f'`{section}.{key}` is in the template but not in the schema')
for b in bad:
    print(f'✖ {b}', file=sys.stderr)
sys.exit(1 if bad else 0)
PY
  if [ $? -eq 0 ]; then printf '   template keys all documented\n'; else ERRORS=$((ERRORS + 1)); fi
fi

# --- 4./5. referenced paths exist ------------------------------------------
sect "referenced scripts, rules and roles exist"
for skill_dir in skills/*/; do
  skill="${skill_dir%/}"; skill="${skill#skills/}"
  while IFS= read -r src; do
    # scripts/<name>.sh
    while IFS= read -r ref; do
      [ -f "skills/$skill/$ref" ] || err "$src references missing $ref (skill: $skill)"
    done < <(grep -ohE 'scripts/[a-z0-9-]+\.sh' "$src" 2>/dev/null | sort -u)
    # rules/... and roles/... markdown
    while IFS= read -r ref; do
      [ -f "skills/$skill/$ref" ] || err "$src references missing $ref (skill: $skill)"
    done < <(grep -ohE '(rules|roles)/[a-z0-9/._-]+\.md' "$src" 2>/dev/null \
             | grep -vE 'rules/<|roles/<|/\*' | sort -u)
  done < <(find "skills/$skill" -maxdepth 2 -name 'SKILL.md' -o -maxdepth 2 -path "*/roles/*.md" | sort)
done
printf '   checked\n'

# --- 6./7. agent definitions ------------------------------------------------
sect "agent definitions"
for f in agents/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f" .md)"
  name="$(awk -F': *' '/^name:/{print $2; exit}' "$f")"
  [ "$name" = "$base" ] || err "$f: frontmatter name '$name' != filename '$base'"
  grep -q '^description:' "$f" || err "$f: missing description"
  grep -q '^tools:' "$f"       || err "$f: missing tools"
  grep -q '^model:' "$f"       && err "$f: pins model: — the dispatcher passes the model (see ARCHITECTURE)"
done
while IFS= read -r t; do
  [ -f "agents/$t.md" ] || err "role files reference subagent_type '$t' but agents/$t.md is missing"
done < <(grep -rhoE 'subagent_type: `?[a-z-]+' skills/*/roles/*.md 2>/dev/null \
         | sed -E 's/.*subagent_type: `?//' | sort -u)
printf '   checked\n'

# --- 8. flag sync -----------------------------------------------------------
sect "flags: Input table ↔ argument-hint ↔ help.sh"
if have_python; then
  python3 - <<'PY'
import glob, re, sys
warn = 0
for skill in sorted(glob.glob('skills/*/SKILL.md')):
    text = open(skill).read()
    d = skill.rsplit('/', 1)[0]
    hint = re.search(r'^argument-hint:\s*"(.*)"', text, re.M)
    hint_flags = set(re.findall(r'--[a-z-]+', hint.group(1))) if hint else set()
    table = set()
    for m in re.finditer(r'^\|\s*`(--[a-z-]+)', text, re.M):
        table.add(m.group(1))
    try:
        help_flags = set(re.findall(r'--[a-z-]+', open(f'{d}/scripts/help.sh').read()))
    except OSError:
        help_flags = set()
    for flag in sorted(table - hint_flags):
        print(f'⚠ {skill}: `{flag}` documented in the Input table but missing from argument-hint', file=sys.stderr); warn += 1
    for flag in sorted(table - help_flags):
        print(f'⚠ {skill}: `{flag}` documented in the Input table but missing from help.sh', file=sys.stderr); warn += 1
    for flag in sorted(hint_flags - table):
        print(f'⚠ {skill}: `{flag}` in argument-hint but not in the Input table', file=sys.stderr); warn += 1
sys.exit(2 if warn else 0)
PY
  [ $? -eq 2 ] && WARNINGS=$((WARNINGS + 1)) || printf '   in sync\n'
fi

# --- 9. version agreement ---------------------------------------------------
sect "plugin versions"
if have_python; then
  v1="$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json')).get('version',''))")"
  v2="$(python3 -c "import json;print(json.load(open('.cursor-plugin/plugin.json')).get('version',''))")"
  if [ "$v1" = "$v2" ] && [ -n "$v1" ]; then
    printf '   %s\n' "$v1"
  else
    err "version mismatch: .claude-plugin=$v1 .cursor-plugin=$v2"
  fi
fi

# --- 10. watermark placeholders --------------------------------------------
sect "watermark templates"
while IFS= read -r line; do
  case "$line" in
    *'{skillName}'*) : ;;
    *) wrn "supensour-config.yaml: watermark_template without {skillName} → $line" ;;
  esac
done < <(grep -nE '^\s*watermark_template:' supensour-config.yaml 2>/dev/null | grep -v '^\s*#')
printf '   checked\n'

# --- 11. command-key placeholders ------------------------------------------
sect "command keys ↔ placeholders"
if have_python; then
  python3 - <<'PY'
import glob, json, re, sys
SCOPED = {'test_command', 'test_command_coverage'}          # per-file → need {spec}
WHOLE  = {'install_command', 'build_command', 'test_command_all'}   # gate → no placeholders
warn = 0

# The schema must document every key both skills read.
props = json.load(open('schemas/project-config.schema.json'))['properties']['project']['properties']
for key in sorted(SCOPED | WHOLE):
    if key not in props:
        print(f'✖ schemas/project-config.schema.json: project.{key} is undocumented', file=sys.stderr)
        sys.exit(1)

# Every example in the schema must obey its key's placeholder contract.
for key in sorted(SCOPED | WHOLE):
    for ex in props[key].get('examples', []):
        has = set(re.findall(r'\{[a-z_]+\}', ex))
        if key in SCOPED and '{spec}' not in has and '{classes}' not in has:
            print(f'⚠ schema example for {key} has no {{spec}}/{{classes}}: {ex}', file=sys.stderr); warn += 1
        if key in WHOLE and has:
            print(f'⚠ schema example for {key} is whole-project but uses {sorted(has)}: {ex}', file=sys.stderr); warn += 1

# Same contract for any value set in the shipped template (commented or not).
tpl = open('examples/project-config.template.yaml').read()
for m in re.finditer(r'^\s*#?\s*([a-z_]+):\s*"([^"]+)"', tpl, re.M):
    key, val = m.group(1), m.group(2)
    if key not in (SCOPED | WHOLE):
        continue
    has = set(re.findall(r'\{[a-z_]+\}', val))
    if key in SCOPED and not has:
        print(f'⚠ template: {key} without placeholders: {val}', file=sys.stderr); warn += 1
    if key in WHOLE and has:
        print(f'⚠ template: {key} is whole-project but uses {sorted(has)}: {val}', file=sys.stderr); warn += 1
sys.exit(2 if warn else 0)
PY
  rc=$?
  if [ "$rc" -eq 1 ]; then ERRORS=$((ERRORS + 1))
  elif [ "$rc" -eq 2 ]; then WARNINGS=$((WARNINGS + 1))
  else printf '   scoped vs whole-project keys consistent\n'; fi
fi

# --- 12. documented script flags are actually parsed -------------------------
# The bug this catches: a role told analysts to run `collect-diff.sh "$BASE" HEAD -- <file>`
# while the script parsed only 3 positional args, so every analyst silently read the WHOLE
# diff. A flag that a doc hands to a script must exist in that script's own argument parsing.
sect "documented script flags ↔ script parsing"
if have_python; then
  python3 - <<'PY'
import glob, os, re, sys
bad = []
for skill_dir in sorted(glob.glob('skills/*')):
    docs = glob.glob(f'{skill_dir}/SKILL.md') + glob.glob(f'{skill_dir}/roles/*.md') \
         + glob.glob(f'{skill_dir}/platforms/*.md')
    for doc in sorted(docs):
        for line in open(doc):
            m = re.search(r'scripts/([a-z0-9-]+)\.sh"?(.*)$', line)
            if not m:
                continue
            script = f'{skill_dir}/scripts/{m.group(1)}.sh'
            if not os.path.exists(script):
                continue                      # check 4 already reports missing scripts
            src = open(script).read()
            for flag in set(re.findall(r'(?<![-\w])--[a-z][a-z-]+', m.group(2))):
                # A placeholder list like `[--skip-tests]` still counts: the doc tells an
                # agent it may pass it.
                if flag not in src:
                    bad.append(f'{doc}: passes `{flag}` to scripts/{m.group(1)}.sh, '
                               f'which never parses it')
for b in sorted(set(bad)):
    print(f'✖ {b}', file=sys.stderr)
sys.exit(1 if bad else 0)
PY
  rc=$?
  if [ "$rc" -eq 0 ]; then printf '   every documented flag is parsed\n'; else ERRORS=$((ERRORS + 1)); fi
fi

# --- 13. platform parity + external-tool guards ------------------------------
sect "platform libs: dispatch parity + tool guards"
RC_LIB="skills/review-code/scripts/lib"
if [ -d "$RC_LIB" ]; then
  # Every fn suffix reached via platform_dispatch must exist in every platform-*.sh.
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    for lib in "$RC_LIB"/platform-*.sh; do
      type="$(basename "$lib" .sh)"; type="${type#platform-}"
      grep -qE "^${type}_${fn}\(\)" "$lib" \
        || err "$lib does not implement ${type}_${fn} (reached via platform_dispatch $fn)"
    done
  done < <(grep -rhoE 'platform_dispatch [a-z_]+' skills/review-code/scripts \
           | awk '{print $2}' | sort -u)

  # init_platform is the upstream guard every platform path goes through — assert it still
  # guards, otherwise the check below passes on a file that only *mentions* init_platform.
  grep -qE '^ *require_cmd .*jq' "$RC_LIB/common.sh" \
    || err "$RC_LIB/common.sh: init_platform no longer calls require_cmd jq — every platform script loses its guard"

  # Anything that RUNS jq/curl must reach a require_cmd guard — in the file itself, or via
  # init_platform (which guards both). platform-*.sh is only ever sourced by init_platform,
  # so its guard is upstream by construction. Comment lines don't count as usage.
  while IFS= read -r f; do
    case "$f" in */lib/platform-*.sh) continue ;; esac
    grep -qE 'require_cmd|init_platform|deps_report' "$f" && continue
    wrn "$f runs jq/curl without reaching a require_cmd guard (init_platform or explicit)"
  done < <(grep -rlE '^[^#]*(^|[^a-z_.-])(jq|curl) ' skills/*/scripts 2>/dev/null | sort -u)
  printf '   checked\n'
fi

# --- 14. portability ---------------------------------------------------------
# Contract: bash 4+ on Linux, macOS and Windows (Git Bash / WSL). No GNU-only flags,
# no symlinks, no CRLF, no package manager assumed.
sect "portability (linux · macos · windows/git-bash)"

# .gitattributes must pin LF for scripts, or a Windows clone gets CRLF shebangs.
if [ -f .gitattributes ]; then
  grep -qE '^\*\.sh[[:space:]]+.*eol=lf' .gitattributes \
    || err ".gitattributes does not pin *.sh to eol=lf — a Windows clone would break every shebang"
else
  err "no .gitattributes — a Windows clone with core.autocrlf=true breaks every script's shebang"
fi

# No CRLF in tracked text files.
while IFS= read -r f; do
  case "$f" in *.bat|*.cmd) continue ;; esac
  LC_ALL=C grep -qU $'\r' "$f" 2>/dev/null && err "CRLF line endings in $f (must be LF)"
done < <(git ls-files -- '*.sh' '*.md' '*.json' '*.yaml' '*.yml' 2>/dev/null)

# The two greps below scan real code only: this script is full of the very patterns it
# looks for, and a comment explaining why `ln -s` is banned is not a use of it.
# `<file>:<line>:` followed by optional space and `#` = comment line.
code_lines() { grep -rnE "$1" lib skills scripts --include='*.sh' --include='*.md' 2>/dev/null \
                 | grep -v '^scripts/validate\.sh:' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true; }

# Symlinks: Windows needs admin rights / Developer Mode to create one. Docs are scanned
# too — a role telling an agent to `ln -s` breaks Windows just as surely as a script
# doing it — minus lines that *forbid* it.
while IFS= read -r line; do
  [ -n "$line" ] && err "symlink creation ($line) — Windows needs admin rights; write a copy instead"
done < <(code_lines '(^|[^a-z-])ln -s' | grep -viE 'never|instead|banned|forbid|do not|don.t')

# GNU-only flags that silently differ or fail on BSD (macOS) userland.
while IFS= read -r hit; do
  [ -n "$hit" ] && err "GNU-only usage: $hit"
done < <(code_lines "sed -i[^ ']|readlink -f|stat -c|find [^|]*-printf|grep -P|sort -V|xargs -r|date -d |date --date")

# bash 4 constructs are allowed, but only where lib/core.sh's require_bash has run
# (i.e. the script sources its skill's common.sh) — otherwise bash 3.2 degrades silently.
while IFS= read -r f; do
  [ "$f" = "lib/core.sh" ] && continue
  grep -qE '(lib/common\.sh|lib/core\.sh)' "$f" \
    || err "$f uses a bash-4 construct (declare -A / globstar / mapfile) without sourcing common.sh (no require_bash guard)"
done < <(grep -rlE 'declare -A|shopt -s [a-z ]*globstar|mapfile|readarray' lib skills scripts 2>/dev/null | sort -u)

# Install hints must cover more than Homebrew.
if [ -f lib/core.sh ]; then
  for mgr in 'apt-get' 'winget'; do
    grep -q "$mgr" lib/core.sh || err "lib/core.sh install hints never mention $mgr — non-macOS users get no usable hint"
  done
fi
printf '   checked\n'

# --- summary ----------------------------------------------------------------
printf '\n'
if [ "$ERRORS" -gt 0 ]; then
  printf '✖ %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf '⚠ 0 errors, %d warning(s)\n' "$WARNINGS" >&2
  [ "$STRICT" -eq 1 ] && exit 1
  exit 0
fi
printf '✓ all checks passed\n'
