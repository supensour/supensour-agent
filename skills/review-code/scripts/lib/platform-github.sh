#!/usr/bin/env bash
# platform-github.sh — GitHub (github.com + Enterprise Server) implementation.
# Implements the uniform platform interface: <type>_fetch_pr / _post_summary /
# _post_inline / _post_file / _list_prior / _update_comment / _resolve_comment.
# Sourced by common.sh. Reconcile never deletes comments (see reconcile-comments.sh).
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
#   [{number,url,title,source,base}, ...]   (source = head branch, base = target branch)
github_fetch_pr() {
  local src="$1"
  if [ -n "${TOKEN:-}" ]; then
    _gh_api GET "/repos/$OWNER/$REPO/pulls?head=$OWNER:$src&state=open" | _body \
      | jq -c 'if type=="array" then map({number, url:.html_url, title, source:.head.ref, base:.base.ref}) else [] end' 2>/dev/null || printf '[]'
  elif command -v gh >/dev/null 2>&1; then
    gh pr list --head "$src" --state open --json number,url,title,headRefName,baseRefName 2>/dev/null \
      | jq -c 'map({number, url, title, source:.headRefName, base:.baseRefName})' 2>/dev/null || printf '[]'
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

# GraphQL endpoint (github.com vs Enterprise) — used to resolve/collapse comments.
_gh_graphql_base() {
  if [ -z "${HOST:-}" ] || printf '%s' "$HOST" | grep -qE 'github\.com|api\.github\.com'; then
    printf 'https://api.github.com/graphql'
  else
    printf '%s/api/graphql' "${HOST%/}"
  fi
}
_gh_graphql() {  # <query> <variables-json> → body + final line = HTTP status
  curl -sS -X POST \
    -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
    -w $'\n%{http_code}' \
    --data "$(jq -n --arg q "$1" --argjson v "$2" '{query:$q, variables:$v}')" \
    "$(_gh_graphql_base)"
}

# _gh_prior_jq <kind> — jq program mapping our comments to {id,aux,kind,fp,h}.
#   aux = node_id (GraphQL subject id, needed to resolve/collapse).
_gh_prior_jq='[ .[]? | select(.body|test("supensour:review-code"))
  | . as $c
  | ( ($c.body|capture("fp=(?<fp>[a-z0-9]+) h=(?<h>[a-z0-9]+)"))? // {fp:"",h:""} ) as $m
  | {id:$c.id, aux:($c.node_id // ""), kind:$k, fp:$m.fp, h:$m.h} ]'

# github_list_prior <pr> → JSON array of our prior comments [{id,aux,kind,fp,h}].
#   kind: "issue" (summary / top-level) | "review" (inline + file-level).
github_list_prior() {
  local pr="$1"
  { _gh_api GET "/repos/$OWNER/$REPO/pulls/$pr/comments?per_page=100" | _body \
      | jq -c --arg k review "$_gh_prior_jq" 2>/dev/null || printf '[]'
    _gh_api GET "/repos/$OWNER/$REPO/issues/$pr/comments?per_page=100" | _body \
      | jq -c --arg k issue "$_gh_prior_jq" 2>/dev/null || printf '[]'
  } | jq -cs 'add // []'
}

# github_update_comment <pr> <id> <aux> <kind> <body> → edit in place. 0=ok.
github_update_comment() {
  local pr="$1" id="$2" kind="$4" body="$5" path payload code
  payload="$(jq -n --arg b "$(decorate_body "$body")" '{body:$b}')"
  if [ "$kind" = issue ]; then path="/repos/$OWNER/$REPO/issues/comments/$id"
  else path="/repos/$OWNER/$REPO/pulls/comments/$id"; fi
  code="$(_gh_api PATCH "$path" -d "$payload" | _code)"
  [ "$code" = 200 ]
}

# github_resolve_comment <pr> <id> <aux=node_id> <kind> → collapse as RESOLVED. 0=ok.
# Never deletes — minimizeComment marks the comment resolved/collapsed on the PR page.
github_resolve_comment() {
  local node="$3" code
  [ -n "$node" ] || return 1
  code="$(_gh_graphql \
    'mutation($id:ID!){minimizeComment(input:{subjectId:$id,classifier:RESOLVED}){minimizedComment{isMinimized}}}' \
    "$(jq -n --arg id "$node" '{id:$id}')" | _code)"
  [ "$code" = 200 ]
}
