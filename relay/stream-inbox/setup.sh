#!/bin/bash
# Sets up the Stream ring's inbox for HITList on your own Cloudflare account (the free plan covers it), from a Mac.
# Run it once; run it again any time to redeploy: it keeps the keys unless you ask for new ones.
#
#   relay/stream-inbox/setup.sh
#
# It deploys the relay, makes HITList's inbox key, then connects Stream: (1) Stream's MCP, free (the relay asks Stream
# every minute), and/or (2) Stream's webhook, which needs Stream's paid plan (Stream sends each capture at once). Then,
# optionally, wake-ups: with an Apple push key the relay wakes HITList on your iPhone the moment a capture arrives. It
# ends with the inbox link for HITList on your clipboard. The key is kept in this Mac's login keychain too, so a second
# run can print the link again. Keys never go on a command line.
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
headers="$(mktemp)" # 0600: the inbox key for curl, never on a command line
trap 'rm -f "$log" "$headers"' EXIT
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

# What the relay already has. If wrangler can't say, nothing goes on: a key made now would replace the one your devices
# use (round 3, finding 5).
if ! secrets="$(wrangler secret list 2>/dev/null)" || ! printf '%s' "$secrets" | grep -q '^[[:space:]]*\['; then
  say ""
  say "Nothing changed: couldn't read the relay's secrets (wrangler secret list failed), so no key was made."
  say "Check that wrangler is signed in to the account the relay is on (wrangler whoami), then run this again."
  exit 1
fi
has_secret() { printf '%s' "$secrets" | grep -q "\"$1\""; }
keep_in_keychain() { # the key into this Mac's login keychain, through security's stdin, never its arguments
  printf 'add-generic-password -U -s "%s" -a "%s" -w "%s"\n' "$KEYCHAIN_SERVICE" "$url" "$1" | security -i >/dev/null
}

# 3. HITList's inbox key: kept unless you ask for a new one (every device then connects again with the new link).
key="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$url" -w 2>/dev/null || true)"
if [ -n "$key" ] && has_secret INBOX_KEY; then
  case "$(ask "Keep the inbox key your devices already use? [Y/n]")" in
    [nN]*) key="" ;;
  esac
elif [ -z "$key" ] && has_secret INBOX_KEY; then
  say ""
  say "Your relay has an inbox key, but this Mac's keychain doesn't (it was made on another Mac, or removed), and"
  say "Cloudflare never gives a key back."
  case "$(ask "Make a new key? Every device then connects again with the new link. [y/N]")" in
    [yY]*) ;;
    *) say "Nothing changed. Run this on the Mac that made the key to print its link, or answer y next time."; exit 0 ;;
  esac
fi
if [ -z "$key" ]; then
  key="$(openssl rand -hex 32)"
  # The keychain first: a key the relay has is then never one this Mac has lost.
  keep_in_keychain "$key"
  printf '%s' "$key" | wrangler secret put INBOX_KEY >/dev/null
  say "Made a new inbox key."
elif ! has_secret INBOX_KEY; then
  printf '%s' "$key" | wrangler secret put INBOX_KEY >/dev/null
fi
printf 'Authorization: Bearer %s\n' "$key" > "$headers"

# The relay answers with the new key a moment after it is stored.
relay() { # relay METHOD PATH: one keyed request, tried for up to 30 s
  local reply="" body=()
  [ "$1" = POST ] && body=(-H "Content-Type: application/json" -d '{}')
  for _ in $(seq 1 15); do
    if reply="$(curl -fsS -X "$1" -H @"$headers" ${body[@]+"${body[@]}"} "$url$2" 2>/dev/null)"; then
      printf '%s' "$reply"
      return 0
    fi
    /bin/sleep 2
  done
  return 1
}

# 4. Where captures come from. Once one is set up (the webhook's secret, or Stream connected), a run again keeps it by
# default and only prints the link.
default=1
if has_secret STREAM_SECRET \
   || curl -fsS -m 10 -H @"$headers" "$url/inbox/status" 2>/dev/null | grep -q '"connected":true'; then
  default=4
fi
say ""
say "Where should captures come from?"
say "  1  Stream's MCP: free. The relay asks Stream every minute; you sign in to Stream once."
say "  2  Stream's webhook: needs Stream's paid plan (Upstream). Stream sends each capture as it is saved."
say "  3  Both (with Upstream: the webhook is instant, and the MCP catches anything the webhook missed)"
say "  4  Keep what is set up, and print HITList's link"
choice="$(ask "Choose 1, 2, 3 or 4 [$default]:")"
choice="${choice:-$default}"

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

# 5. Wake-ups (optional): an Apple push key, so the relay wakes HITList the moment a capture arrives.
say ""
say "Wake HITList when a capture arrives (optional): with an Apple push key, the relay wakes HITList on your iPhone"
say "the moment Stream sends a capture, so the task is there with the phone asleep in your pocket."
wake="$(ask "Set up wake-ups now? [y/N]")"
if has_secret APNS_KEY && [ "${wake:-n}" != n ] && [ "${wake:-n}" != N ]; then
  case "$(ask "The relay already has a push key. Replace it? [y/N]")" in
    [yY]*) ;;
    *) wake="n" ;;
  esac
fi
case "$wake" in
  [yY]*)
    say ""
    say "Make the key in a browser, once (Apple shows the .p8 file one time only):"
    say "  1. developer.apple.com → Account → Certificates, IDs & Profiles → Keys → the + button."
    say "  2. Key Name: HITList relay. Tick “Apple Push Notifications service (APNs)”, then Configure:"
    say "     Environment “Sandbox & Production”, Key Restriction “Team Scoped (All Topics)”, Save."
    say "  3. Continue, then Register, then Download. Note the Key ID on that page (10 characters)."
    p8=""
    while [ -z "$p8" ] || [ ! -f "$p8" ] || ! grep -q "BEGIN PRIVATE KEY" "$p8"; do
      [ -n "$p8" ] && say "That isn't a .p8 key file: drag the downloaded AuthKey_….p8 into this window."
      p8="$(ask "The .p8 file (drag it here, then Return):")"
      p8="$(printf '%s' "$p8" | sed -e 's/[[:space:]]*$//' -e "s/^'//" -e "s/'$//" -e 's/\\ / /g')"
    done
    named="$(basename "$p8" | sed -n 's/^AuthKey_\([A-Z0-9]\{10\}\)\.p8$/\1/p')"
    key_id="$(ask "Key ID${named:+ [$named]}:")"
    key_id="${key_id:-$named}"
    team="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p' ../../project.yml 2>/dev/null | head -1 || true)"
    team_id="$(ask "Team ID${team:+ [$team]}:")"
    team_id="${team_id:-$team}"
    wrangler secret put APNS_KEY < "$p8" >/dev/null
    printf '%s' "$key_id" | wrangler secret put APNS_KEY_ID >/dev/null
    printf '%s' "$team_id" | wrangler secret put APNS_TEAM_ID >/dev/null
    say "Wake-ups are on. Each device gives the relay its push token at its next check: open HITList once on it."
    ;;
esac

# 6. HITList's link.
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
say "Stream Ring isn't in Settings on a device that isn't connected yet? Settings → About, then tap Version seven times"
say "quickly: Stream Ring appears after Claude, and stays listed once that device is connected."
