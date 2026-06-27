#!/usr/bin/env bash
# platform-github.sh — GitHub (github.com + Enterprise Server) implementation.
# Implements the uniform platform interface: <type>_fetch_pr / _post_summary /
# _post_inline / _post_file / _delete_prior. Sourced by common.sh.
# Requires: $TOKEN, $OWNER, $REPO from common.sh; jq, curl.

# REST API base — github.com vs Enterprise (HOST/api/v3).
_gh_base() {
  if [ -z "${HOST:-}" ] || printf '%s' "$HOST" | grep -qE 'github\.com|api\.github\.com'; then
    printf 'https://api.github.com'
  else
    printf '%s/api/v3' "${HOST%/}"
  fi
}

# _gh_api METHOD PATH [curl-args...] → body + final line = HTTP status code.
_gh_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -w $'\n%{http_code}' \
    "$@" "$(_gh_base)$path"
}

# github_fetch_pr <SRC> → JSON array of ALL open PRs for the branch ([] if none).
#   [{number,url,title,base}, ...]
github_fetch_pr() {
  local src="$1"
  if [ -n "${TOKEN:-}" ]; then
    _gh_api GET "/repos/$OWNER/$REPO/pulls?head=$OWNER:$src&state=open" | _body \
      | jq -c 'if type=="array" then map({number, url:.html_url, title, base:.base.ref}) else [] end' 2>/dev/null || printf '[]'
  elif command -v gh >/dev/null 2>&1; then
    gh pr list --head "$src" --state open --json number,url,title,baseRefName 2>/dev/null \
      | jq -c 'map({number, url, title, base:.baseRefName})' 2>/dev/null || printf '[]'
  else
    printf '[]'
  fi
}

# github_post_summary <pr> <body> → posts a PR-level (issue) comment. Prints url.
github_post_summary() {
  local pr="$1" payload resp code
  payload="$(jq -n --arg b "$(decorate_body "$2")" '{body:$b}')"
  resp="$(_gh_api POST "/repos/$OWNER/$REPO/issues/$pr/comments" -d "$payload")"
  code="$(printf '%s' "$resp" | _code)"
  [ "$code" = 201 ] && printf '%s' "$resp" | _body | jq -r '.html_url' || { warn "GitHub summary post failed (HTTP $code)"; return 1; }
}

# github_post_inline <pr> <path> <line> <body> → review comment at line. 0=ok.
github_post_inline() {
  local pr="$1" path="$2" line="$3" body="$4" sha payload resp code
  sha="${HEAD_SHA:-$(git rev-parse HEAD)}"
  payload="$(jq -n --arg b "$(decorate_body "$body")" --arg p "$path" --argjson l "$line" --arg c "$sha" \
    '{body:$b, path:$p, line:$l, side:"RIGHT", commit_id:$c}')"
  resp="$(_gh_api POST "/repos/$OWNER/$REPO/pulls/$pr/comments" -d "$payload")"
  code="$(printf '%s' "$resp" | _code)"
  [ "$code" = 201 ]
}

# github_post_file <pr> <path> <body> → file-level comment (no line). 0=ok.
github_post_file() {
  local pr="$1" path="$2" body="$3" sha payload resp code
  sha="${HEAD_SHA:-$(git rev-parse HEAD)}"
  payload="$(jq -n --arg b "$(decorate_body "$body")" --arg p "$path" --arg c "$sha" \
    '{body:$b, path:$p, commit_id:$c, subject_type:"file"}')"
  resp="$(_gh_api POST "/repos/$OWNER/$REPO/pulls/$pr/comments" -d "$payload")"
  code="$(printf '%s' "$resp" | _code)"
  [ "$code" = 201 ]
}

# github_delete_prior <pr> → delete our review + issue comments (marker match). Prints count.
github_delete_prior() {
  local pr="$1" n=0 ids id
  # Review (inline + file) comments.
  ids="$(_gh_api GET "/repos/$OWNER/$REPO/pulls/$pr/comments?per_page=100" | _body \
        | jq -r --arg m "$MARKER" '.[]? | select(.body|contains($m)) | .id')"
  for id in $ids; do
    _gh_api DELETE "/repos/$OWNER/$REPO/pulls/comments/$id" >/dev/null && n=$((n+1))
  done
  # PR-level (issue) comments — the summary.
  ids="$(_gh_api GET "/repos/$OWNER/$REPO/issues/$pr/comments?per_page=100" | _body \
        | jq -r --arg m "$MARKER" '.[]? | select(.body|contains($m)) | .id')"
  for id in $ids; do
    _gh_api DELETE "/repos/$OWNER/$REPO/issues/comments/$id" >/dev/null && n=$((n+1))
  done
  printf '%s' "$n"
}
