# Stream ring inbox

A small relay of your own that lets tasks said to a Sandbar **Stream** ring land in HITList with the phone in your
pocket. The ring's audio goes only to the Stream app; nothing outside HITList can write into its iCloud. So Stream's
captures come here, wait, and one of your devices running HITList takes them, makes each a task with the quick-add
parser (dates, `p1`–`p4`, `#Group`), and says it has them. iCloud then carries the task to your other devices.

```
ring → Stream app → this relay (Cloudflare Worker, your account, free) ← HITList (Mac, iPhone) → iCloud
```

It is one Worker with one SQLite Durable Object, plain JavaScript, no packages, no build step.

## Setting it up

From this folder, on a Mac with `wrangler` (`npm install -g wrangler`):

```sh
wrangler login        # once: signs in to your Cloudflare account
./setup.sh            # deploys, makes the inbox key, connects Stream, copies HITList's inbox link
```

Then in HITList: Settings → Stream Ring → Paste → Connect, on each device. Until a device is connected, Stream Ring is
listed only where the troubleshooting rows show (Settings → About, tap Version seven times). `./setup.sh` again
redeploys and keeps the keys unless you ask for new ones.

`./test.sh` proves the relay on this Mac with no account: `wrangler dev --local`, a pretend Stream
(`test/fake-stream.mjs`), and `curl`.

## Where captures come from

- **Stream's MCP** (free): you sign in to Stream once (read only); a cron trigger asks Stream every minute for what
  was said lately. The first poll after an approval takes nothing said before it. Stream ends the connection 90 days
  after you approve it; HITList offers "Reconnect Stream…" two weeks before.
- **Stream's webhook** (Stream's paid plan): Stream sends each capture as it is saved, signed with a secret this relay
  checks before reading it. Unsigned or badly signed requests are refused.

Both can be on: one capture is never handed over twice. The "Only captures that start with 'Task'" rule lives here,
one for every device: a capture it leaves out is remembered as seen and never handed over.

## Wake-ups

With an Apple push key (`setup.sh` asks for it; optional), each device that gave its push token with a claim is woken
by a background push the moment a capture is kept, so the iPhone takes it with the phone asleep in a pocket. A device
is woken at most once every 30 seconds until it has come for its captures. Apple's retired or refused tokens are
dropped.

## Endpoints

Every answer is JSON. The inbox endpoints need `Authorization: Bearer <inbox key>`.

| | |
|---|---|
| `POST /stream` | Stream's webhook: `X-Stream-Signature: t=…,v1=…` (HMAC-SHA256 of `t.body`), ±300 s. 202 kept, 200 duplicate or skipped by the rule, 204 empty, 400, 401, 413. |
| `POST /inbox/claim` | `{"device":"…","push":{token, environment, platform}}`: what waits, oldest first, at most 50, held for that device 30 minutes (it may take its own again at any time), each with the time it was said. |
| `POST /inbox/ack` | `{"ids":[…]}`: what a device handled. Its words are deleted. |
| `GET /inbox/status` | What waits, when the last capture came and from where, its top-level fields, the rule, each source's state, the wake-ups. |
| `POST /inbox/settings` | `{"onlyStartingWithTask":true}`: the rule, for every device. |
| `POST /inbox/test` | A test capture, as if Stream had sent it. |
| `POST /stream/connect-link` | A one-time link (10 minutes) that opens Stream's sign-in. |
| `GET /stream/connect`, `/stream/callback` | Stream's sign-in, there and back. |
| `GET /` | `{"ok":true}` |

## What it keeps

- A capture's words and Stream's whole body until a device acks it, or 30 days.
- After an ack, its id only, 30 days, to catch a redelivery (and for an hour a one-way hash of its words, so the same
  capture from the other route moments later is matched, until the routes have shown they share ids).
- Stream's sign-in tokens and the time you approved, while connected.
- Each device's push token, its environment and when it last claimed and was woken.
- The top-level field names of the last capture (how we learn what Stream sends), never their values.
- Secrets live in your Cloudflare account (`wrangler secret`): `INBOX_KEY`, `STREAM_SECRET` for the webhook, and
  `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` for the wake-ups.
