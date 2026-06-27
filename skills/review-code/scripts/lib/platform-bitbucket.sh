#!/usr/bin/env bash
# platform-bitbucket.sh — Bitbucket Cloud + Server implementation.
# Uniform interface: bitbucket_fetch_pr/_post_summary/_post_inline/_post_file/_delete_prior.
# Requires: $TOKEN, $HOST, $WORKSPACE/$OWNER, $REPO from common.sh; jq, curl.

# Server = self-hosted (HOST not on bitbucket.org). Cloud = api.bitbucket.org/2.0.
_bb_is_server() { [ -n "${HOST:-}" ] && ! printf '%s' "$HOST" | grep -q 'bitbucket\.org'; }
_bb_cloud_base()  { printf 'https://api.bitbucket.org/2.0/repositories/%s/%s' "$WORKSPACE" "$REPO"; }
_bb_server_base() { printf '%s/rest/api/1.0/projects/%s/repos/%s' "${HOST%/}" "$OWNER" "$REPO"; }
_bb_base() { if _bb_is_server; then _bb_server_base; else _bb_cloud_base; fi; }

_bb_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -w $'\n%{http_code}' \
    "$@" "$(_bb_base)$path"
}

# bitbucket_fetch_pr <SRC> → JSON array of ALL open PRs for the branch ([] if none).
bitbucket_fetch_pr() {
  local src="$1"
  if _bb_is_server; then
    _bb_api GET "/pull-requests?at=refs/heads/$src&direction=OUTGOING&state=OPEN" | _body \
      | jq -c '(.values // []) | map({number:.id, url:(.links.self[0].href), title, base:.toRef.displayId})' 2>/dev/null || printf '[]'
  else
    _bb_api GET "/pullrequests?q=source.branch.name=%22$src%22&state=OPEN" | _body \
      | jq -c '(.values // []) | map({number:.id, url:(.links.html.href), title, base:.destination.branch.name})' 2>/dev/null || printf '[]'
  fi
}

bitbucket_post_summary() {
  local pr="$1" payload resp code
  if _bb_is_server; then
    payload="$(jq -n --arg t "$(decorate_body "$2")" '{text:$t}')"
  else
    payload="$(jq -n --arg t "$(decorate_body "$2")" '{content:{raw:$t}}')"
  fi
  resp="$(_bb_api POST "/pull-requests/$pr/comments" -d "$payload")"
  # Cloud path differs (/pullrequests/, no hyphen) — retry on 404.
  code="$(printf '%s' "$resp" | _code)"
  if [ "$code" = 404 ] && ! _bb_is_server; then
    resp="$(_bb_api POST "/pullrequests/$pr/comments" -d "$payload")"
    code="$(printf '%s' "$resp" | _code)"
  fi
  { [ "$code" = 200 ] || [ "$code" = 201 ]; } || { warn "Bitbucket summary post failed (HTTP $code)"; return 1; }
}

_bb_comments_path() { if _bb_is_server; then printf '/pull-requests/%s/comments' "$1"; else printf '/pullrequests/%s/comments' "$1"; fi; }

bitbucket_post_inline() {
  local pr="$1" path="$2" line="$3" body="$4" payload code
  if _bb_is_server; then
    payload="$(jq -n --arg t "$(decorate_body "$body")" --arg p "$path" --argjson l "$line" \
      '{text:$t, anchor:{path:$p, line:$l, lineType:"ADDED", fileType:"TO"}}')"
  else
    payload="$(jq -n --arg t "$(decorate_body "$body")" --arg p "$path" --argjson l "$line" \
      '{content:{raw:$t}, inline:{path:$p, to:$l}}')"
  fi
  code="$(_bb_api POST "$(_bb_comments_path "$pr")" -d "$payload" | _code)"
  { [ "$code" = 200 ] || [ "$code" = 201 ]; }
}

bitbucket_post_file() {
  local pr="$1" path="$2" body="$3" payload code
  if _bb_is_server; then
    payload="$(jq -n --arg t "$(decorate_body "$body")" --arg p "$path" '{text:$t, anchor:{path:$p, fileType:"TO"}}')"
  else
    payload="$(jq -n --arg t "$(decorate_body "$body")" --arg p "$path" '{content:{raw:$t}, inline:{path:$p}}')"
  fi
  code="$(_bb_api POST "$(_bb_comments_path "$pr")" -d "$payload" | _code)"
  { [ "$code" = 200 ] || [ "$code" = 201 ]; }
}

bitbucket_delete_prior() {
  local pr="$1" n=0
  if _bb_is_server; then
    # Server delete requires the comment version; comments arrive via activities. Best-effort.
    local rows id ver
    rows="$(_bb_api GET "/pull-requests/$pr/activities?limit=100" | _body \
      | jq -r --arg m "$MARKER" '.values[]?.comment | select(.!=null) | select(.text|contains($m)) | "\(.id) \(.version)"')"
    while read -r id ver; do
      [ -z "$id" ] && continue
      _bb_api DELETE "/pull-requests/$pr/comments/$id?version=$ver" >/dev/null && n=$((n+1))
    done <<< "$rows"
  else
    local ids id
    ids="$(_bb_api GET "/pullrequests/$pr/comments?pagelen=100" | _body \
      | jq -r --arg m "$MARKER" '.values[]? | select((.content.raw // "")|contains($m)) | .id')"
    for id in $ids; do
      _bb_api DELETE "/pullrequests/$pr/comments/$id" >/dev/null && n=$((n+1))
    done
  fi
  printf '%s' "$n"
}
