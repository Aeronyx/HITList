#!/bin/bash
# Proves setup.sh with no Cloudflare account, keychain, clipboard or browser (brief 176, round 3, finding 5): stubs for
# wrangler, security, curl, open and pbcopy go first on PATH, each logging what it was asked. Every argv is logged
# whole, so an inbox key on a command line shows; the key is masked only where it is meant to go (security's stdin, the
# header file curl reads, wrangler's stdin). Exits non-zero on any failure.
#
#   relay/stream-inbox/test/setup-dry.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SETUP="${SETUP_SCRIPT:-$HERE/../setup.sh}" # another copy of setup.sh to prove, e.g. an older one
WORK="$(mktemp -d "${TMPDIR:-/tmp}/setup-dry.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"
export DRY_LOG="$WORK/dry.log" DRY_SECRETS="$WORK/secrets" DRY_KEYCHAIN="$WORK/keychain" DRY_STATUS="$WORK/status.json"
passes=0
failures=0

cat > "$BIN/wrangler" <<'EOF'
#!/bin/bash
echo "wrangler $*" >> "$DRY_LOG"
case "$1" in
  whoami) echo "You are logged in with an OAuth Token (stub)." ;;
  deploy) echo "Uploaded stream-inbox (stub)"; echo "  https://stream-inbox.example.workers.dev"; echo "  schedule: * * * * *" ;;
  secret)
    if [ "$2" = list ]; then
      [ -n "${DRY_SECRETS_FAIL:-}" ] && { echo "✘ [ERROR] A request to the Cloudflare API failed." >&2; exit 1; }
      printf '['; sep=""; while read -r name; do printf '%s{"name": "%s", "type": "secret_text"}' "$sep" "$name"; sep=","; done < <(cat "$DRY_SECRETS" 2>/dev/null); echo ']'
    else
      value="$(cat)"
      echo "  put $3 (${#value} characters$(printf '%s' "$value" | grep -q 'BEGIN PRIVATE KEY' && echo ', a PEM'))" >> "$DRY_LOG"
      echo "$3" >> "$DRY_SECRETS"
    fi ;;
esac
EOF

cat > "$BIN/security" <<'EOF'
#!/bin/bash
echo "security $*" >> "$DRY_LOG"
if [ "$1" = -i ]; then
  read -r command
  echo "  stdin: $(printf '%s' "$command" | sed -E 's/-w "[0-9a-f]{64}"/-w "<key>"/')" >> "$DRY_LOG"
  printf '%s' "$command" | sed -nE 's/.*-w "([0-9a-f]{64})".*/\1/p' > "$DRY_KEYCHAIN"
  exit 0
fi
if [ "$1" = find-generic-password ]; then
  [ -s "$DRY_KEYCHAIN" ] && { cat "$DRY_KEYCHAIN"; exit 0; }
  exit 44
fi
exit 0
EOF

cat > "$BIN/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$DRY_LOG"
for arg in "$@"; do
  case "$arg" in
    @*) grep -q '^Authorization: Bearer [0-9a-f]\{64\}$' "${arg#@}" && echo "  header file holds the key, mode $(stat -f %Lp "${arg#@}")" >> "$DRY_LOG" ;;
  esac
  last="$arg"
done
case "$last" in
  */stream/connect-link) echo '{"url":"https://stream-inbox.example.workers.dev/stream/connect?c=abc","expiresAt":"2026-11-23T18:10:00.000Z"}' ;;
  */inbox/status) cat "$DRY_STATUS" 2>/dev/null || echo '{"pending":0,"stream":{"connected":false}}' ;;
  *) exit 22 ;;
esac
EOF

cat > "$BIN/open" <<'EOF'
#!/bin/bash
echo "open $*" >> "$DRY_LOG"
EOF

cat > "$BIN/pbcopy" <<'EOF'
#!/bin/bash
value="$(cat)"
case "$value" in
  *#*) echo "pbcopy ${value%%#*}#<key>" >> "$DRY_LOG" ;;
  *) echo "pbcopy $value" >> "$DRY_LOG" ;;
