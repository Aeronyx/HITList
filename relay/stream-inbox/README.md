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

Then in HITList: Settings → Stream Ring → Paste → Connect, on each device. `./setup.sh` again redeploys and keeps the
keys unless you ask for new ones.

`./test.sh` proves the relay on this Mac with no account: `wrangler dev --local`, a pretend Stream
(`test/fake-stream.mjs`), and `curl`.

## Where captures come from

- **Stream's MCP** (free): you sign in to Stream once (read only); a cron trigger asks Stream every minute for what
  was said lately. The first poll after an approval takes nothing said before it. Stream ends the connection 90 days
  after you approve it; HITList offers "Reconnect Stream…" two weeks before.
- **Stream's webhook** (Stream's paid plan): Stream sends each capture as it is saved, signed with a secret this relay
  checks before reading it. Unsigned or badly signed requests are refused.

Both can be on: one capture is never handed over twice.

## Endpoints

Every answer is JSON. The inbox endpoints need `Authorization: Bearer <inbox key>`.

| | |
|---|---|
| `POST /stream` | Stream's webhook: `X-Stream-Signature: t=…,v1=…` (HMAC-SHA256 of `t.body`), ±300 s. 202 kept, 200 duplicate, 204 empty, 400, 401, 413. |
| `POST /inbox/claim` | `{"device":"…"}`: what waits, oldest first, at most 50, held for that device 10 minutes. |
| `POST /inbox/ack` | `{"ids":[…]}`: what a device handled. Its words are deleted. |
| `GET /inbox/status` | What waits, when the last capture came and from where, its top-level fields, each source's state. |
| `POST /inbox/test` | A test capture, as if Stream had sent it. |
| `POST /stream/connect-link` | A one-time link (10 minutes) that opens Stream's sign-in. |
| `GET /stream/connect`, `/stream/callback` | Stream's sign-in, there and back. |
| `GET /` | `{"ok":true}` |

## What it keeps

- A capture's words and Stream's whole body until a device acks it, or 30 days.
- After an ack, its id only, 30 days, to catch a redelivery (and for an hour a one-way hash of its words, so the same
  capture from the other source is matched).
- Stream's sign-in tokens and the time you approved, while connected.
- The top-level field names of the last capture (how we learn what Stream sends), never their values.
- Secrets live in your Cloudflare account (`wrangler secret`): `INBOX_KEY`, and `STREAM_SECRET` for the webhook.
