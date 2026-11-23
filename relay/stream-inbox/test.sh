#!/bin/bash
# Proves the relay on this Mac with no Cloudflare or Apple account (brief 176): `wrangler dev --local` on a port of its
# own, test secrets in a temporary .dev.vars (deleted on exit), a pretend Stream and a pretend Apple push service
# (test/fake-stream.mjs, Node's built-ins only, with a throwaway P-256 key made here by openssl), and curl with
# signatures made by openssl. Each run starts from an empty inbox. Exits non-zero on any failure.
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
APNS_KEY_ID="TESTKEY123"
APNS_TEAM_ID="TESTTEAM01"
# A throwaway push key, shaped like Apple's .p8 (PKCS#8, P-256), and its public half for the pretend Apple.
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/ec.pem" 2>/dev/null
openssl pkcs8 -topk8 -nocrypt -in "$WORK/ec.pem" -out "$WORK/apns.p8"
openssl ec -in "$WORK/ec.pem" -pubout -out "$WORK/apns.pub" 2>/dev/null
APNS_KEY_ONE_LINE="$(awk 'BEGIN { ORS = "\\n" } { print }' "$WORK/apns.p8")"
{
  echo "$MARK"
  echo "STREAM_SECRET=$SECRET"
  echo "INBOX_KEY=$KEY"
  echo "STREAM_MCP_URL=$FAKE/mcp"
  echo "APNS_KEY=\"$APNS_KEY_ONE_LINE\""
  echo "APNS_KEY_ID=$APNS_KEY_ID"
  echo "APNS_TEAM_ID=$APNS_TEAM_ID"
  echo "APNS_HOST=$FAKE/production"
  echo "APNS_SANDBOX_HOST=$FAKE/sandbox"
  echo "RELAY_TEST_MODE=1"
} > "$DIR/.dev.vars"

node "$DIR/test/fake-stream.mjs" "$FAKE_PORT" "$WORK/apns.pub" "$APNS_KEY_ID" "$APNS_TEAM_ID" > "$WORK/fake.log" 2>&1 &
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

