#!/bin/bash
# Proves the relay on this Mac with no Cloudflare account (brief 176): `wrangler dev --local` on a port of its own,
# test secrets in a temporary .dev.vars (deleted on exit), a pretend Stream for the poller (test/fake-stream.mjs,
# Node's built-ins only), and curl with signatures made by openssl. Each run starts from an empty inbox. Exits non-zero
# on any failure.
#
#   relay/stream-inbox/test.sh                               # the relay on 8799, the pretend Stream on 8801
#   STREAM_INBOX_TEST_PORT=8899 relay/stream-inbox/test.sh   # other ports
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${STREAM_INBOX_TEST_PORT:-8799}"
FAKE_PORT=$((PORT + 2))
BASE="http://127.0.0.1:$PORT"
FAKE="http://127.0.0.1:$FAKE_PORT"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/stream-inbox-test.XXXXXX")"
MARK="# made by test.sh; deleted when it ends"
passes=0
failures=0
pids=()
made_wrangler_dir=0
[ -d "$DIR/.wrangler" ] || made_wrangler_dir=1

for tool in wrangler node openssl curl jq lsof; do
  command -v "$tool" >/dev/null || { echo "test.sh needs $tool." >&2; exit 2; }
done
if [ -f "$DIR/.dev.vars" ] && ! head -1 "$DIR/.dev.vars" | grep -qF "$MARK"; then
  echo "relay/stream-inbox/.dev.vars exists and isn't test.sh's: move it aside first." >&2
  exit 2
fi
for port in "$PORT" $((PORT + 1)) "$FAKE_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $port is in use: set STREAM_INBOX_TEST_PORT to another." >&2
    exit 2
  fi
done

