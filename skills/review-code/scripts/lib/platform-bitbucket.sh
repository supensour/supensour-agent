#!/usr/bin/env bash
# platform-bitbucket.sh — Bitbucket Cloud + Server implementation.
# Uniform interface: bitbucket_fetch_pr/_post_summary/_post_inline/_post_file/
#   _list_prior/_update_comment/_resolve_comment. Reconcile never deletes.
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
      | jq -c '(.values // []) | map({number:.id, url:(.links.self[0].href), title, source:.fromRef.displayId, base:.toRef.displayId})' 2>/dev/null || printf '[]'
  else
    _bb_api GET "/pullrequests?q=source.branch.name=%22$src%22&state=OPEN" | _body \
      | jq -c '(.values // []) | map({number:.id, url:(.links.html.href), title, source:.source.branch.name, base:.destination.branch.name})' 2>/dev/null || printf '[]'
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

# bitbucket_list_prior <pr> → JSON array of our prior comments [{id,aux,kind,fp,h}].
#   Server: kind="server", aux=comment version (required to update/resolve).
#   Cloud:  kind="cloud",  aux="".
bitbucket_list_prior() {
  local pr="$1"
  if _bb_is_server; then
    _bb_api GET "/pull-requests/$pr/activities?limit=100" | _body \
      | jq -c '[ .values[]?.comment | select(.!=null) | select(.text|test("supensour:review-code"))
          | . as $c
          | ( ($c.text|capture("fp=(?<fp>[a-z0-9]+) h=(?<h>[a-z0-9]+)"))? // {fp:"",h:""} ) as $m
          | {id:$c.id, aux:($c.version|tostring), kind:"server", fp:$m.fp, h:$m.h} ]' \
      2>/dev/null || printf '[]'
  else
    _bb_api GET "/pullrequests/$pr/comments?pagelen=100" | _body \
      | jq -c '[ .values[]? | select((.content.raw // "")|test("supensour:review-code"))
          | . as $c
          | ( ($c.content.raw|capture("fp=(?<fp>[a-z0-9]+) h=(?<h>[a-z0-9]+)"))? // {fp:"",h:""} ) as $m
          | {id:$c.id, aux:"", kind:"cloud", fp:$m.fp, h:$m.h} ]' \
      2>/dev/null || printf '[]'
  fi
}

# bitbucket_update_comment <pr> <id> <aux=version> <kind> <body> → edit in place. 0=ok.
bitbucket_update_comment() {
  local pr="$1" id="$2" aux="$3" kind="$4" body="$5" payload code
  if [ "$kind" = server ]; then
    payload="$(jq -n --arg t "$(decorate_body "$body")" --argjson v "${aux:-0}" '{text:$t, version:$v}')"
    code="$(_bb_api PUT "/pull-requests/$pr/comments/$id" -d "$payload" | _code)"
  else
    payload="$(jq -n --arg t "$(decorate_body "$body")" '{content:{raw:$t}}')"
    code="$(_bb_api PUT "/pullrequests/$pr/comments/$id" -d "$payload" | _code)"
  fi
  { [ "$code" = 200 ] || [ "$code" = 201 ]; }
}

# bitbucket_resolve_comment <pr> <id> <aux=version> <kind> → mark resolved. 0=ok.
# Server: PUT state=RESOLVED (+version). Cloud: POST .../resolve. Never deletes.
bitbucket_resolve_comment() {
  local pr="$1" id="$2" aux="$3" kind="$4" payload code
  if [ "$kind" = server ]; then
    payload="$(jq -n --argjson v "${aux:-0}" '{state:"RESOLVED", version:$v}')"
    code="$(_bb_api PUT "/pull-requests/$pr/comments/$id" -d "$payload" | _code)"
  else
    code="$(_bb_api POST "/pullrequests/$pr/comments/$id/resolve" | _code)"
  fi
  { [ "$code" = 200 ] || [ "$code" = 201 ]; }
}