esac
EOF
chmod +x "$BIN"/*

pass() { passes=$((passes + 1)); echo "  ✔ $1"; }
fail() { failures=$((failures + 1)); echo "  ✘ $1"; [ -n "${2:-}" ] && echo "      $2"; }
# run INPUT: setup.sh with the stubs, INPUT on its stdin; sets OUT and CODE.
run() {
  : > "$DRY_LOG"
  OUT="$(printf "$1" | PATH="$BIN:$PATH" bash "$SETUP" 2>&1)"
  CODE=$?
}
# The line number in the log of the first line matching a pattern (0 when none).
at() { grep -n -m1 -E "$1" "$DRY_LOG" | cut -d: -f1 | sed 's/^$/0/' | head -1; }
no_key_on_a_command_line() {
  if grep -E '^(wrangler|security|curl|open|pbcopy) ' "$DRY_LOG" | grep -qE '[0-9a-f]{64}'; then
    fail "the inbox key is never on a command line" "$(grep -E '[0-9a-f]{64}' "$DRY_LOG" | head -3)"
  else
    pass "the inbox key is never on a command line"
  fi
}

P8="$WORK/AuthKey_ABCDE12345.p8"
openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl pkcs8 -topk8 -nocrypt > "$P8"

echo "▸ a first setup: both sources, then wake-ups"
rm -f "$DRY_SECRETS" "$DRY_KEYCHAIN" "$DRY_STATUS"
run "3\n\nswh_drysecret\ny\n$P8\n\n\n"
[ "$CODE" = 0 ] && pass "it finishes" || fail "it finishes" "exit $CODE: $(printf '%s' "$OUT" | tail -5)"
no_key_on_a_command_line
keychain=$(at '^security -i')
put=$(at '^wrangler secret put INBOX_KEY')
if [ "$keychain" -gt 0 ] && [ "$put" -gt 0 ] && [ "$keychain" -lt "$put" ]; then pass "a new key is in this Mac's keychain before the relay has it"
else fail "a new key is in this Mac's keychain before the relay has it" "keychain at log line $keychain, secret put at $put"; fi
grep -q 'header file holds the key, mode 600' "$DRY_LOG" && pass "curl reads the key from a file only this user can read" || fail "curl reads the key from a 0600 file"
grep -q 'put APNS_KEY (.*a PEM)' "$DRY_LOG" && grep -q 'put APNS_KEY_ID' "$DRY_LOG" && grep -q 'put APNS_TEAM_ID' "$DRY_LOG" \
  && pass "the push key, its id and the team id are stored" || fail "the push key, its id and the team id are stored"
grep -q 'connect-link' "$DRY_LOG" && grep -q 'put STREAM_SECRET' "$DRY_LOG" \
  && pass "Stream's sign-in and the webhook's secret" || fail "Stream's sign-in and the webhook's secret"

echo "▸ the relay's secrets can't be read (set up from another Mac, so this one's keychain has no key)"
printf 'INBOX_KEY\nSTREAM_SECRET\n' > "$DRY_SECRETS"
rm -f "$DRY_KEYCHAIN" "$DRY_STATUS"
export DRY_SECRETS_FAIL=1
run "y\n3\n\nswh_drysecret\nn\n"
unset DRY_SECRETS_FAIL
[ "$CODE" != 0 ] && pass "it stops" || fail "it stops" "exit $CODE"
printf '%s' "$OUT" | grep -q "Nothing changed: couldn't read the relay's secrets" && pass "and says nothing changed" \
  || fail "and says nothing changed" "$(printf '%s' "$OUT" | tail -3)"
if grep -qE '^wrangler secret put|^security -i' "$DRY_LOG"; then fail "no key is made or stored" "$(grep -E '^wrangler secret put|^security -i' "$DRY_LOG")"
else pass "no key is made or stored"; fi

echo "▸ the relay has a key this Mac's keychain doesn't"
rm -f "$DRY_KEYCHAIN"
run "n\n"
[ "$CODE" = 0 ] && printf '%s' "$OUT" | grep -q "Nothing changed" && pass "it asks, and no changes nothing" \
  || fail "it asks, and no changes nothing" "exit $CODE: $(printf '%s' "$OUT" | tail -3)"
grep -qE '^wrangler secret put|^security -i' "$DRY_LOG" && fail "no key is made" || pass "no key is made"

echo "▸ a second run once a source is set up"
printf 'INBOX_KEY\nSTREAM_SECRET\nAPNS_KEY\nAPNS_KEY_ID\nAPNS_TEAM_ID\n' > "$DRY_SECRETS"
openssl rand -hex 32 | tr -d '\n' > "$DRY_KEYCHAIN"
echo '{"pending":0,"stream":{"connected":true}}' > "$DRY_STATUS"
run "\n\n\n"
[ "$CODE" = 0 ] && pass "it finishes" || fail "it finishes" "exit $CODE: $(printf '%s' "$OUT" | tail -5)"
# (read -p shows its prompt only at a terminal, so the default is proved by what Return does.)
if grep -qE 'connect-link|put STREAM_SECRET|^open ' "$DRY_LOG"; then
  fail "Return takes the default, 4: no sign-in, no new webhook secret" "$(grep -E 'connect-link|put STREAM_SECRET|^open ' "$DRY_LOG")"
else pass "Return takes the default, 4: no sign-in, no new webhook secret"; fi
printf '%s' "$OUT" | grep -q "Your HITList inbox link" && grep -q '^pbcopy https://stream-inbox.example.workers.dev/#<key>' "$DRY_LOG" \
  && pass "it prints the link and puts it on the clipboard" || fail "it prints the link and puts it on the clipboard" "$(grep pbcopy "$DRY_LOG")"
echo '{"pending":0,"stream":{"connected":false}}' > "$DRY_STATUS"
printf 'INBOX_KEY\n' > "$DRY_SECRETS"
run "\n\n\n\n"
grep -q 'connect-link' "$DRY_LOG" && pass "with nothing set up yet, Return still means 1: Stream's sign-in" \
  || fail "with nothing set up yet, Return still means 1: Stream's sign-in"
no_key_on_a_command_line

echo
echo "$passes passed, $failures failed"
[ "$failures" = 0 ]