cleanup() {
  for pid in ${pids[@]+"${pids[@]}"}; do kill "$pid" 2>/dev/null; done
  # workerd, wrangler's child, on this run's ports only (they were free when it began).
  for port in "$PORT" $((PORT + 1)) "$FAKE_PORT"; do
    lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null
  done
  wait 2>/dev/null
  if [ -f "$DIR/.dev.vars" ] && head -1 "$DIR/.dev.vars" | grep -qF "$MARK"; then rm -f "$DIR/.dev.vars"; fi
  [ "$made_wrangler_dir" = 1 ] && rm -rf "$DIR/.wrangler"
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

SECRET="swh_test_$(openssl rand -hex 16)"
KEY="$(openssl rand -hex 32)"
printf '%s\nSTREAM_SECRET=%s\nINBOX_KEY=%s\nSTREAM_MCP_URL=%s\n' "$MARK" "$SECRET" "$KEY" "$FAKE/mcp" > "$DIR/.dev.vars"

node "$DIR/test/fake-stream.mjs" "$FAKE_PORT" > "$WORK/fake.log" 2>&1 &
pids+=($!)
(cd "$DIR" && WRANGLER_SEND_METRICS=false exec wrangler dev --local --ip 127.0.0.1 --port "$PORT" \
  --inspector-port $((PORT + 1)) --persist-to "$WORK/state" --test-scheduled --show-interactive-dev-session=false) \
  > "$WORK/wrangler.log" 2>&1 &
pids+=($!)

ready=0
for _ in $(seq 1 120); do
  if curl -fsS "$BASE/" >/dev/null 2>&1 && curl -fsS "$FAKE/__fake/log" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 0.5
done
if [ "$ready" != 1 ]; then
  echo "The relay didn't start. wrangler said:" >&2
  tail -30 "$WORK/wrangler.log" >&2
  exit 1
fi

# MARK: helpers

pass() { passes=$((passes + 1)); echo "  ✔ $1"; }
fail() { failures=$((failures + 1)); echo "  ✘ $1"; [ -n "${2:-}" ] && echo "      $2"; }

# req METHOD PATH [curl arguments…]: sets STATUS and BODY.
req() {
  local method="$1" path="$2"
  shift 2
  STATUS=$(curl -sS -o "$WORK/body" -w '%{http_code}' -X "$method" "$@" "$BASE$path")
  BODY=$(cat "$WORK/body")
}
keyed() {
  local method="$1" path="$2"
  shift 2
  req "$method" "$path" -H "Authorization: Bearer $KEY" "$@"
}
# expect NAME STATUS [JQ-FILTER EXPECTED]
expect() {
  local name="$1" want="$2" got
  if [ "$STATUS" != "$want" ]; then fail "$name" "HTTP $STATUS, wanted $want: $BODY"; return; fi
  if [ $# -ge 4 ]; then
    got=$(printf '%s' "$BODY" | jq -c "$3" 2>/dev/null)
    if [ "$got" != "$4" ]; then fail "$name" "$3 is $got, wanted $4"; return; fi
  fi
  pass "$name"
}
# check NAME JSON JQ-FILTER EXPECTED
check() {
  local got
  got=$(printf '%s' "$2" | jq -c "$3" 2>/dev/null)
  if [ "$got" = "$4" ]; then pass "$1"; else fail "$1" "$3 is $got, wanted $4"; fi
}
# file NAME CONTENT: writes a body exactly as given and prints its path.
file() { printf '%s' "$2" > "$WORK/$1"; echo "$WORK/$1"; }
# sign FILE [T]: the X-Stream-Signature header for FILE, as Stream makes it.
sign() {
  local t="${2:-$(date +%s)}" mac
  mac=$({ printf '%s.' "$t"; cat "$1"; } | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $NF}')
  printf 't=%s,v1=%s' "$t" "$mac"
}
# webhook FILE [HEADER | none]
webhook() {
  local header="${2:-$(sign "$1")}"
  if [ "$header" = none ]; then
    req POST /stream -H 'Content-Type: application/json' --data-binary "@$1"
  else
    req POST /stream -H 'Content-Type: application/json' -H "X-Stream-Signature: $header" --data-binary "@$1"
  fi
}
fake() { curl -sS -X POST "$FAKE/__fake/$1" --data-binary "${2:-}" >/dev/null; }
poll() { curl -sS "$BASE/__scheduled?cron=*+*+*+*+*" >/dev/null; }
fakelog() { curl -sS "$FAKE/__fake/log"; }
iso() { date -u -v"$1" +%Y-%m-%dT%H:%M:%SZ; }

# MARK: the relay

echo "▸ the relay"
req GET /
expect "GET / answers" 200 '.ok' 'true'
req GET /nowhere
expect "anything else: 404" 404
req POST /inbox/claim -d '{"device":"mac-test"}'
expect "no key: 401" 401
req POST /inbox/claim -H "Authorization: Bearer $(openssl rand -hex 32)" -d '{"device":"mac-test"}'
expect "a wrong key: 401" 401

echo "▸ Stream's webhook"
one=$(file one.json '{"text":"Call the dentist tomorrow at 9am p2.","interaction_id":"int-1","kind":"capture"}')
two=$(file two.json '{"text":"Buy milk","interaction_id":"int-2"}')
webhook "$one"
expect "signed: 202 accepted" 202 '.status' '"accepted"'
webhook "$one"
expect "the same id again: 200 duplicate" 200 '.status' '"duplicate"'
webhook "$two" "t=$(date +%s),v1=$(openssl rand -hex 32)"
expect "a bad signature: 401" 401
webhook "$two" "$(sign "$two" $(($(date +%s) - 400)))"
expect "an old t: 401" 401
webhook "$two" "$(sign "$two" $(($(date +%s) + 400)))"
expect "a t from the future: 401" 401
webhook "$two" none
expect "no header: 401" 401
signature=$(sign "$two")
webhook "$two" "v1=${signature#*,v1=},${signature%%,v1=*}"
expect "t and v1 in either order: 202" 202 '.status' '"accepted"'
big="$WORK/big.json"
{ printf '{"interaction_id":"big","text":"'; head -c 17000 /dev/zero | tr '\0' 'a'; printf '"}'; } > "$big"
webhook "$big"
expect "over 16 KB: 413" 413
webhook "$(file bad.json 'not json')"
expect "signed but not JSON: 400" 400
webhook "$(file number.json '{"text":5,"interaction_id":"int-3"}')"
expect "text not a string: 400" 400
webhook "$(file noid.json '{"text":"Buy eggs"}')"
expect "no interaction_id: 400" 400
# Built in two steps: bash 3.2 mangles a quoted string with $(…) inside it inside "$(…)".
long_body="{\"text\":\"Buy eggs\",\"interaction_id\":\"$(head -c 257 /dev/zero | tr '\0' 'i')\"}"
webhook "$(file longid.json "$long_body")"
expect "an interaction_id over 256: 400" 400
webhook "$(file empty.json '{"text":"   ","interaction_id":"int-4"}')"
expect "empty text: 204, nothing kept" 204

echo "▸ the inbox"
keyed GET /inbox/status
expect "status: two waiting" 200 '.pending' '2'
check "status: the last capture's top-level keys" "$BODY" '.lastFields' '["text","interaction_id"]'
check "status: the webhook's last body" "$BODY" '.webhook.lastResult' '"empty"'
keyed POST /inbox/claim -d '{"device":"mac-test"}'
expect "claim: the captures, oldest first" 200 '[.items[].id]' '["int-1","int-2"]'
check "claim: the words as Stream sent them" "$BODY" '.items[0].text' '"Call the dentist tomorrow at 9am p2."'
keyed POST /inbox/claim -d '{"device":"iphone-test"}'
expect "a second device's claim: nothing" 200 '.items | length' '0'
keyed POST /inbox/claim -d '{"device":"mac-test"}'
expect "the same device again: its own claim once more" 200 '.items | length' '2'
keyed POST /inbox/ack -d '{"ids":["int-1","int-2","int-1","never-seen"]}'
expect "ack: the two handled" 200 '.acked' '2'
keyed GET /inbox/status
expect "acked: gone from status" 200 '.pending' '0'
webhook "$one"
expect "a redelivery after the ack: 200 duplicate" 200 '.status' '"duplicate"'
keyed POST /inbox/claim -d '{}'
expect "a claim names its device: 400" 400
keyed POST /inbox/test
expect "test: a capture as if Stream sent it" 202 '.status' '"accepted"'
test_id=$(printf '%s' "$BODY" | jq -r .id)
keyed POST /inbox/claim -d '{"device":"iphone-test"}'
expect "the test capture is claimed" 200 '[.items[] | {id, text}]' "[{\"id\":\"$test_id\",\"text\":\"Test capture from your Stream ring\"}]"
keyed POST /inbox/ack -d "{\"ids\":[\"$test_id\"]}"
expect "the test capture acked" 200 '.acked' '1'

# MARK: the poller

echo "▸ Stream's MCP, asked every minute"
keyed GET /inbox/status
expect "not connected yet" 200 '.stream.connected' 'false'
fake interactions '[{"id":"old-2","text":"An old note"},{"id":"old-1","text":"An older note"}]'
keyed POST /stream/connect-link
expect "a one-time connect link" 200
link=$(printf '%s' "$BODY" | jq -r .url)
case "$link" in "$BASE/stream/connect?c="*) pass "the link is the relay's own" ;; *) fail "the link is the relay's own" "$link" ;; esac
case "$link" in *"$KEY"*) fail "the link carries no key" ;; *) pass "the link carries no key" ;; esac
to_sign_in=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' "$link")
authorize="${to_sign_in#302 }"
case "$to_sign_in" in "302 $FAKE/auth/authorize?"*) pass "opened: on to Stream's sign-in" ;; *) fail "opened: on to Stream's sign-in" "$to_sign_in" ;; esac
case "$authorize" in *code_challenge_method=S256*) pass "PKCE S256" ;; *) fail "PKCE S256" "$authorize" ;; esac
case "$authorize" in *"resource=http%3A%2F%2F127.0.0.1%3A$FAKE_PORT%2Fmcp"*) pass "the resource parameter" ;; *) fail "the resource parameter" "$authorize" ;; esac
req GET "${link#"$BASE"}"
expect "the link works once" 400
callback=$(curl -sS -o /dev/null -w '%{redirect_url}' "$authorize")
req GET "${callback#"$BASE"}"
if [ "$STATUS" = 200 ] && printf '%s' "$BODY" | grep -q "Stream is connected."; then pass "back from the sign-in: Stream is connected"
else fail "back from the sign-in: Stream is connected" "HTTP $STATUS: $BODY"; fi
req GET "${callback#"$BASE"}"
expect "the sign-in's answer works once" 400
log=$(fakelog)
check "registered once, as HITList inbox" "$log" '.registrations | map(.client_name)' '["HITList inbox"]'
check "registered: its callback" "$log" '.registrations[0].redirect_uris' "[\"$BASE/stream/callback\"]"
check "registered: a public client" "$log" '.registrations[0].token_endpoint_auth_method' '"none"'
check "registered: code and refresh grants" "$log" '.registrations[0].grant_types' '["authorization_code","refresh_token"]'
check "asked for read only" "$log" '.authorizations[0].scope' '"stream"'
check "the code exchanged with PKCE and the resource" "$log" '.grants[0] | [.grant_type, .resource]' "[\"authorization_code\",\"$FAKE/mcp\"]"
keyed GET /inbox/status
expect "connected" 200 '.stream.connected' 'true'
check "the first poll took nothing said before the approval" "$BODY" '.pending' '0'
check "the tool's arguments, from its schema" "$BODY" '.stream.toolArguments' '["limit","days"]'
check "the connection ends 90 days after the approval" "$BODY" \
  '((.stream.expiresAt | sub("\\.[0-9]+Z$"; "Z") | fromdate) - (.stream.approvedAt | sub("\\.[0-9]+Z$"; "Z") | fromdate))' '7776000'