# req METHOD PATH [curl arguments…]: sets STATUS, BODY and SECONDS_TAKEN.
req() {
  local method="$1" path="$2" out
  shift 2
  out=$(curl -sS -m 30 -o "$WORK/body" -w '%{http_code} %{time_total}' -X "$method" "$@" "$BASE$path")
  STATUS="${out% *}"
  SECONDS_TAKEN="${out#* }"
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
  if [ "$STATUS" != "$want" ]; then fail "$name" "HTTP $STATUS, wanted $want: ${BODY:0:300}"; return; fi
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
# say ID TEXT: one capture through the webhook. The body is built first: bash 3.2 splits a "{…,…}" written inside "$(…)".
say() {
  local body="{\"text\":\"$2\",\"interaction_id\":\"$1\"}"
  webhook "$(file "say-$1.json" "$body")"
}
fake() { curl -sS -X POST "$FAKE/__fake/$1" --data-binary "${2:-}" >/dev/null; }
mode() { fake mode "$1"; }
poll() { curl -sS -m "${1:-30}" "$BASE/__scheduled?cron=*+*+*+*+*" >/dev/null 2>&1; }
fakelog() { curl -sS "$FAKE/__fake/log"; }
iso() { date -u -v"$1" +%Y-%m-%dT%H:%M:%SZ; }
status() { keyed GET /inbox/status; }
# clock MS: the relay's clock moved on (RELAY_TEST_MODE only).
clock() { keyed POST /__test/clock -d "{\"offsetMs\":$1}"; }
claim() { keyed POST /inbox/claim -d "{\"device\":\"$1\"${2:+,\"push\":$2}}"; }
# connect: a one-time link, followed as a browser would, to the callback's page.
connect() {
  local link authorize callback
  keyed POST /stream/connect-link
  link=$(printf '%s' "$BODY" | jq -r .url)
  authorize=$(curl -sS -o /dev/null -w '%{redirect_url}' "$link")
  callback=$(curl -sS -o /dev/null -w '%{redirect_url}' "$authorize")
  req GET "${callback#"$BASE"}"
}
pushes() { fakelog | jq '.pushes | length'; }
wait_pushes() { # wait_pushes N: up to 5 s for the pretend Apple to have N pushes
  for _ in $(seq 1 25); do [ "$(pushes)" -ge "$1" ] && return 0; /bin/sleep 0.2; done
  return 1
}
token_pushes() { fakelog | jq "[.pushes[] | select(.token == \"$1\")] | length"; }
wait_token() { # wait_token TOKEN N [SECONDS]: up to 5 s (or SECONDS) for N pushes to that token
  for _ in $(seq 1 $((${3:-5} * 5))); do [ "$(token_pushes "$1")" -ge "$2" ] && return 0; /bin/sleep 0.2; done
  return 1
}
# alarm: the inbox's alarm, run now on the test clock (RELAY_TEST_MODE only).
alarm() { keyed POST /__test/alarm; }
ack_claimed() { keyed POST /inbox/ack -d "{\"ids\":$(printf '%s' "$BODY" | jq -c '[.items[].id]')}"; }

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
status
expect "status: two waiting" 200 '.pending' '2'
check "status: the last capture's top-level keys" "$BODY" '.lastFields' '["text","interaction_id"]'
check "status: the webhook's last body" "$BODY" '.webhook.lastResult' '"empty"'
claim mac-test
expect "claim: the captures, oldest first" 200 '[.items[].id]' '["int-1","int-2"]'
check "claim: the words as Stream sent them" "$BODY" '.items[0].text' '"Call the dentist tomorrow at 9am p2."'
check "claim: a webhook capture's time is when it arrived" "$BODY" '.items[0] | .capturedAt == .receivedAt and .capturedAt != null' 'true'
claim iphone-test
expect "a second device's claim: nothing" 200 '.items | length' '0'
claim mac-test
expect "the same device again: its own claim once more" 200 '.items | length' '2'
keyed POST /inbox/ack -d '{"ids":["int-1","int-2","int-1","never-seen"]}'
expect "ack: the two handled" 200 '.acked' '2'
status
expect "acked: gone from status" 200 '.pending' '0'
webhook "$one"
expect "a redelivery after the ack: 200 duplicate" 200 '.status' '"duplicate"'
keyed POST /inbox/claim -d '{}'
expect "a claim names its device: 400" 400
keyed POST /inbox/test
expect "test: a capture as if Stream sent it" 202 '.status' '"accepted"'
test_id=$(printf '%s' "$BODY" | jq -r .id)
claim iphone-test
expect "the test capture is claimed" 200 '[.items[] | {id, text}]' "[{\"id\":\"$test_id\",\"text\":\"Test capture from your Stream ring\"}]"
keyed POST /inbox/ack -d "{\"ids\":[\"$test_id\"]}"
expect "the test capture acked" 200 '.acked' '1'

echo "▸ review 4: a claim holds 30 minutes"
say hold-1 "Book the car service"
claim mac-test
expect "claimed by the Mac" 200 '[.items[].id]' '["hold-1"]'
clock $((11 * 60 * 1000))
expect "the relay's clock moves on (test mode)" 200
claim iphone-test
expect "11 minutes on, the iPhone still gets nothing" 200 '.items | length' '0'
claim mac-test
expect "the Mac re-takes its own claim at any time" 200 '[.items[].id]' '["hold-1"]'
clock $((42 * 60 * 1000))
claim iphone-test
expect "31 minutes after the Mac's last claim, the iPhone gets it" 200 '[.items[].id]' '["hold-1"]'
keyed POST /inbox/ack -d '{"ids":["hold-1"]}'
clock 0

echo "▸ minor: connect links and sign-ins are checked before the inbox"
req GET "/stream/connect?c=short"
if [ "$STATUS" = 400 ] && printf '%s' "$BODY" | grep -q "a link HITList made"; then pass "a malformed link is refused"
else fail "a malformed link is refused" "HTTP $STATUS: ${BODY:0:200}"; fi
req GET "/stream/callback?state=x&code=y"
if [ "$STATUS" = 400 ] && printf '%s' "$BODY" | grep -q "a sign-in HITList started"; then pass "a malformed sign-in is refused"
else fail "a malformed sign-in is refused" "HTTP $STATUS: ${BODY:0:200}"; fi

# MARK: the poller

echo "▸ Stream's MCP, asked every minute"
status
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
else fail "back from the sign-in: Stream is connected" "HTTP $STATUS: ${BODY:0:200}"; fi
req GET "${callback#"$BASE"}"
expect "the sign-in's answer works once" 400
/bin/sleep 1
log=$(fakelog)
check "registered as HITList inbox" "$log" '.registrations | map(.client_name)' '["HITList inbox"]'
check "registered: its callback" "$log" '.registrations[0].redirect_uris' "[\"$BASE/stream/callback\"]"
check "registered: a public client" "$log" '.registrations[0].token_endpoint_auth_method' '"none"'
check "registered: code and refresh grants" "$log" '.registrations[0].grant_types' '["authorization_code","refresh_token"]'
check "asked for read only" "$log" '.authorizations[0].scope' '"stream"'
check "the code exchanged with PKCE and the resource" "$log" '.grants[0] | [.grant_type, .resource]' "[\"authorization_code\",\"$FAKE/mcp\"]"
status
expect "connected" 200 '.stream.connected' 'true'
check "the first poll took nothing said before the approval" "$BODY" '.pending' '0'
check "the tool's arguments, from its schema" "$BODY" '.stream.toolArguments' '["limit","days"]'
check "the connection ends 90 days after the approval" "$BODY" \
  '((.stream.expiresAt | sub("\\.[0-9]+Z$"; "Z") | fromdate) - (.stream.approvedAt | sub("\\.[0-9]+Z$"; "Z") | fromdate))' '7776000'
check "the sign-in can be renewed" "$BODY" '.stream.refreshable' 'true'
log=$(fakelog)
check "the handshake, then the tool" "$log" '.methods[0:4]' '["initialize","notifications/initialized","tools/list","tools/call"]'
check "asked for 100" "$log" '.arguments[0]' '{"limit":100}'

fake interactions '[{"id":"new-1","text":"Task: water the plants friday"},{"id":"old-2","text":"An old note"},{"id":"old-1","text":"An older note"}]'
poll
status
expect "a poll adds what is new" 200 '.pending' '1'
check "from Stream's MCP" "$BODY" '.lastSource' '"stream"'
check "the interaction's fields" "$BODY" '.lastFields' '["id","text"]'
poll
status
expect "the same item again is not added" 200 '.pending' '1'
claim mac-test
expect "claimed from the poller" 200 '[.items[] | {id, text}]' '[{"id":"new-1","text":"Task: water the plants friday"}]'
keyed POST /inbox/ack -d '{"ids":["new-1"]}'
expect "acked" 200 '.acked' '1'

echo "▸ review 1 and 7: Stream's own time travels with a capture; after the first poll every new id is taken"
spoken=$(iso -9H)
fake interactions "[{\"id\":\"t-1\",\"text\":\"Call the dentist tomorrow at 9am\",\"created_at\":\"$spoken\"},{\"id\":\"t-2\",\"text\":\"Said yesterday, polled late\",\"created_at\":\"$(iso -1d)\"}]"
poll
claim mac-test
expect "both new ids taken, even one older than the approval" 200 '[.items[].id] | sort' '["t-1","t-2"]'
check "the capture's time is Stream's" "$BODY" "[.items[] | select(.id == \"t-1\") | .capturedAt | sub(\"\\\\.[0-9]+Z$\"; \"Z\")]" "[\"$spoken\"]"
keyed POST /inbox/ack -d '{"ids":["t-1","t-2"]}'

echo "▸ round 3, 6: a time that can't be the capture's is no time"
# say_with ID FIELDS: a webhook capture with more fields (built in a variable first, for bash 3.2).
say_with() {
  local body="{\"text\":\"Plausible or not\",\"interaction_id\":\"$1\",$2}"
  webhook "$(file "said-$1.json" "$body")"
}
say_with p-12 '"time":12'
say_with p-2019 '"created_at":"2019-06-01T10:00:00Z"'
say_with p-ahead "\"created_at\":\"$(iso +1H)\""
two_hours=$(iso -2H)
say_with p-ok "\"created_at\":\"$two_hours\""
fake interactions '[{"id":"q-12","text":"Polled with a tiny time","timestamp":12}]'
poll
claim mac-test
plain='sub("\\.[0-9]+Z$"; "Z")'
check "a small number isn't 1970: the arrival counts" "$BODY" '[.items[] | select(.id == "p-12") | .capturedAt == .receivedAt]' '[true]'
check "a time before 2020 counts as no time" "$BODY" '[.items[] | select(.id == "p-2019") | .capturedAt == .receivedAt]' '[true]'
check "a time an hour after the arrival counts as no time" "$BODY" '[.items[] | select(.id == "p-ahead") | .capturedAt == .receivedAt]' '[true]'
check "a plausible time is kept" "$BODY" "[.items[] | select(.id == \"p-ok\") | .capturedAt | $plain]" "[\"$two_hours\"]"
check "the poller's tiny time counts as no time too" "$BODY" '[.items[] | select(.id == "q-12") | .capturedAt == .receivedAt]' '[true]'
keyed POST /inbox/ack -d '{"ids":["p-12","p-2019","p-ahead","p-ok","q-12"]}'

echo "▸ review 3: an answer the relay can't read is said, with its shape"
mode '{"prose":true}'
poll
status
check "the trouble is said" "$BODY" '.stream.lastError | test("couldn.t be read")' 'true'
check "the answer's shape, never its words" "$BODY" '.stream.answerShape | {contentTypes, json}' '{"contentTypes":["text"],"json":[false]}'
check "still connected" "$BODY" '.stream.connected' 'true'
mode '{"prose":false}'
poll
status
check "readable again: the trouble goes" "$BODY" '.stream.lastError' 'null'

echo "▸ review 6: the same words from both routes"
say w-a "Buy oat milk"
clock $((5 * 60 * 1000))
fake interactions '[{"id":"m-a","text":"buy  oat milk"}]'
poll
status
expect "said again five minutes later by the other route: both kept" 200 '.pending' '2'
say w-b "Pick up the parcel"
fake interactions '[{"id":"m-b","text":"Pick up the parcel"},{"id":"m-a","text":"buy  oat milk"}]'
poll
status
expect "within three minutes by the other route: one capture" 200 '.pending' '3'
say x-1 "Call Sam"
fake interactions '[{"id":"x-1","text":"Call Sam"},{"id":"m-b","text":"Pick up the parcel"},{"id":"m-a","text":"buy  oat milk"}]'
poll
say y-1 "Pay the rent"
fake interactions '[{"id":"y-2","text":"Pay the rent"},{"id":"x-1","text":"Call Sam"},{"id":"m-b","text":"Pick up the parcel"}]'
poll
status
check "once one id came by both routes, matching words with other ids are two captures" "$BODY" '.pending' '6'
check "the relay knows the routes share ids" "$BODY" '.idsMatch' 'true'
claim mac-test
keyed POST /inbox/ack -d "{\"ids\":$(printf '%s' "$BODY" | jq -c '[.items[].id]')}"
clock 0

echo "▸ review 8: one \"starts with Task\" rule, kept by the relay"
keyed POST /inbox/settings -d '{"onlyStartingWithTask":true}'
expect "the rule is set on the relay" 200 '.settings.onlyStartingWithTask' 'true'
status
check "status says the rule" "$BODY" '.settings.onlyStartingWithTask' 'true'
say r-1 "Remember where I parked"
expect "a capture the rule leaves out: kept nowhere" 200 '.status' '"skipped"'
say r-1 "Remember where I parked"
expect "and it is remembered as seen" 200 '.status' '"duplicate"'
say r-2 "Task, buy milk"
expect "a capture that starts with Task is kept" 202 '.status' '"accepted"'
fake interactions '[{"id":"r-3","text":"Pick up Sam"},{"id":"y-2","text":"Pay the rent"}]'
poll
status
check "the poller follows the rule too" "$BODY" '.pending' '1'
keyed POST /inbox/test
claim mac-test
check "the relay's own test capture counts whatever the rule says" "$BODY" '.items | length' '2'
keyed POST /inbox/ack -d "{\"ids\":$(printf '%s' "$BODY" | jq -c '[.items[].id]')}"
keyed POST /inbox/settings -d '{"onlyStartingWithTask":false}'
expect "the rule is turned off" 200 '.settings.onlyStartingWithTask' 'false'
keyed POST /inbox/settings -d '{"onlyStartingWithTask":"yes"}'
expect "a rule that isn't true or false: 400" 400

echo "▸ review 11: a server that differs"
mode '{"clientSecret":true,"noRefreshToken":true}'
connect
if [ "$STATUS" = 200 ]; then pass "a registration with a client secret signs in"; else fail "a registration with a client secret signs in" "HTTP $STATUS: ${BODY:0:200}"; fi
log=$(fakelog)
check "registered again on this connect" "$log" '.registrations | length' '2'
check "the secret went with the code" "$log" '[.grants[] | select(.grant_type == "authorization_code")] | last | .secret' 'true'
status
check "a sign-in with no refresh token is flagged" "$BODY" '.stream.refreshable' 'false'
mode '{"clientSecret":false,"noRefreshToken":false,"mcpDelayMs":4000}'
keyed POST /stream/connect-link
link=$(printf '%s' "$BODY" | jq -r .url)
authorize=$(curl -sS -o /dev/null -w '%{redirect_url}' "$link")
callback=$(curl -sS -o /dev/null -w '%{redirect_url}' "$authorize")
req GET "${callback#"$BASE"}"
if [ "$STATUS" = 200 ] && [ "$(echo "$SECONDS_TAKEN < 2" | bc)" = 1 ]; then pass "the callback page answers at once (${SECONDS_TAKEN}s), the first poll goes on behind it"
else fail "the callback page answers at once" "HTTP $STATUS in ${SECONDS_TAKEN}s"; fi
mode '{"mcpDelayMs":0}'
/bin/sleep 9
mode '{"sse":true}'
fake interactions '[{"id":"sse-1","text":"Read over an event stream"}]'
start=$(date +%s)
poll 25
took=$(($(date +%s) - start))
status
if [ "$took" -lt 5 ]; then pass "an event stream that stays open: read to its answer and no further (${took}s)"; else fail "an event stream that stays open" "the poll took ${took}s"; fi
check "the event's interaction was taken" "$BODY" '.pending' '1'
mode '{"sse":false}'
claim mac-test
keyed POST /inbox/ack -d '{"ids":["sse-1"]}'

echo "▸ review 10: a poll still out when Stream is reconnected"
grant_before=$(fakelog | jq '.grantCount')
fake expire
mode "{\"refreshDelayMs\":3000,\"refuseRefreshGrant\":$grant_before}"
poll 20 &
slow=$!
/bin/sleep 0.5
connect
expect "reconnected while the old poll waits" 200
wait "$slow"
mode '{"refreshDelayMs":0,"refuseRefreshGrant":null}'
fake interactions '[{"id":"after-race","text":"Said after the reconnect"}]'
poll
status
check "the new sign-in survived the old poll" "$BODY" '.stream | {connected, lastError}' '{"connected":true,"lastError":null}'
check "the newest grant is the one in use" "$(fakelog)" '(.accessGrants | last) == .grantCount' 'true'
claim mac-test
keyed POST /inbox/ack -d '{"ids":["after-race"]}'

# MARK: wake-ups

echo "▸ wake-ups: an Apple background push when a capture arrives (a Mac's token: woken at once)"
MAC="aa$(openssl rand -hex 31)"
STALE="bb$(openssl rand -hex 31)"
WRONG="cc$(openssl rand -hex 31)"
mac_push="{\"token\":\"$MAC\",\"environment\":\"development\",\"platform\":\"macOS\"}"
status
check "status: pushes configured" "$BODY" '.push.configured' 'true'
claim mac-test "$mac_push"
expect "a claim registers the device's push token" 200 '.push | {configured, registered}' '{"configured":true,"registered":true}'
say push-1 "Water the plants"
if wait_token "$MAC" 1; then pass "a capture wakes the device"; else fail "a capture wakes the device" "$(fakelog | jq -c .pushes)"; fi
check "headers, payload and the provider token verify" "$(fakelog)" "[.pushes[] | select(.token == \"$MAC\")][0] | {token, problems}" "{\"token\":\"$MAC\",\"problems\":[]}"
say push-2 "Call the bank"
/bin/sleep 1
check "a second capture within 30 s before the device claims: no second push" "$(token_pushes "$MAC")" '.' '1'
claim mac-test "$mac_push"
say push-3 "Book a table"
if wait_token "$MAC" 2; then pass "after the device claimed, the next capture wakes it again"; else fail "after the device claimed, the next capture wakes it again"; fi
claim mac-test "$mac_push"
mode '{"apnsDelayMs":3000}'
say push-5 "A webhook while Apple is slow"
if [ "$(echo "$SECONDS_TAKEN < 1" | bc)" = 1 ]; then pass "the webhook still answers at once while Apple is slow (${SECONDS_TAKEN}s)"
else fail "the webhook still answers at once while Apple is slow" "${SECONDS_TAKEN}s"; fi
mode '{"apnsDelayMs":0}'
/bin/sleep 4
claim stale-device "{\"token\":\"$STALE\",\"environment\":\"production\",\"platform\":\"macOS\"}"
claim wrong-device "{\"token\":\"$WRONG\",\"environment\":\"production\",\"platform\":\"macOS\"}"
status
check "three devices registered" "$BODY" '.push.devices' '3'
mode "{\"apns\":{\"$STALE\":[410,\"Unregistered\"],\"$WRONG\":[400,\"BadDeviceToken\"]}}"
claim mac-test "$mac_push"
say push-6 "Pay the gas bill"
wait_token "$WRONG" 2
/bin/sleep 1
status
check "410, and BadDeviceToken at both services: those tokens aren't woken again" "$BODY" '.push.devices' '1'
check "the last push was sent" "$BODY" '.push.lastSentAt != null' 'true'
mode '{"apnsExpireOnce":true}'
claim mac-test "$mac_push"
before=$(token_pushes "$MAC")
say push-7 "Buy stamps"
if wait_token "$MAC" $((before + 2)); then pass "an expired provider token is made again and the push sent"; else fail "an expired provider token is made again and the push sent" "$(fakelog | jq -c '.pushes[-2:]')"; fi
check "the retry verified" "$(fakelog)" "[.pushes[] | select(.token == \"$MAC\")] | last | .problems" '[]'
before=$(token_pushes "$MAC")
clock 31000
say push-8 "Renew the passport"
if wait_token "$MAC" $((before + 1)); then pass "31 s on, a device that hasn't claimed is woken again"; else fail "31 s on, a device that hasn't claimed is woken again"; fi
claim mac-test "$mac_push"
ack_claimed
clock 0

echo "▸ round 3, 3: a wake-up counts once Apple has taken it, and its trouble is said"
SANDBOXED="dd$(openssl rand -hex 31)"
NOWHERE="ee$(openssl rand -hex 31)"
mode "{\"apnsTokens\":{\"$SANDBOXED\":\"sandbox\",\"$NOWHERE\":\"nowhere\"}}"
# mac_claim DEVICE TOKEN: a Mac that says "production" (a Release build signed for development says so too).
mac_claim() { claim "$1" "{\"token\":\"$2\",\"environment\":\"production\",\"platform\":\"macOS\"}"; }
mac_claim mac-dev "$SANDBOXED"
check "a new token is registered, not yet proved" "$BODY" '.push | {registered, lastOkAt, lastError}' '{"registered":true,"lastOkAt":null,"lastError":null}'
say r3w-1 "Water the ferns"
wait_token "$SANDBOXED" 2
check "refused as BadDeviceToken at one push service, it is tried at the other" "$(fakelog)" "[.pushes[] | select(.token == \"$SANDBOXED\") | .host]" '["production","sandbox"]'
mac_claim mac-dev "$SANDBOXED"
check "the device's claim says it was woken" "$BODY" '.push | (.lastOkAt != null) and .registered and (.lastError == null)' 'true'
ack_claimed
say r3w-2 "Water the palms"
wait_token "$SANDBOXED" 3
/bin/sleep 0.5
check "the service that took it is remembered" "$(fakelog)" "[.pushes[] | select(.token == \"$SANDBOXED\") | .host] | .[2:]" '["sandbox"]'
status
check "status: each device's own state" "$BODY" '[.push.byDevice[] | select(.device == "mac-dev") | (.lastOkAt != null) and (.lastError == null) and (.refused | not)]' '[true]'
mac_claim mac-dead "$NOWHERE"
say r3w-3 "Feed the cat"
wait_token "$NOWHERE" 2
/bin/sleep 0.5
status
check "a token refused at both services is said, with its device" "$BODY" '.push.lastError | test("mac-dead") and test("BadDeviceToken")' 'true'
check "and in that device's own state" "$BODY" '[.push.byDevice[] | select(.device == "mac-dead") | .refused]' '[true]'
mac_claim mac-dead "$NOWHERE"
check "its claim says it can't be woken, and why" "$BODY" '.push | {registered, why: (.lastError != null)}' '{"registered":false,"why":true}'
ack_claimed
dead_before=$(token_pushes "$NOWHERE")
say r3w-4 "Feed the dog"
/bin/sleep 1
check "a refused token isn't pushed again" "$(token_pushes "$NOWHERE")" '.' "$dead_before"
keyed POST /__test/push-key -d '{"key":"not a key"}'
expect "test mode: a push key that can't be used" 200
mac_claim mac-dev "$SANDBOXED"
say r3w-5 "Call the vet"
/bin/sleep 1
status
check "a push key that can't be used is said" "$BODY" '.push.lastError | test("push key")' 'true'
check "with the device it was waking" "$BODY" '.push.lastError | test("mac-dev")' 'true'
check "and in that device's own state" "$BODY" '[.push.byDevice[] | select(.device == "mac-dev") | .lastError | test("push key")]' '[true]'
mac_claim mac-dev "$SANDBOXED"
check "and in its claim" "$BODY" '.push.lastError | test("push key")' 'true'
keyed POST /__test/push-key -d '{"key":null}'
sent=$(token_pushes "$SANDBOXED")
say r3w-6 "Book the vet"
wait_token "$SANDBOXED" $((sent + 1))
/bin/sleep 0.5
status
check "a usable key again: its trouble goes" "$BODY" '(.push.lastError // "") | test("push key") | not' 'true'
mac_claim mac-dev "$SANDBOXED"
check "and the device is woken again" "$BODY" '.push.lastError' 'null'
ack_claimed
claim iphone-test
ack_claimed
claim stale-device
ack_claimed

echo "▸ round 3, 7: a Mac is woken at once; an iPhone only for what no device has taken"
PHONE="ff$(openssl rand -hex 31)"
phone_push="{\"token\":\"$PHONE\",\"environment\":\"development\",\"platform\":\"iOS\"}"
mine='[.items[] | select(.id | startswith("s7-")) | .id] | sort'
B=$((10 * 60 * 1000)) # ten minutes on: every Mac claim above is more than two minutes old
clock $B
claim iphone-7 "$phone_push"
ack_claimed
macs=$(token_pushes "$MAC")
say s7-1 "Pick up the dry cleaning"
wait_token "$MAC" $((macs + 1))
check "a Mac is woken at once" "$(token_pushes "$MAC")" '.' "$((macs + 1))"
check "an iPhone isn't, yet" "$(token_pushes "$PHONE")" '.' '0'
clock $((B + 29000)); alarm
/bin/sleep 0.5
check "29 s on: still not" "$(token_pushes "$PHONE")" '.' '0'
clock $((B + 31000)); alarm
wait_token "$PHONE" 1
check "30 s on and no device took it: the iPhone is woken" "$(token_pushes "$PHONE")" '.' '1'
claim iphone-7 "$phone_push"
ack_claimed
say s7-2 "Return the library books"
claim mac-test "$mac_push"
expect "the Mac takes the next one within 30 s" 200 "$mine" '["s7-2"]'
ack_claimed
clock $((B + 62000)); alarm
/bin/sleep 0.5
check "taken by the Mac: the iPhone isn't woken" "$(token_pushes "$PHONE")" '.' '1'
say s7-3 "Buy batteries"
clock $((B + 93000)); alarm
/bin/sleep 0.5
check "a Mac claimed in the last two minutes: 30 s on, the iPhone still waits" "$(token_pushes "$PHONE")" '.' '1'
clock $((B + 138000)); alarm
wait_token "$PHONE" 2
check "75 s on and still no device's: the iPhone is woken" "$(token_pushes "$PHONE")" '.' '2'
claim iphone-7 "$phone_push"
ack_claimed
C=$((B + 400000)) # the Mac's last claim is over two minutes old again
clock $C
say s7-4 "Charge the camera"
clock $((C + 10000))
say s7-5 "Pack the tripod"
clock $((C + 31000)); alarm
wait_token "$PHONE" 3
clock $((C + 41000)); alarm
/bin/sleep 0.5
check "two captures 10 s apart: one wake-up (a device at most every 30 s)" "$(token_pushes "$PHONE")" '.' '3'
claim iphone-7 "$phone_push"
expect "and the iPhone takes both" 200 "$mine" '["s7-4","s7-5"]'
ack_claimed
clock $((C + 300000))
claim iphone-7 "$phone_push"
say s7-6 "Water the window boxes"
start=$(date +%s)
if wait_token "$PHONE" 4 40; then pass "the inbox's own alarm wakes the iPhone ($(($(date +%s) - start)) s on, nothing run by hand)"
else fail "the inbox's own alarm wakes the iPhone" "no push in 40 s"; fi
claim iphone-7 "$phone_push"
ack_claimed
clock 0

echo "▸ review 2: a session the server forgets doesn't spin the relay"
mode '{"sessionIds":true,"session404":true}'
fake expire
connect
calls=$(fakelog | jq '.methods | length')
start=$(date +%s)
poll 25
took=$(($(date +%s) - start))
status
check "the trouble is said" "$BODY" '.stream.lastError | test("session")' 'true'
after=$(fakelog | jq '.methods | length')
refused=$(fakelog | jq '.session404s')
if [ "$refused" -le 10 ] && [ "$took" -lt 20 ]; then pass "a few calls and done ($((after - calls)) calls, $refused refused in all, ${took}s)"
else fail "a few calls and done" "$refused requests refused for their session; this poll ${took}s"; fi
req GET /
expect "the relay still answers" 200 '.ok' 'true'

echo
echo "$passes passed, $failures failed"
[ "$failures" = 0 ]
