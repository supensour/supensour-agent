#!/usr/bin/env bash
# platform-gitlab.sh — GitLab (CE + EE, incl. self-hosted) implementation.
# Uniform interface: gitlab_fetch_pr/_post_summary/_post_inline/_post_file/_delete_prior.
# Project id = URL-encoded path ($PROJECT_PATH) accepted directly by the v4 API.
# Requires: $TOKEN, $HOST, $PROJECT_PATH from common.sh; jq, curl.

_gl_base() { printf '%s/api/v4/projects/%s' "${HOST%/}" "$PROJECT_PATH"; }

# _gl_api METHOD PATH [curl-args...] → body + final line = HTTP status code.
_gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" \
    -H "PRIVATE-TOKEN: $TOKEN" \
    -H "Content-Type: application/json" \
    -w $'\n%{http_code}' \
    "$@" "$(_gl_base)$path"
}

# gitlab_fetch_pr <SRC> → JSON array of ALL open MRs for the branch ([] if none).
gitlab_fetch_pr() {
  local src="$1"
  _gl_api GET "/merge_requests?source_branch=$src&state=opened" | _body \
    | jq -c 'if type=="array" then map({number:.iid, url:.web_url, title, base:.target_branch}) else [] end' 2>/dev/null || printf '[]'
}

# Cache MR diff refs (base/head/start sha) needed for inline discussion positions.
_gl_diffrefs() {  # <mr>
  [ -n "${_GL_REFS:-}" ] && { printf '%s' "$_GL_REFS"; return 0; }
  _GL_REFS="$(_gl_api GET "/merge_requests/$1/versions" | _body \
    | jq -c '.[0] | {base:.base_commit_sha, head:.head_commit_sha, start:.start_commit_sha}')"
  printf '%s' "$_GL_REFS"
}

gitlab_post_summary() {
  local mr="$1" payload resp code
  payload="$(jq -n --arg b "$(decorate_body "$2")" '{body:$b}')"
  resp="$(_gl_api POST "/merge_requests/$mr/notes" -d "$payload")"
  code="$(printf '%s' "$resp" | _code)"
  [ "$code" = 201 ] && printf '%s' "$resp" | _body | jq -r '.id' || { warn "GitLab summary post failed (HTTP $code)"; return 1; }
}

gitlab_post_inline() {
  local mr="$1" path="$2" line="$3" body="$4" refs payload code
  refs="$(_gl_diffrefs "$mr")"
  payload="$(jq -n --arg b "$(decorate_body "$body")" --arg p "$path" --argjson l "$line" --argjson r "$refs" \
    '{body:$b, position:{position_type:"text", base_sha:$r.base, head_sha:$r.head, start_sha:$r.start, new_path:$p, new_line:$l}}')"
  code="$(_gl_api POST "/merge_requests/$mr/discussions" -d "$payload" | _code)"
  [ "$code" = 201 ]
}

gitlab_post_file() {
  local mr="$1" path="$2" body="$3" refs payload code
  refs="$(_gl_diffrefs "$mr")"
  # File-level: position with paths but no line. Rejected on some versions → caller falls back to summary.
  payload="$(jq -n --arg b "$(decorate_body "$body")" --arg p "$path" --argjson r "$refs" \
    '{body:$b, position:{position_type:"text", base_sha:$r.base, head_sha:$r.head, start_sha:$r.start, new_path:$p, old_path:$p}}')"
  code="$(_gl_api POST "/merge_requests/$mr/discussions" -d "$payload" | _code)"
  [ "$code" = 201 ]
}

gitlab_delete_prior() {
  local mr="$1" n=0 ids id
  ids="$(_gl_api GET "/merge_requests/$mr/notes?per_page=100" | _body \
        | jq -r --arg m "$MARKER" '.[]? | select(.body|contains($m)) | .id')"
  for id in $ids; do
    _gl_api DELETE "/merge_requests/$mr/notes/$id" >/dev/null && n=$((n+1))
  done
  printf '%s' "$n"
}