log=$(fakelog)
check "the handshake, then the tool" "$log" '.methods[0:4]' '["initialize","notifications/initialized","tools/list","tools/call"]'
check "asked for 100" "$log" '.arguments[0]' '{"limit":100}'

fake interactions '[{"id":"new-1","text":"Task: water the plants friday"},{"id":"old-2","text":"An old note"},{"id":"old-1","text":"An older note"}]'
poll
keyed GET /inbox/status
expect "a poll adds what is new" 200 '.pending' '1'
check "from Stream's MCP" "$BODY" '.lastSource' '"stream"'
check "the interaction's fields" "$BODY" '.lastFields' '["id","text"]'
poll
keyed GET /inbox/status
expect "the same item again is not added" 200 '.pending' '1'
keyed POST /inbox/claim -d '{"device":"mac-test"}'
expect "claimed from the poller" 200 '[.items[] | {id, text}]' '[{"id":"new-1","text":"Task: water the plants friday"}]'
keyed POST /inbox/ack -d '{"ids":["new-1"]}'
expect "acked" 200 '.acked' '1'

webhook "$(file nine.json '{"text":"Pick up the dry cleaning","interaction_id":"int-9"}')"
expect "a webhook capture" 202
fake interactions '[{"id":"int-9","text":"Pick up the dry cleaning"},{"id":"twin-9","text":"pick up the  dry cleaning"},{"id":"new-1","text":"Task: water the plants friday"}]'
poll
keyed GET /inbox/status
expect "both sources never give one capture twice" 200 '.pending' '1'
keyed POST /inbox/ack -d '{"ids":["int-9"]}'
expect "acked" 200 '.acked' '1'

