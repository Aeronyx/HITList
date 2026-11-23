#!/bin/bash
# Sets up the Stream ring's inbox for HITList on your own Cloudflare account (the free plan covers it), from a Mac.
# Run it once; run it again any time to redeploy: it keeps the keys unless you ask for new ones.
#
#   relay/stream-inbox/setup.sh
#
# It deploys the relay, makes HITList's inbox key, then connects Stream: (1) Stream's MCP, free (the relay asks Stream
# every minute), and/or (2) Stream's webhook, which needs Stream's paid plan (Stream sends each capture at once). It
# ends with the inbox link for HITList on your clipboard. The key is kept in this Mac's login keychain too, so a
# second run can print the link again.
set -euo pipefail
cd "$(dirname "$0")"

KEYCHAIN_SERVICE="HITList Stream inbox"

say() { printf '%s\n' "$*"; }
ask() { local answer=""; read -r -p "$1 " answer || true; printf '%s' "$answer"; }
json_field() { # json_field NAME: one string field of the JSON on stdin
  if command -v jq >/dev/null; then jq -r --arg name "$1" '.[$name] // empty'
  else sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; fi
}

command -v wrangler >/dev/null || { say "wrangler isn't installed: npm install -g wrangler, then run this again."; exit 1; }
command -v openssl >/dev/null || { say "openssl is missing."; exit 1; }

# 1. Signed in to Cloudflare?
if wrangler whoami 2>&1 | grep -qi "not authenticated"; then
  say "You aren't signed in to Cloudflare yet. Run:"
  say "  wrangler login"
  say "then run this again."
  exit 1
fi

# 2. Deploy. wrangler keeps its terminal (`script` gives it one), so it can ask you for a workers.dev subdomain the
# first time.
say "Deploying the relay…"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if [ -t 0 ] && [ -t 1 ]; then
  script -q "$log" wrangler deploy
else
  wrangler deploy 2>&1 | tee "$log"
fi
url="$(grep -Eo 'https://[A-Za-z0-9.-]+\.workers\.dev' "$log" | head -1 || true)"
if [ -z "$url" ]; then
  say ""
  say "The relay's address wasn't in wrangler's output. If wrangler asked for a workers.dev subdomain and stopped,"
  say "pick one at dash.cloudflare.com (Workers & Pages), then run this again."
  exit 1
fi
say ""
say "The relay is at $url"

secrets="$(wrangler secret list 2>/dev/null || true)"
has_secret() { printf '%s' "$secrets" | grep -q "\"$1\""; }

# 3. HITList's inbox key: kept unless you ask for a new one (every device then connects again with the new link).
key="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$url" -w 2>/dev/null || true)"
if [ -n "$key" ] && has_secret INBOX_KEY; then
  case "$(ask "Keep the inbox key your devices already use? [Y/n]")" in
    [nN]*) key="" ;;
  esac
fi
if [ -z "$key" ]; then
  key="$(openssl rand -hex 32)"
  printf '%s' "$key" | wrangler secret put INBOX_KEY >/dev/null
  security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$url" -w "$key"
  say "Made a new inbox key."
elif ! has_secret INBOX_KEY; then
  printf '%s' "$key" | wrangler secret put INBOX_KEY >/dev/null
fi

# The relay answers with the new key a moment after it is stored.
relay() { # relay METHOD PATH: one keyed request, tried for up to 30 s
  local reply="" body=()
  [ "$1" = POST ] && body=(-H "Content-Type: application/json" -d '{}')
  for _ in $(seq 1 15); do
    if reply="$(curl -fsS -X "$1" -H "Authorization: Bearer $key" ${body[@]+"${body[@]}"} "$url$2" 2>/dev/null)"; then
      printf '%s' "$reply"
      return 0
    fi
    /bin/sleep 2
  done
  return 1
}

# 4. Where captures come from.
say ""
say "Where should captures come from?"
say "  1  Stream's MCP: free. The relay asks Stream every minute; you sign in to Stream once."
say "  2  Stream's webhook: needs Stream's paid plan (Upstream). Stream sends each capture as it is saved."
say "  3  Both"
say "  4  Keep what is set up"
choice="$(ask "Choose 1, 2, 3 or 4 [1]:")"
choice="${choice:-1}"

if [ "$choice" = 1 ] || [ "$choice" = 3 ]; then
  say ""
  if link_reply="$(relay POST /stream/connect-link)"; then
    connect="$(printf '%s' "$link_reply" | json_field url)"
    say "Opening Stream's sign-in in your browser (the link works once, for 10 minutes):"
    say "  $connect"
    say "Sign in to Stream and allow “HITList inbox” to read what you say to Stream."
    open "$connect" || true
    ask "Press Return here once the page says “Stream is connected.”" >/dev/null
    if status="$(relay GET /inbox/status)" && printf '%s' "$status" | grep -q '"connected":true'; then
      say "Stream is connected: the relay asks it every minute."
    else
      say "The relay isn't connected to Stream yet. Run this again to try once more, or use HITList: Settings → Stream Ring."
    fi
  else
    say "The relay didn't answer with the new key yet. Run this again in a minute."
  fi
fi

if [ "$choice" = 2 ] || [ "$choice" = 3 ]; then
  keep_secret=0
  if has_secret STREAM_SECRET; then
    case "$(ask "Keep the webhook's signing secret Stream already uses? [Y/n]")" in
      [nN]*) ;;
      *) keep_secret=1 ;;
    esac
  fi
  if [ "$keep_secret" = 0 ]; then
    printf '%s' "$url/stream" | pbcopy
    say ""
    say "In the Stream app on your iPhone (the webhook address is on your clipboard; Universal Clipboard pastes it there):"
    say "  1. Stream → Settings → Other Tools → Developer (Webhook)."
    say "  2. Tap “Paste webhook URL”. It must be exactly: $url/stream"
    say "  3. Turn on “Send interactions”, check the address in the alert, and tap Turn On."
    say "  4. Turn on “Sign requests” and copy the secret Stream shows (it starts with swh_)."
    secret=""
    while [ -z "$secret" ]; do
      read -r -s -p "Paste the signing secret here and press Return (it won't show): " secret || true
      printf '\n'
      case "$secret" in
        swh_*) ;;
        "") say "Nothing pasted: copy the secret in Stream, then paste it here." ;;
        *) say "That doesn't start with swh_; it is used as it is." ;;
      esac
    done
    printf '%s' "$secret" | wrangler secret put STREAM_SECRET >/dev/null
    secret=""
    say "The webhook's secret is stored. Say something to your ring to try it."
  fi
fi

# 5. HITList's link.
inbox_link="$url/#$key"
printf '%s' "$inbox_link" | pbcopy
say ""
say "Tip: in Stream, tap the chat bubble in the Stream tab to turn Chat off, so Stream doesn't answer each capture or"
say "take a task for a question."
say ""
say "Your HITList inbox link (on your clipboard now; it holds the key, keep it to yourself):"
say "  $inbox_link"
say "On the Mac: HITList → Settings → Stream Ring → Paste → Connect."
say "On the iPhone: the same; Universal Clipboard pastes the link this Mac copied."