fake expire
fake interactions '[{"id":"new-2","text":"Book the car service"},{"id":"int-9","text":"Pick up the dry cleaning"}]'
poll
keyed GET /inbox/status
expect "a 401: the token refreshed and the poll goes on" 200 '.pending' '1'
check "no error" "$BODY" '.stream.lastError' 'null'
check "refreshed with the refresh token" "$(fakelog)" '[.grants[].grant_type] | index("refresh_token") != null' 'true'
keyed POST /inbox/ack -d '{"ids":["new-2"]}'

fake refuse-refresh
fake expire
poll
keyed GET /inbox/status
expect "a refused refresh: disconnected" 200 '.stream.connected' 'false'
check "said so in status" "$BODY" '.stream.lastError | test("ended")' 'true'
calls=$(fakelog | jq '.methods | length')
poll
check "polling stops until reconnected" "$(fakelog)" '.methods | length' "$calls"

fake allow-refresh
fake shape structured
fake interactions "[{\"interaction_id\":\"t-old\",\"text\":\"Said before the approval\",\"created_at\":\"$(iso -1H)\"}]"
keyed POST /stream/connect-link
link=$(printf '%s' "$BODY" | jq -r .url)
authorize=$(curl -sS -o /dev/null -w '%{redirect_url}' "$link")
callback=$(curl -sS -o /dev/null -w '%{redirect_url}' "$authorize")
req GET "${callback#"$BASE"}"
expect "reconnected" 200
keyed GET /inbox/status
expect "connected again" 200 '.stream.connected' 'true'
check "with times: nothing older than the approval" "$BODY" '.pending' '0'
fake interactions "[{\"interaction_id\":\"t-new\",\"text\":\"Said after\",\"created_at\":\"$(iso +5S)\"},{\"interaction_id\":\"t-old\",\"text\":\"Said before the approval\",\"created_at\":\"$(iso -1H)\"}]"
poll
keyed GET /inbox/status
expect "with times: what is newer is taken (structuredContent)" 200 '.pending' '1'
check "one registration in all" "$(fakelog)" '.registrations | length' '1'

echo
echo "$passes passed, $failures failed"
[ "$failures" = 0 ]
