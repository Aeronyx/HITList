// The Stream ring's inbox for HITList (brief 176): a Cloudflare Worker with one SQLite Durable Object.
//
// What George says to his Stream ring lands in the Stream app on his iPhone. This relay holds it until one of his
// devices running HITList takes it, makes a task of it and says so. Two sources fill one inbox, deduplicated by
// Stream's interaction id:
//
//   - Stream's webhook (POST /stream; Stream's paid plan): Stream sends each interaction, signed with a secret this
//     relay checks before it reads a byte as JSON.
//   - Stream's MCP server (free): once connected (Stream's sign-in, read scope only), the cron trigger asks it every
//     minute for what was said lately.
//
// HITList claims what waits (POST /inbox/claim), makes tasks, and acks what it handled (POST /inbox/ack): an acked
// capture's words are deleted and only its id is kept, 30 days, to catch a redelivery. Nothing is kept longer. When a
// capture is kept, each device that gave its push token with a claim is woken by an Apple background push (when the
// APNS_* secrets are set), so it takes the capture at once.
//
// Plain JavaScript, no packages, no build step. Nothing here names an account, a subdomain or a secret: those live in
// George's Cloudflare account (`wrangler secret put`).

import { DurableObject } from "cloudflare:workers";

const MAX_BODY = 16 * 1024;
const MAX_KEYED_BODY = 256 * 1024;
const SIGNATURE_WINDOW_S = 300;
const MINUTE_MS = 60_000;
const DAY_MS = 86_400_000;
const KEEP_MS = 30 * DAY_MS;
// A device's claim holds what it took this long: a device that saved a capture and lost its ack has an hour to come
// back and ack it before another device may take the capture too (round 3, finding 4), and is woken again at 10 and
// 40 minutes while its claim is unacked (its check sends the lost ack first).
const CLAIM_HOLD_MS = 60 * MINUTE_MS;
const REWAKE_AFTER_MS = [10 * MINUTE_MS, 40 * MINUTE_MS];
const CLAIM_LIMIT = 50;
const ACK_LIMIT = 500;
const MAX_ID = 256;
const MAX_DEVICE = 128;
const ONCE_MS = 10 * MINUTE_MS;
const CONNECTION_MS = 90 * DAY_MS;
// The same words from the other route, said within this time of each other, are the same capture, until the two
// routes have shown they share ids (then never: matching ids say it). A one-way hash of the words is kept an hour, then
// only the id.
const TWIN_MS = 3 * MINUTE_MS;
const HASH_KEPT_MS = 60 * MINUTE_MS;
const REFRESH_EARLY_MS = 5 * MINUTE_MS;
const OUTBOUND_TIMEOUT_MS = 15_000;
const PUSH_GAP_MS = 30_000;
// Who is woken (round 3, finding 7): a Mac at once; an iPhone or iPad only for a capture no device has claimed 30 s
// on, or 75 s on when a Mac claimed in the last two minutes (it is awake, and takes it). iOS spends one budget of
// background pushes on these and on iCloud's own, and George's sync must not go short.
const PHONE_WAIT_MS = 30_000;
const PHONE_WAIT_MAC_AWAKE_MS = 75_000;
const MAC_AWAKE_MS = 2 * MINUTE_MS;
const PROVIDER_TOKEN_MS = 50 * MINUTE_MS;
const TOKEN_TEXT = /^[A-Za-z0-9_-]{43}$/;
// A capture's own time is believed only from 2020 on and up to five minutes after the relay got it (round 3, 6).
const EARLIEST_SAID_MS = Date.UTC(2020, 0, 1);
const SAID_AHEAD_MS = 5 * MINUTE_MS;

const TEST_TEXT = "Test capture from your Stream ring";
const CLIENT_NAME = "HITList inbox";
const SCOPE = "stream";
const TOOL = "get_recent_interactions";
// The way Stream's answers are read. A new one starts the poller again from its first poll (`take`), so captures
// the old reader couldn't read are never taken late as new ones.
const READER = "2026-11-23.2";
const MCP_PROTOCOL = "2025-06-18";
const DEFAULT_MCP_URL = "https://api.sandbar.com/mcp";
const APNS_TOPIC = "com.trammells.hitlist";
const APNS_BODY = JSON.stringify({ aps: { "content-available": 1 }, hitlist: { inbox: 1 } });

const ENDED = "Stream's sign-in for the relay has ended. Reconnect Stream in HITList: Settings → Stream Ring.";

// MARK: - The Worker

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      console.error("relay error:", error && error.message);
      return json({ error: "The relay had a problem." }, 500);
    }
  },

  // Every minute (wrangler.toml): old captures dropped, and Stream asked for what was said, while connected.
  async scheduled(controller, env) {
    await inbox(env).tick(mcpURL(env));
  },
};

function inbox(env) {
  return env.INBOX.get(env.INBOX.idFromName("inbox"));
}

function mcpURL(env) {
  const configured = (env.STREAM_MCP_URL || "").trim();
  return configured && safeURL(configured) ? configured : DEFAULT_MCP_URL;
}

async function route(request, env) {
  const url = new URL(request.url);
  const name = `${request.method} ${url.pathname}`;
  switch (name) {
    case "GET /":
      return json({ ok: true });
    case "POST /stream":
      return webhook(request, env);
    case "GET /stream/connect":
      return connectPage(url, env);
    case "GET /stream/callback":
      return callbackPage(url, env);
  }
  const keyed = KEYED[name];
  if (!keyed || (url.pathname.startsWith("/__test/") && env.RELAY_TEST_MODE !== "1")) return json({ error: "Not found." }, 404);
  if (!(await hasInboxKey(request, env))) return json({ error: "Unauthorized." }, 401);
  return keyed(request, env, url);
}

/// The endpoints HITList uses, each behind the inbox key.
const KEYED = {
  async "POST /inbox/claim"(request, env) {
    const body = await readJSON(request);
    const device = body && typeof body.device === "string" ? body.device.trim() : "";
    if (!device || device.length > MAX_DEVICE) return json({ error: "Say which device is asking (device)." }, 400);
    return json(await inbox(env).claim(device, isPlainObject(body.push) ? body.push : null));
  },

  async "POST /inbox/ack"(request, env) {
    const body = await readJSON(request);
    const ids = body && Array.isArray(body.ids) ? body.ids : null;
    if (!ids || ids.length > ACK_LIMIT || !ids.every((id) => typeof id === "string" && id && id.length <= MAX_ID)) {
      return json({ error: `Send the ids handled (ids), at most ${ACK_LIMIT}.` }, 400);
    }
    return json(await inbox(env).ack(ids));
  },

  async "GET /inbox/status"(request, env) {
    return json(await inbox(env).status());
  },

  /// The relay's own settings, the same for every device: the "starts with Task" rule.
  async "POST /inbox/settings"(request, env) {
    const body = await readJSON(request);
    if (!body || typeof body.onlyStartingWithTask !== "boolean") {
      return json({ error: "Send onlyStartingWithTask, true or false." }, 400);
    }
    return json(await inbox(env).setSettings({ onlyStartingWithTask: body.onlyStartingWithTask }));
  },

  async "POST /inbox/test"(request, env) {
    const id = `test-${randomHex(8)}`;
    await inbox(env).keepTest(id, TEST_TEXT, await textHash(TEST_TEXT));
    return json({ status: "accepted", id }, 202);
  },

  async "POST /stream/connect-link"(request, env, url) {
    return json(await inbox(env).createConnectLink(url.origin));
  },

  /// test.sh only (RELAY_TEST_MODE=1 in its .dev.vars): moves the inbox's clock, so the half-hour claim and the
  /// three-minute match are proved without waiting.
  async "POST /__test/clock"(request, env) {
    const body = await readJSON(request);
    const offset = body && Number.isFinite(body.offsetMs) ? body.offsetMs : 0;
    return json(await inbox(env).setTestClock(offset));
  },

  /// test.sh only: the inbox's alarm, run now on its clock (the real alarm fires on the real one).
  async "POST /__test/alarm"(request, env) {
    return json(await inbox(env).runTimers());
  },

  /// test.sh only: the Stream connection as a relay made before `READER` left it (no reader noted), so the next poll is
  /// the new reader's first.
  async "POST /__test/forget-reader"(request, env) {
    return json(await inbox(env).forgetReader());
  },

  /// test.sh only: signs with this key instead of APNS_KEY (`{"key": null}` goes back to it), so a key that can't be
  /// used is proved to be said.
  async "POST /__test/push-key"(request, env) {
    const body = await readJSON(request);
    return json(await inbox(env).setTestPushKey(body && typeof body.key === "string" ? body.key : null));
  },
};

// MARK: - Stream's webhook

async function webhook(request, env) {
  const header = request.headers.get("X-Stream-Signature");
  const secret = env.STREAM_SECRET;
  // Signing is required, never optional: with no secret set, nothing verifies.
  if (!header || !secret) return json({ error: "A signature is required." }, 401);
  const raw = await readCapped(request, MAX_BODY);
  if (raw === null) return json({ error: "The body is over 16 KB." }, 413);
  const signature = parseSignature(header);
  const now = Date.now();
  if (!signature || Math.abs(now / 1000 - Number(signature.t)) > SIGNATURE_WINDOW_S
      || !(await signatureVerifies(secret, signature, raw))) {
    return json({ error: "The signature didn't verify." }, 401);
  }

  // Signed by Stream: only now is the body read as JSON.
  let text;
  let body;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(raw);
    body = JSON.parse(text);
  } catch {
    return json({ error: "The body isn't JSON." }, 400);
  }
  if (!isPlainObject(body)) return json({ error: "The body isn't a JSON object." }, 400);
  const fields = Object.keys(body).slice(0, 64);
  const id = interactionID(body.interaction_id);
  const problem = typeof body.text !== "string" ? "text isn't a string"
    : !id ? `interaction_id is missing or over ${MAX_ID} characters` : null;
  const words = problem ? "" : body.text;
  // The interaction's own time, when Stream sends one with its zone (the webhook is sent as the capture is saved).
  const said = parseTime(first(body, TIME_FIELDS, (v) => parseTime(v, now) !== null), now);
  const outcome = await inbox(env).receiveWebhook({
    id, text: words, body: text, fields, problem, hash: problem ? null : await textHash(words), said,
  });
  switch (outcome) {
    case "invalid": return json({ error: `The body's ${problem}.` }, 400);
    case "empty": return new Response(null, { status: 204 });
    case "duplicate": return json({ status: "duplicate" }, 200);
    case "skipped": return json({ status: "skipped" }, 200);
    default: return json({ status: "accepted" }, 202);
  }
}

/// `t=<unix seconds>,v1=<64 hex>`, the parts in either order; more than one v1 is tried in turn.
function parseSignature(header) {
  let t = null;
  const v1 = [];
  for (const part of header.split(",")) {
    const at = part.indexOf("=");
    if (at < 0) continue;
    const name = part.slice(0, at).trim();
    const value = part.slice(at + 1).trim();
    if (name === "t" && /^\d{1,12}$/.test(value)) t = value;
    else if (name === "v1" && /^[0-9a-fA-F]{64}$/.test(value)) v1.push(value.toLowerCase());
  }
  return t && v1.length ? { t, v1 } : null;
}

/// HMAC-SHA256 over `t + "." + the raw body`, keyed with the whole secret (`swh_…`). `crypto.subtle.verify` compares
/// in constant time.
async function signatureVerifies(secret, signature, raw) {
  const key = await crypto.subtle.importKey("raw", utf8(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const message = concat(utf8(`${signature.t}.`), raw);
  for (const hex of signature.v1) {
    if (await crypto.subtle.verify("HMAC", key, hexBytes(hex), message)) return true;
  }
  return false;
}

function interactionID(value) {
  const id = typeof value === "number" && Number.isFinite(value) ? String(value) : value;
  return typeof id === "string" && id.trim() && id.length <= MAX_ID ? id : null;
}

/// A device's platform as its claim named it: a Mac is woken at once, an iPhone or iPad waits (round 3, finding 7).
function isMac(platform) {
  return platform === "macOS";
}

/// Whether a capture's first word is "Task" (any case, with or without the mark after it): HITList's `SpokenTask`.
function startsWithTask(text) {
  const trimmed = String(text || "").trimStart();
  if (trimmed.slice(0, 4).toLowerCase() !== "task") return false;
  const next = trimmed.charAt(4);
  return !next || !/[\p{L}\p{N}'’]/u.test(next);
}

// MARK: - Connecting Stream's MCP

async function connectPage(url, env) {
  const code = url.searchParams.get("c") || "";
  // Checked here, before the inbox is asked anything.
  if (!TOKEN_TEXT.test(code)) {
    return page("Stream wasn't connected", "That isn't a link HITList made. Ask for a new one: HITList → Settings → Stream Ring → Reconnect Stream…, or run setup.sh again.", 400);
  }
  const reply = await inbox(env).beginConnect(code, url.origin, mcpURL(env));
  if (reply.error) return page("Stream wasn't connected", reply.error, 400);
  return new Response(null, {
    status: 302,
    headers: { Location: reply.location, "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
  });
}

async function callbackPage(url, env) {
  const p = url.searchParams;
  const state = p.get("state") || "";
  if (!TOKEN_TEXT.test(state)) {
    return page("Stream wasn't connected", "That isn't a sign-in HITList started. Start again from HITList (Settings → Stream Ring) or setup.sh.", 400);
  }
  const reply = await inbox(env).finishConnect({
    state, code: p.get("code") || "",
    error: p.get("error") || "", errorDescription: p.get("error_description") || "", mcpUrl: mcpURL(env),
  });
  if (reply.error) return page("Stream wasn't connected", reply.error, 400);
  return page("Stream is connected.", "You can close this page.");
}

// MARK: - The inbox

export class StreamInbox extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS captures (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      text TEXT,
      body TEXT,
      text_hash TEXT,
      received_at INTEGER NOT NULL,
      claimed_by TEXT,
      claimed_at INTEGER,
      done_at INTEGER)`);
    // Added after the first deployments: a relay that has run before gains the column in place.
    const columns = this.sql.exec("PRAGMA table_info(captures)").toArray().map((c) => c.name);
    if (!columns.includes("captured_at")) this.sql.exec("ALTER TABLE captures ADD COLUMN captured_at INTEGER");
    this.sql.exec("CREATE INDEX IF NOT EXISTS captures_waiting ON captures (done_at, received_at)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS once (token TEXT PRIMARY KEY, kind TEXT NOT NULL, data TEXT NOT NULL, expires_at INTEGER NOT NULL)");
    this.sql.exec(`CREATE TABLE IF NOT EXISTS devices (
      token TEXT PRIMARY KEY,
      device TEXT NOT NULL,
      environment TEXT NOT NULL,
      platform TEXT,
      registered_at INTEGER NOT NULL,
      last_claim_at INTEGER,
      last_push_at INTEGER)`);
    // Round 3: each device's own wake-ups (the push service that took its token, its last success and trouble, a token
    // Apple refused), added in place on a relay that ran before.
    const deviceColumns = this.sql.exec("PRAGMA table_info(devices)").toArray().map((c) => c.name);
    for (const [column, type] of [["proven_environment", "TEXT"], ["last_ok_at", "INTEGER"], ["last_error", "TEXT"],
      ["last_error_at", "INTEGER"], ["refused_at", "INTEGER"]]) {
      if (!deviceColumns.includes(column)) this.sql.exec(`ALTER TABLE devices ADD COLUMN ${column} ${type}`);
    }
    // Round 3: wake-ups that wait (the inbox's alarm runs them): an iPhone's, for a capture still unclaimed ("phones").
    this.sql.exec(`CREATE TABLE IF NOT EXISTS timers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      due_at INTEGER NOT NULL,
      kind TEXT NOT NULL,
      capture_id TEXT NOT NULL,
      device TEXT,
      claimed_at INTEGER)`);
    this.sql.exec("CREATE INDEX IF NOT EXISTS timers_due ON timers (due_at)");
    this.lastSweep = 0;
    this.polling = null;
    this.rpcID = 1;
    // test.sh's clock is kept, so an inbox made again (an alarm after it went idle) runs on the same one.
    this.testOffset = env.RELAY_TEST_MODE === "1" ? this.getMeta("testOffset", 0) : 0;
    this.testPushKey = null;
  }

  /// The inbox's clock: the real one, moved only by test.sh (`POST /__test/clock`, RELAY_TEST_MODE).
  now() {
    return Date.now() + this.testOffset;
  }

  async setTestClock(offsetMs) {
    if (this.env.RELAY_TEST_MODE === "1") {
      this.testOffset = offsetMs;
      this.setMeta("testOffset", offsetMs);
    }
    await this.armAlarm();
    return { offsetMs: this.testOffset };
  }

  forgetReader() {
    if (this.env.RELAY_TEST_MODE !== "1") return { ok: false };
    const conn = this.getMeta("stream", null);
    if (conn) {
      delete conn.reader;
      this.setMeta("stream", conn);
    }
    return { ok: true };
  }

  setTestPushKey(key) {
    if (this.env.RELAY_TEST_MODE !== "1") return { ok: false };
    this.testPushKey = key;
    this.deleteMeta("apnsJWT");
    return { ok: true };
  }

  // MARK: What waits

  /// A capture from either route. `duplicate` when its id was seen in the last 30 days, or the same words came by the
  /// other route moments ago while the routes haven't shown they share ids; `skipped` when the "starts with Task" rule
  /// leaves it out (it is then kept as seen, never handed over).
  keep({ id, text, body, hash, source, fields, said }) {
    const now = this.now();
    const existing = this.sql.exec("SELECT source FROM captures WHERE id = ? LIMIT 1", id).toArray()[0];
    if (existing) {
      // One id by both routes: they share ids, and matching words with other ids are two captures from now on.
      if (existing.source !== source && existing.source !== "test" && !this.getMeta("idsMatch", false)) {
        this.setMeta("idsMatch", true);
      }
      return "duplicate";
    }
    if (this.settings().onlyStartingWithTask && !startsWithTask(text)) {
      this.markSeen(id, source, now);
      return "skipped";
    }
    // The same words by the other route, said within three minutes of these: by when each was said (Stream's own time
    // for a poll's capture, the arrival for the webhook's, which Stream sends as it saves), so a poll that finds a
    // capture late still knows the webhook brought it (2026-11-23: Stream's MCP sends no id, so this is the only match).
    if (hash && !this.getMeta("idsMatch", false)) {
      const when = Number.isFinite(said) ? said : now;
      const twin = this.sql.exec(
        `SELECT 1 FROM captures WHERE text_hash = ? AND source != ? AND source != 'test'
           AND ABS(COALESCE(captured_at, received_at) - ?) <= ? LIMIT 1`,
        hash, source, when, TWIN_MS).toArray();
      if (twin.length) {
        this.markSeen(id, source, now);
        return "duplicate";
      }
    }
    this.sql.exec(
      "INSERT INTO captures (id, source, text, body, text_hash, received_at, captured_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      id, source, text, body, hash, now, Number.isFinite(said) ? said : now);
    this.setMeta("last", { at: now, source, fields });
    return "accepted";
  }

  /// The relay's own test capture: kept whatever the rule says, and it wakes the devices like any other.
  async keepTest(id, text, hash) {
    const now = this.now();
    this.sql.exec(
      "INSERT INTO captures (id, source, text, body, text_hash, received_at, captured_at) VALUES (?, 'test', ?, ?, ?, ?, ?)",
      id, text, JSON.stringify({ test: true }), hash, now, now);
    await this.capturesKept([id]);
    return { status: "accepted" };
  }

  /// The webhook's body, signed and read: what it carried is noted for the status whatever came of it.
  async receiveWebhook({ id, text, body, fields, problem, hash, said }) {
    const now = this.now();
    const outcome = problem ? "invalid"
      : !text.trim() ? "empty"
      : this.keep({ id, text, body, hash, source: "webhook", fields, said });
    this.setMeta("webhook", { at: now, result: outcome, fields });
    if (outcome === "accepted") await this.capturesKept([id]);
    return outcome;
  }

  has(id) {
    return this.sql.exec("SELECT 1 FROM captures WHERE id = ? LIMIT 1", id).toArray().length > 0;
  }

  /// An id kept with no words: never handed over, a duplicate if it comes again.
  markSeen(id, source, now) {
    this.sql.exec(
      "INSERT OR IGNORE INTO captures (id, source, text, body, received_at, done_at) VALUES (?, ?, NULL, NULL, ?, ?)",
      id, source, now, now);
  }

  /// What waits and isn't held by another device (held an hour from its claim; a device re-takes its own at any time),
  /// oldest first; held for `device` now, which is woken again at 10 and 40 minutes while the claim is unacked. A claim
  /// also brings the device's push token.
  async claim(device, push) {
    const now = this.now();
    this.sweep(now);
    const wakeState = this.registerDevice(device, push, now);
    this.noteMacClaim(device, push, now);
    const rows = this.sql.exec(
      `SELECT id, text, received_at, captured_at FROM captures
       WHERE done_at IS NULL AND text IS NOT NULL
         AND (claimed_at IS NULL OR claimed_at < ? OR claimed_by = ?)
       ORDER BY received_at, id LIMIT ?`,
      now - CLAIM_HOLD_MS, device, CLAIM_LIMIT).toArray();
    const rewakes = this.pushConfigured();
    for (const row of rows) {
      this.sql.exec("UPDATE captures SET claimed_by = ?, claimed_at = ? WHERE id = ?", device, now, row.id);
      this.sql.exec("DELETE FROM timers WHERE kind = 'holder' AND capture_id = ?", row.id);
      for (const after of rewakes ? REWAKE_AFTER_MS : []) {
        this.sql.exec("INSERT INTO timers (due_at, kind, capture_id, device, claimed_at) VALUES (?, 'holder', ?, ?, ?)",
          now + after, row.id, device, now);
      }
    }
    if (rows.length && rewakes) await this.armAlarm();
    const last = this.getMeta("last", null);
    return {
      items: rows.map((row) => ({
        id: row.id, text: row.text, receivedAt: iso(row.received_at), capturedAt: iso(row.captured_at ?? row.received_at),
      })),
      lastReceivedAt: last ? iso(last.at) : null,
      settings: this.settings(),
      push: { configured: this.pushConfigured(), ...wakeState },
    };
  }

  /// The words of what a device handled go; the ids stay 30 days.
  ack(ids) {
    const now = this.now();
    let acked = 0;
    for (const id of new Set(ids)) {
      acked += this.sql.exec(
        "UPDATE captures SET text = NULL, body = NULL, done_at = ? WHERE id = ? AND done_at IS NULL RETURNING id",
        now, id).toArray().length;
      this.sql.exec("DELETE FROM timers WHERE capture_id = ?", id);
    }
    return { acked };
  }

  settings() {
    return { onlyStartingWithTask: false, ...this.getMeta("settings", {}) };
  }

  setSettings(settings) {
    this.setMeta("settings", { ...this.settings(), ...settings });
    return { settings: this.settings() };
  }

  status() {
    const now = this.now();
    this.sweep(now);
    const pending = this.sql.exec(
      "SELECT COUNT(*) AS n FROM captures WHERE done_at IS NULL AND text IS NOT NULL").one().n;
    const last = this.getMeta("last", null);
    const webhook = this.getMeta("webhook", null);
    return {
      pending,
      lastReceivedAt: last ? iso(last.at) : null,
      lastSource: last ? last.source : null,
      lastFields: last ? last.fields || [] : [],
      idsMatch: this.getMeta("idsMatch", false),
      settings: this.settings(),
      webhook: {
        lastReceivedAt: webhook ? iso(webhook.at) : null,
        lastResult: webhook ? webhook.result : null,
        lastFields: webhook ? webhook.fields || [] : [],
      },
      stream: this.streamStatus(),
      push: this.pushStatus(),
    };
  }

  /// Wake-ups: whether the relay has a push key, how many devices it can wake, its last trouble with the device it was
  /// waking (a key that can't be used first, then the newest device's), and each device's own state.
  pushStatus() {
    const push = this.getMeta("push", {});
    const rows = this.sql.exec(
      `SELECT device, platform, environment, proven_environment, last_claim_at, last_push_at, last_ok_at, last_error,
         last_error_at, refused_at FROM devices ORDER BY registered_at`).toArray();
    const newest = rows.filter((row) => row.last_error).sort((a, b) => (b.last_error_at || 0) - (a.last_error_at || 0))[0];
    const keyError = push.keyError ? `${push.keyError.message} (waking ${push.keyError.devices.join(", ")})` : null;
    return {
      configured: this.pushConfigured(),
      devices: rows.filter((row) => row.refused_at === null).length,
      lastSentAt: iso(push.lastSentAt),
      lastError: keyError || (newest ? `${newest.device}: ${newest.last_error}` : null),
      byDevice: rows.map((row) => ({
        device: row.device,
        platform: row.platform,
        service: (row.proven_environment || row.environment) === "production" ? "production" : "sandbox",
        lastClaimAt: iso(row.last_claim_at),
        lastPushAt: iso(row.last_push_at),
        lastOkAt: iso(row.last_ok_at),
        lastError: row.last_error || null,
        refused: row.refused_at !== null,
      })),
    };
  }

  /// Captures and ids older than 30 days go; hashes after an hour; one-time links and sign-ins when they expire.
  sweep(now) {
    if (Math.abs(now - this.lastSweep) < MINUTE_MS) return;
    this.lastSweep = now;
    this.sql.exec(
      "DELETE FROM captures WHERE (done_at IS NOT NULL AND done_at < ?) OR (done_at IS NULL AND received_at < ?)",
      now - KEEP_MS, now - KEEP_MS);
    this.sql.exec("UPDATE captures SET text_hash = NULL WHERE text_hash IS NOT NULL AND received_at < ?", now - HASH_KEPT_MS);
    this.sql.exec("DELETE FROM once WHERE expires_at < ?", Date.now());
  }

  // MARK: Settings kept here

  getMeta(key, fallback) {
    const row = this.sql.exec("SELECT value FROM meta WHERE key = ?", key).toArray()[0];
    return row ? JSON.parse(row.value) : fallback;
  }

  setMeta(key, value) {
    this.sql.exec(
      "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      key, JSON.stringify(value));
  }

  deleteMeta(key) {
    this.sql.exec("DELETE FROM meta WHERE key = ?", key);
  }

  /// A one-time token: ten minutes, gone once read.
  putOnce(kind, data) {
    const token = randomToken(32);
    this.sql.exec("INSERT INTO once (token, kind, data, expires_at) VALUES (?, ?, ?, ?)",
      token, kind, JSON.stringify(data), Date.now() + ONCE_MS);
    return token;
  }

  takeOnce(kind, token) {
    if (!token) return null;
    const row = this.sql.exec("DELETE FROM once WHERE token = ? AND kind = ? RETURNING data, expires_at", token, kind).toArray()[0];
    return row && row.expires_at >= Date.now() ? JSON.parse(row.data) : null;
  }

  // MARK: Waking the devices (Apple background pushes)

  pushConfigured() {
    return Boolean(this.env.APNS_KEY && this.env.APNS_KEY_ID && this.env.APNS_TEAM_ID);
  }

  /// A claim's `push: {token, environment, platform}`: one token per device, the newest (a new one starts over). A
  /// claim without one still says the device came for its captures. The answer is this device's own wake-ups:
  /// `registered` (it can be woken: a token Apple hasn't refused), `lastOkAt` (Apple last took a push for it) and
  /// `lastError` (why the last one didn't go, or why it can't be woken).
  registerDevice(device, push, now) {
    const token = push && typeof push.token === "string" ? push.token.trim().toLowerCase() : "";
    if (/^[0-9a-f]{64,200}$/.test(token)) {
      const environment = push.environment === "production" ? "production" : "development";
      const platform = typeof push.platform === "string" ? push.platform.slice(0, 16) : null;
      this.sql.exec("DELETE FROM devices WHERE device = ? AND token != ?", device, token);
      this.sql.exec(
        `INSERT INTO devices (token, device, environment, platform, registered_at, last_claim_at) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(token) DO UPDATE SET device = excluded.device, environment = excluded.environment,
           platform = excluded.platform, last_claim_at = excluded.last_claim_at`,
        token, device, environment, platform, now, now);
    } else {
      this.sql.exec("UPDATE devices SET last_claim_at = ? WHERE device = ?", now, device);
    }
    const row = this.sql.exec("SELECT last_ok_at, last_error, refused_at FROM devices WHERE device = ? LIMIT 1", device).toArray()[0];
    return {
      registered: Boolean(row && row.refused_at === null),
      lastOkAt: row ? iso(row.last_ok_at) : null,
      lastError: (row && row.last_error) || null,
    };
  }

  /// A Mac came for its captures: it is awake, so an iPhone's wake-up waits longer (finding 7).
  noteMacClaim(device, push, now) {
    const named = push && typeof push.platform === "string" ? push.platform : null;
    const platform = named || (this.sql.exec("SELECT platform FROM devices WHERE device = ? LIMIT 1", device).toArray()[0] || {}).platform;
    if (isMac(platform) || /^mac-/i.test(device)) this.setMeta("lastMacClaimAt", now);
  }

  /// Captures were kept (round 3, finding 7): each Mac is woken now, in the background (`waitUntil`), so Stream's
  /// webhook is answered at once; an iPhone or iPad only by the inbox's alarm, if the capture is still unclaimed 30 s on
  /// (75 s when a Mac claimed in the last two minutes). A device at most every 30 s until it has claimed since.
  async capturesKept(ids) {
    if (!ids.length || !this.pushConfigured()) return;
    const now = this.now();
    const lastMac = this.getMeta("lastMacClaimAt", null);
    const macAwake = lastMac !== null && now - lastMac <= MAC_AWAKE_MS;
    const sending = this.wakeNow(this.dueDevices(now, (device) => isMac(device.platform)), now);
    if (sending && this.ctx.waitUntil) this.ctx.waitUntil(sending);
    const dueAt = now + (macAwake ? PHONE_WAIT_MAC_AWAKE_MS : PHONE_WAIT_MS);
    for (const id of ids) this.sql.exec("INSERT INTO timers (due_at, kind, capture_id) VALUES (?, 'phones', ?)", dueAt, id);
    await this.armAlarm();
  }

  /// Devices that may be pushed now: a token Apple hasn't refused, not pushed in the last 30 s unless it has claimed
  /// since.
  dueDevices(now, accept) {
    return this.sql.exec(
      `SELECT token, device, environment, proven_environment, platform FROM devices
       WHERE refused_at IS NULL
         AND (last_push_at IS NULL OR (last_claim_at IS NOT NULL AND last_claim_at > last_push_at) OR ? - last_push_at >= ?)`,
      now, PUSH_GAP_MS).toArray().filter(accept);
  }

  /// Pushes these devices, marked as pushed now; the sending, or null when there is none.
  wakeNow(devices, now) {
    if (!devices.length) return null;
    for (const device of devices) this.sql.exec("UPDATE devices SET last_push_at = ? WHERE token = ?", now, device.token);
    return this.sendPushes(devices).catch((error) => console.error("push:", error && error.message));
  }

  /// The inbox's alarm: the wake-ups that waited, run when due.
  async alarm() {
    await this.runTimers();
  }

  /// Every waiting wake-up that is due: an iPhone's for a capture no device has claimed since it was kept; a holder's
  /// for a claim of its own still unacked (the same claim: a re-take starts its own two).
  async runTimers() {
    const now = this.now();
    const due = this.sql.exec(
      "SELECT kind, capture_id, device, claimed_at FROM timers WHERE due_at <= ? ORDER BY due_at, id", now).toArray();
    this.sql.exec("DELETE FROM timers WHERE due_at <= ?", now);
    let phones = false;
    const holders = new Set();
    for (const timer of due) {
      const capture = this.sql.exec(
        "SELECT claimed_by, claimed_at, done_at, text FROM captures WHERE id = ? LIMIT 1", timer.capture_id).toArray()[0];
      if (!capture || capture.done_at !== null || capture.text === null) continue;
      if (timer.kind === "phones" && capture.claimed_at === null) phones = true;
      if (timer.kind === "holder" && capture.claimed_by === timer.device && capture.claimed_at === timer.claimed_at) {
        holders.add(timer.device);
      }
    }
    let woken = [];
    if ((phones || holders.size) && this.pushConfigured()) {
      woken = this.dueDevices(now, (device) => (phones && !isMac(device.platform)) || holders.has(device.device));
      const sending = this.wakeNow(woken, now);
      if (sending) await sending;
    }
    await this.armAlarm();
    return { ran: due.length, woken: woken.map((device) => device.device) };
  }

  /// The alarm at the next waiting wake-up, on the real clock (test.sh moves only the inbox's), or none.
  async armAlarm() {
    const next = this.sql.exec("SELECT MIN(due_at) AS at FROM timers").one().at;
    if (next === null || next === undefined) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    await this.ctx.storage.setAlarm(Math.max(Date.now(), next - this.testOffset));
  }

  /// Each device's push, at the service its token was last taken by (else the one its build named). BadDeviceToken
  /// is tried once at the other service, whose answer is remembered for that token: a Release build signed for
  /// development names the wrong one (round 3, finding 3). A key that can't sign is said, with the devices it was for.
  async sendPushes(devices) {
    let providerToken;
    try {
      providerToken = await this.providerToken(false);
    } catch (error) {
      this.noteKeyTrouble(`The relay's Apple push key couldn't be used (${words(error)}). Run setup.sh again with the .p8 file Apple gave you.`, devices);
      return;
    }
    for (const device of devices) {
      const first = device.proven_environment || device.environment;
      let answer = await this.pushOne(device.token, first, providerToken);
      if (answer.status === 403 && answer.reason === "ExpiredProviderToken") {
        try {
          providerToken = await this.providerToken(true);
        } catch (error) {
          this.noteKeyTrouble(`The relay's Apple push key couldn't be used (${words(error)}). Run setup.sh again with the .p8 file Apple gave you.`, [device]);
          continue;
        }
        answer = await this.pushOne(device.token, first, providerToken);
      }
      let used = first;
      if (answer.status === 400 && answer.reason === "BadDeviceToken") {
        const other = first === "production" ? "development" : "production";
        const again = await this.pushOne(device.token, other, providerToken);
        if (again.status === 200) used = other;
        answer = again.status === 400 && again.reason === "BadDeviceToken" ? { ...again, bothServices: true } : again;
      }
      this.notePush(device, answer, used);
    }
  }

  async pushOne(token, environment, providerToken) {
    // APNS_HOST and APNS_SANDBOX_HOST are test.sh's pretend Apple; nothing else sets them.
    const host = environment === "production"
      ? this.env.APNS_HOST || "https://api.push.apple.com"
      : this.env.APNS_SANDBOX_HOST || "https://api.sandbox.push.apple.com";
    const url = `${host}/3/device/${token}`;
    if (!safeURL(url)) return { status: 0, reason: "an address that isn't https" };
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          authorization: `bearer ${providerToken}`, "apns-push-type": "background", "apns-priority": "5",
          "apns-topic": APNS_TOPIC, "content-type": "application/json",
        },
        body: APNS_BODY,
        redirect: "manual",
        signal: AbortSignal.timeout(OUTBOUND_TIMEOUT_MS),
      });
      let reason = null;
      if (response.status !== 200) reason = ((await response.json().catch(() => null)) || {}).reason || null;
      else response.body && response.body.cancel().catch(() => {});
      return { status: response.status, reason };
    } catch (error) {
      return { status: 0, reason: error && error.name === "TimeoutError" ? "no answer in time" : "no connection" };
    }
  }

  /// Apple's answer, kept on the device's own row: a push Apple took (`last_ok_at`, and the service that took it);
  /// a token Apple retired (410) or refused (BadDeviceToken at both services, DeviceTokenNotForTopic), kept as refused
  /// with the reason, so it isn't pushed again and its device hears why until it gives a new one; anything else, said
  /// as that device's trouble. A key Apple refuses is the relay's trouble, said with the device.
  notePush(device, { status, reason, bothServices }, used) {
    const now = this.now();
    const push = this.getMeta("push", {});
    if (status === 200) {
      push.lastSentAt = now;
      push.keyError = null;
      this.sql.exec(
        "UPDATE devices SET last_ok_at = ?, last_error = NULL, last_error_at = NULL, proven_environment = ? WHERE token = ?",
        now, used, device.token);
    } else if (status === 410 || (status === 400 && (bothServices || reason === "DeviceTokenNotForTopic"))) {
      const why = status === 410 ? "Apple says its push token is no longer in use (Unregistered)"
        : reason === "DeviceTokenNotForTopic" ? "Apple says its push token isn't HITList's (DeviceTokenNotForTopic)"
          : "Apple refused its push token at both of its push services (BadDeviceToken)";
      this.sql.exec("UPDATE devices SET refused_at = ?, last_error = ?, last_error_at = ? WHERE token = ?",
        now, `${why}; it isn't woken until HITList on it gives a new one.`, now, device.token);
    } else if (status === 403 && ["InvalidProviderToken", "MissingProviderToken"].includes(reason)) {
      this.noteKeyTrouble(`Apple refused the relay's push key (${reason}): check its Key ID and Team ID, then run setup.sh again.`, [device], push);
    } else {
      const why = status === 0 ? `Apple's push service couldn't be reached (${reason}).`
        : `Apple refused a wake-up push (${status}${reason ? ` ${reason}` : ""}).`;
      this.sql.exec("UPDATE devices SET last_error = ?, last_error_at = ? WHERE token = ?", why, now, device.token);
    }
    this.setMeta("push", push);
  }

  /// The push key couldn't sign, or Apple refused it: said in status with the devices it was waking, and on each.
  noteKeyTrouble(message, devices, push = this.getMeta("push", {})) {
    const now = this.now();
    push.keyError = { message, at: now, devices: [...new Set(devices.map((device) => device.device))] };
    for (const device of devices) {
      this.sql.exec("UPDATE devices SET last_error = ?, last_error_at = ? WHERE token = ?", message, now, device.token);
    }
    this.setMeta("push", push);
  }

  /// The provider token: an ES256 JWT signed with the .p8 key, reused 50 minutes (Apple refuses one older than an
  /// hour, and too many new ones), made again on ExpiredProviderToken.
  async providerToken(force) {
    const now = Date.now();
    const cached = this.getMeta("apnsJWT", null);
    if (!force && cached && now - cached.issuedAt < PROVIDER_TOKEN_MS && cached.keyId === this.env.APNS_KEY_ID
        && cached.teamId === this.env.APNS_TEAM_ID) {
      return cached.token;
    }
    const token = await signProviderToken(this.testPushKey || this.env.APNS_KEY, this.env.APNS_KEY_ID, this.env.APNS_TEAM_ID,
      Math.floor(now / 1000));
    this.setMeta("apnsJWT", { token, issuedAt: now, keyId: this.env.APNS_KEY_ID, teamId: this.env.APNS_TEAM_ID });
    return token;
  }

  // MARK: Connecting Stream (OAuth 2.1 with dynamic client registration and PKCE, as the MCP authorization spec asks)

  /// The link HITList opens: one-time, ten minutes. It carries no key.
  createConnectLink(origin) {
    this.sweep(this.now());
    const code = this.putOnce("connect", { origin });
    return { url: `${origin}/stream/connect?c=${code}`, expiresAt: iso(Date.now() + ONCE_MS) };
  }

  /// The link opened: Stream's sign-in found and this relay registered with it (again, each time: a client the server
  /// forgot or refused is never reused), then the way there.
  async beginConnect(code, origin, mcpUrl) {
    if (!this.takeOnce("connect", code)) {
      return { error: "This link has expired or was already used. Ask HITList for a new one (Settings → Stream Ring → Reconnect Stream…) or run setup.sh again." };
    }
    try {
      const redirectUri = `${origin}/stream/callback`;
      const server = await discover(mcpUrl);
      const client = await register(server, redirectUri);
      const verifier = randomToken(32);
      const state = this.putOnce("state", { verifier, redirectUri, server, client });
      const target = new URL(server.authorizationEndpoint);
      const params = {
        response_type: "code", client_id: client.clientId, redirect_uri: redirectUri, scope: SCOPE, state,
        code_challenge: await pkceChallenge(verifier), code_challenge_method: "S256", resource: server.resource,
      };
      for (const [name, value] of Object.entries(params)) target.searchParams.set(name, value);
      return { location: target.toString() };
    } catch (error) {
      return { error: `Couldn't start Stream's sign-in: ${words(error)}` };
    }
  }

  /// Back from Stream's sign-in: the code exchanged for tokens, kept here with the server and client this sign-in
  /// used. The page answers at once; the first poll runs behind it.
  async finishConnect({ state, code, error, errorDescription, mcpUrl }) {
    const pending = this.takeOnce("state", state);
    if (!pending) return { error: "This sign-in has expired or was already used. Start again from HITList (Settings → Stream Ring) or setup.sh." };
    if (error) return { error: `Stream said: ${errorDescription || error}.` };
    if (!code) return { error: "Stream sent no code back. Start again from HITList or setup.sh." };
    const { server, client } = pending;
    let tokens;
    try {
      tokens = await tokenRequest(server, client, {
        grant_type: "authorization_code", code, redirect_uri: pending.redirectUri, code_verifier: pending.verifier,
        resource: server.resource,
      });
    } catch (failure) {
      return { error: `Stream didn't accept the sign-in: ${words(failure)}` };
    }
    const now = this.now();
    this.setMeta("server", server);
    this.setMeta("client", client);
    this.saveTokens(tokens, null, now, now);
    // Captures said before this approval are never taken. A reconnection while still connected keeps its line, so
    // nothing said in the minute between the two is lost.
    const previous = this.getMeta("stream", null);
    const carries = previous && previous.connected && previous.baselineDone;
    this.setMeta("stream", {
      connected: true, approvedAt: now, since: carries ? previous.since : now, baselineDone: Boolean(carries),
      reader: carries ? previous.reader || null : null, lastListed: null,
      lastPollAt: carries ? previous.lastPollAt : null, lastError: null, protocolVersion: null, sessionId: null,
      toolSchema: null, toolArguments: null, interactionFields: previous ? previous.interactionFields || null : null,
      refreshable: Boolean(tokens.refresh_token), answerShape: null,
    });
    const firstPoll = this.tick(mcpUrl).catch((failure) => console.error("first poll:", failure && failure.message));
    if (this.ctx.waitUntil) this.ctx.waitUntil(firstPoll);
    return { ok: true };
  }

  /// Tokens are kept with the sign-in (`grant`: its approval time) they belong to.
  saveTokens(reply, previous, now, grant) {
    const seconds = Number(reply.expires_in);
    this.setMeta("tokens", {
      access: reply.access_token,
      refresh: reply.refresh_token || (previous ? previous.refresh : null),
      expiresAt: now + (Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : 3600_000),
      grant,
    });
  }

  streamStatus() {
    const conn = this.getMeta("stream", null);
    if (!conn) return { connected: false, approvedAt: null, expiresAt: null, lastPollAt: null, lastError: null };
    return {
      connected: Boolean(conn.connected),
      approvedAt: iso(conn.approvedAt),
      expiresAt: conn.approvedAt ? iso(conn.approvedAt + CONNECTION_MS) : null,
      lastPollAt: iso(conn.lastPollAt),
      lastError: conn.lastError || null,
      refreshable: conn.refreshable === undefined ? null : Boolean(conn.refreshable),
      toolArguments: conn.toolArguments || null,
      interactionFields: conn.interactionFields || null,
      // How many interactions Stream's last answer listed, read or not (null before the first poll of this reader).
      lastListed: Number.isInteger(conn.lastListed) ? conn.lastListed : null,
      answerShape: conn.answerShape || null,
    };
  }

  // MARK: Asking Stream every minute

  async tick(mcpUrl) {
    this.sweep(this.now());
    const conn = this.getMeta("stream", null);
    if (!conn || !conn.connected) return { polled: false };
    // One at a time: a slow poll and the next minute's never overlap.
    if (!this.polling) this.polling = this.poll(mcpUrl).finally(() => { this.polling = null; });
    return this.polling;
  }

  async poll(mcpUrl) {
    const started = this.now();
    const server = this.getMeta("server", null);
    const client = this.getMeta("client", null);
    const conn = this.getMeta("stream", null);
    if (!server || !client || !conn) return { polled: false };
    const grant = conn.approvedAt;
    // Tokens kept before they carried their sign-in belong to the one connected now.
    const kept = this.getMeta("tokens", null);
    if (kept && kept.grant === undefined) this.setMeta("tokens", { ...kept, grant });
    if (server.mcpUrl !== mcpUrl) server.mcpUrl = mcpUrl;
    const session = { protocolVersion: conn.protocolVersion, sessionId: conn.sessionId, toolSchema: conn.toolSchema,
      toolArguments: conn.toolArguments };
    let update;
    let keptIDs = [];
    try {
      const result = await this.callTool(server, client, session, grant);
      const taken = await this.take(result, conn, started);
      keptIDs = taken.kept || [];
      delete taken.kept;
      update = { ...session, ...taken, lastPollAt: started };
    } catch (failure) {
      if (failure instanceof Superseded) return { polled: false };
      if (failure instanceof Ended) {
        // Only this sign-in's tokens go: a reconnection made while Stream answered keeps its own.
        if ((this.getMeta("tokens", null) || {}).grant === grant) this.deleteMeta("tokens");
        update = { connected: false, lastError: ENDED, endedAt: started, protocolVersion: null, sessionId: null };
      } else {
        update = { ...session, lastError: words(failure), lastTriedAt: started };
      }
    }
    // Read again: a sign-in may have finished while Stream answered.
    const latest = this.getMeta("stream", conn);
    if (latest.approvedAt !== grant) return { polled: false };
    if (update.refreshable === undefined && this.getMeta("tokens", null) && !this.getMeta("tokens", null).refresh) {
      update.refreshable = false;
    }
    this.setMeta("stream", { ...latest, ...update });
    await this.capturesKept(keptIDs);
    return { polled: true, added: keptIDs.length };
  }

  /// `get_recent_interactions`, after the handshake when there is none yet. A 401 refreshes the token once; a session
  /// the server forgets is started again once, never more (a server that keeps forgetting is trouble, said in status).
  async callTool(server, client, session, grant) {
    let tokens = await this.freshTokens(server, client, false, grant);
    let refreshed = false;
    let resets = 0;
    for (;;) {
      try {
        if (!session.protocolVersion) await this.handshake(server, tokens, session);
        const reply = await this.rpc(server, tokens, session, "tools/call", {
          name: TOOL, arguments: argumentsFor(session.toolSchema),
        });
        return reply.result;
      } catch (failure) {
        if (failure instanceof Unauthorized && !refreshed) {
          refreshed = true;
          tokens = await this.freshTokens(server, client, true, grant);
          continue;
        }
        if (failure instanceof Unauthorized) throw new Ended();
        if (failure instanceof SessionGone && resets < 1) {
          resets += 1;
          session.protocolVersion = null;
          session.sessionId = null;
          continue;
        }
        if (failure instanceof SessionGone) {
          session.protocolVersion = null;
          session.sessionId = null;
          throw new Trouble("Stream's server keeps losing the relay's session; it is tried again next minute.");
        }
        throw failure;
      }
    }
  }

  /// The access token of this poll's sign-in, refreshed when it ends within five minutes or when asked. A refused
  /// refresh means the connection has ended; a reconnection made meanwhile wins (`Superseded`).
  async freshTokens(server, client, force, grant) {
    const tokens = this.getMeta("tokens", null);
    if (!tokens || !tokens.access) throw new Ended();
    if (tokens.grant !== grant) throw new Superseded();
    if (!force && tokens.expiresAt - this.now() > REFRESH_EARLY_MS) return tokens;
    if (!tokens.refresh) throw new Ended();
    let reply;
    try {
      reply = await tokenRequest(server, client, {
        grant_type: "refresh_token", refresh_token: tokens.refresh, resource: server.resource,
      });
    } catch (failure) {
      if ((this.getMeta("stream", {}) || {}).approvedAt !== grant) throw new Superseded();
      if (failure instanceof Refused) throw new Ended();
      throw failure;
    }
    if ((this.getMeta("stream", {}) || {}).approvedAt !== grant) throw new Superseded();
    this.saveTokens(reply, tokens, this.now(), grant);
    return this.getMeta("tokens", null);
  }

  async handshake(server, tokens, session) {
    const init = await this.rpc(server, tokens, { protocolVersion: null, sessionId: null }, "initialize", {
      protocolVersion: MCP_PROTOCOL, capabilities: {}, clientInfo: { name: CLIENT_NAME, version: "1" },
    });
    session.protocolVersion = (init.result && init.result.protocolVersion) || MCP_PROTOCOL;
    session.sessionId = init.sessionId || null;
    await this.rpc(server, tokens, session, "notifications/initialized", undefined, true);
    let tool = null;
    let cursor;
    for (let page = 0; page < 5 && !tool; page += 1) {
      const list = await this.rpc(server, tokens, session, "tools/list", cursor ? { cursor } : {});
      const tools = (list.result && Array.isArray(list.result.tools)) ? list.result.tools : [];
      tool = tools.find((t) => t && t.name === TOOL) || null;
      cursor = list.result && list.result.nextCursor;
      if (!cursor) break;
    }
    if (!tool) throw new Trouble(`Stream's server has no ${TOOL} tool.`);
    session.toolSchema = isPlainObject(tool.inputSchema) ? tool.inputSchema : null;
    session.toolArguments = Object.keys((session.toolSchema && session.toolSchema.properties) || {});
  }

  /// One JSON-RPC message over Streamable HTTP; the answer as JSON or as server-sent events.
  async rpc(server, tokens, session, method, params, notification = false) {
    const headers = {
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      Authorization: `Bearer ${tokens.access}`,
    };
    if (session.protocolVersion) headers["MCP-Protocol-Version"] = session.protocolVersion;
    if (session.sessionId) headers["Mcp-Session-Id"] = session.sessionId;
    const id = notification ? undefined : this.rpcID++;
    const message = notification ? { jsonrpc: "2.0", method } : { jsonrpc: "2.0", id, method, params: params || {} };
    const response = await timedFetch(server.mcpUrl, { method: "POST", headers, body: JSON.stringify(message) });
    if (response.status === 401) throw new Unauthorized();
    if (response.status === 404 && session.sessionId) throw new SessionGone();
    if (notification) return {};
    if (!response.ok) throw new Trouble(`Stream's server answered ${response.status}.`);
    const reply = await rpcReply(response, id);
    if (reply.error) {
      const text = String(reply.error.message || reply.error.code || "an error");
      if (/initiali[sz]|session/i.test(text)) throw new SessionGone();
      throw new Trouble(`Stream's server said: ${text}.`);
    }
    return { result: reply.result, sessionId: response.headers.get("Mcp-Session-Id") };
  }

  /// What the tool returned, taken into the inbox. The first poll after an approval takes nothing older than it (by
  /// the interactions' times when they have them, else every id it sees is kept as seen); after that every new id is
  /// taken, whatever its time says. An answer that can't be read is said, with its shape and never its words, and so is
  /// a list whose interactions carry no words the relay knows (their field names, 2026-11-23: George's first real
  /// capture came by the webhook while every poll found nothing to take).
  ///
  /// A relay whose reader changed (`READER`) starts again from this poll, as a new connection does: what Stream lists
  /// now is kept as seen. Without that, a reader that learned to read Stream's answer would take the past week's
  /// captures as new ones.
  async take(result, conn, now) {
    const read = interactionsFrom(result, now);
    if (read.error) return { lastError: `Stream's tool said: ${read.error}` };
    if (!read.items) {
      return { lastError: "Stream's answer couldn't be read: the relay found no list of interactions in it.", answerShape: read.shape };
    }
    const newReader = conn.baselineDone && conn.reader !== READER;
    const counts = { lastListed: read.listed, reader: READER };
    // Interactions with no words the relay knows: said, and the poller waits at its first poll, from now, so the day
    // they can be read starts from that poll and not from a week of captures it couldn't read.
    if (read.listed > 0 && !read.items.length) {
      return {
        ...counts, baselineDone: false, since: now, kept: [], answerShape: null, interactionFields: read.listFields,
        lastError: `Stream listed ${read.listed} interaction${read.listed === 1 ? "" : "s"}, but the relay found no words in them (their fields: ${read.listFields.join(", ") || "none"}).`,
      };
    }
    const items = read.items;
    for (const item of items) item.hash = await textHash(item.text);
    const kept = [];
    const firstPoll = !conn.baselineDone || newReader;
    const since = newReader ? now : conn.since;
    for (const item of items) {
      if (this.has(item.id)) {
        if (this.getMeta("idsMatch", false) === false) {
          const existing = this.sql.exec("SELECT source FROM captures WHERE id = ? LIMIT 1", item.id).toArray()[0];
          if (existing && existing.source === "webhook") this.setMeta("idsMatch", true);
        }
        continue;
      }
      const old = firstPoll && (item.at === null || item.at < since);
      if (old || item.deleted || !item.text.trim()) {
        this.markSeen(item.id, "stream", this.now());
        continue;
      }
      if (this.keep({ id: item.id, text: item.text, body: JSON.stringify(item.raw), hash: item.hash, source: "stream",
        fields: item.fields, said: item.at }) === "accepted") kept.push(item.id);
    }
    return {
      ...counts, baselineDone: true, since, lastError: null, kept, answerShape: null,
      interactionFields: items.length ? items[0].fields : read.listFields.length ? read.listFields : conn.interactionFields || null,
    };
  }
}

// MARK: - Reading Stream's answers

/// The tool's arguments from its input schema: a count-like argument asks for 100 (Stream's most); a required one
/// takes its default. Others are left to Stream (its default is the last 7 days).
function argumentsFor(schema) {
  const args = {};
  const properties = (schema && isPlainObject(schema.properties)) ? schema.properties : {};
  const required = new Set(Array.isArray(schema && schema.required) ? schema.required : []);
  for (const [name, spec] of Object.entries(properties)) {
    const type = spec && spec.type;
    if (/^(limit|count|max|max_?results|n|num|page_?size|per_?page)$/i.test(name) && (type === "integer" || type === "number")) {
      args[name] = Math.min(100, Number.isFinite(spec.maximum) ? spec.maximum : 100);
    } else if (required.has(name) && spec && "default" in spec) {
      args[name] = spec.default;
    }
  }
  return args;
}

/// The interactions in a `tools/call` result, read tolerantly: from `structuredContent`, or each text content as
/// JSON; an array of objects, bare or under a key. `items` is null when nothing in the answer is such a list (then
/// `shape` says what came: content types, whether each text was JSON, the top-level keys, never words). Times are
/// judged against `receivedAt`, the poll's own.
function interactionsFrom(result, receivedAt) {
  const candidates = [];
  if (result && result.structuredContent !== undefined) candidates.push(result.structuredContent);
  const json = [];
  for (const part of (result && Array.isArray(result.content)) ? result.content : []) {
    if (part && part.type === "text" && typeof part.text === "string") {
      try {
        candidates.push(JSON.parse(part.text));
        json.push(true);
      } catch {
        json.push(false);
      }
    }
  }
  for (const value of candidates) {
    const list = objectList(value);
    if (list) {
      return {
        items: list.map((raw) => interaction(raw, receivedAt)).filter(Boolean),
        listed: list.length,
        listFields: list.length ? Object.keys(list[0]).slice(0, 64) : [],
      };
    }
  }
  for (const value of candidates) {
    if (isPlainObject(value) && value.error) return { error: String(value.error.message || value.error) };
  }
  if (result && result.isError) return { error: "an error with no words" };
  const content = (result && Array.isArray(result.content)) ? result.content : [];
  return {
    items: null,
    shape: {
      contentTypes: content.map((part) => (part && typeof part.type === "string" ? part.type : typeof part)),
      json,
      structured: Boolean(result && result.structuredContent !== undefined),
      keys: [...new Set(candidates.flatMap((value) => (isPlainObject(value) ? Object.keys(value) : [])))].slice(0, 32),
    },
  };
}

function objectList(value, depth = 0) {
  if (Array.isArray(value)) return value.every((v) => isPlainObject(v)) ? value : null;
  if (!isPlainObject(value) || depth > 2) return null;
  for (const key of ["interactions", "items", "results", "data", "recent", "records", "entries"]) {
    const found = objectList(value[key], depth + 1);
    if (found) return found;
  }
  for (const nested of Object.values(value)) {
    if (Array.isArray(nested) && nested.length && nested.every((v) => isPlainObject(v))) return nested;
  }
  return null;
}

const TIME_FIELDS = ["requestReceivedAtUnix", "requestReceivedAt", "created_at", "createdAt", "timestamp", "time", "date",
  "saved_at", "savedAt", "occurred_at", "occurredAt", "started_at", "startedAt", "updated_at", "updatedAt"];

/// Where an interaction's words may be, in this order: what the person said, under the names an API would give it. A
/// field holding an object with its own `text` counts too (`{"message": {"text": …}}`). Never a reply's or a summary's.
/// Stream's own (2026-11-23, George's relay): `requestReceivedAtUnix`, `inputText` (his words), `outputText` (Stream's
/// reply, never read), `noteId`, `deleted`, and no id: the id is made from the words and the time.
const TEXT_FIELDS = ["inputText", "input_text", "text", "transcript", "transcription", "content", "body", "note",
  "message", "value", "utterance", "user_text", "userText", "said", "spoken", "input", "query", "prompt", "request"];

function interaction(raw, receivedAt) {
  let text = first(raw, TEXT_FIELDS, (v) => typeof v === "string");
  if (typeof text !== "string") {
    const holder = first(raw, TEXT_FIELDS, (v) => isPlainObject(v) && typeof v.text === "string");
    text = holder ? holder.text : undefined;
  }
  if (typeof text !== "string") return null;
  const at = parseTime(first(raw, TIME_FIELDS, (v) => parseTime(v, receivedAt) !== null), receivedAt);
  let id = interactionID(first(raw, ["interaction_id", "interactionId", "id", "uuid"], (v) => interactionID(v) !== null));
  if (!id) id = `words-${simpleHash(`${text}|${at || ""}`)}`;
  // Deleted in Stream: never a task.
  const deleted = raw.deleted === true || raw.isDeleted === true;
  return { id, text, at: at === undefined ? null : at, deleted, raw, fields: Object.keys(raw).slice(0, 64) };
}

function first(object, keys, accept) {
  for (const key of keys) {
    if (object[key] !== undefined && object[key] !== null && accept(object[key])) return object[key];
  }
  return undefined;
}

/// A moment, only when it can't be misread and could be the capture's: epoch seconds or milliseconds, or an ISO 8601
/// time with its zone, after 2020 began and no later than five minutes after the relay got it (`receivedAt`). A date
/// alone, or a time with no zone, would be read as UTC and could be hours off; `{"time": 12}` would be 1970 (round 3,
/// finding 6): each counts as no time.
function parseTime(value, receivedAt) {
  let ms = null;
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    ms = value > 100_000_000_000 ? value : value * 1000;
  } else if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/i.test(value.trim())) {
    const parsed = Date.parse(value.trim());
    ms = Number.isNaN(parsed) ? null : parsed;
  }
  if (ms === null || ms < EARLIEST_SAID_MS || ms > receivedAt + SAID_AHEAD_MS) return null;
  return ms;
}

/// A JSON-RPC answer: the body as JSON, or, from a stream of server-sent events, the event carrying the message with
/// this id, read as it arrives (a server may keep the stream open after it).
async function rpcReply(response, id) {
  const type = response.headers.get("Content-Type") || "";
  if (!type.includes("text/event-stream")) return JSON.parse(await response.text());
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (value) buffer += decoder.decode(value, { stream: true });
    for (let end = buffer.search(/\r?\n\r?\n/); end >= 0; end = buffer.search(/\r?\n\r?\n/)) {
      const message = eventMessage(buffer.slice(0, end));
      buffer = buffer.slice(end).replace(/^\r?\n\r?\n/, "");
      if (message && message.id === id) {
        reader.cancel().catch(() => {});
        return message;
      }
    }
    if (done) break;
  }
  const message = eventMessage(buffer);
  if (message && message.id === id) return message;
  throw new Trouble("Stream's server sent no answer.");
}

function eventMessage(event) {
  const data = event.split(/\r?\n/).filter((line) => line.startsWith("data:")).map((line) => line.slice(5).trimStart()).join("\n");
  if (!data) return null;
  try {
    return JSON.parse(data);
  } catch {
    return null;
  }
}

// MARK: - OAuth helpers

/// The MCP server's protected-resource metadata (from a 401's WWW-Authenticate, or its well-known places), then its
/// authorization server's metadata (RFC 8414, or OpenID's).
async function discover(mcpUrl) {
  const mcp = new URL(mcpUrl);
  let named = null;
  try {
    const probe = await timedFetch(mcpUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 0, method: "initialize", params: { protocolVersion: MCP_PROTOCOL, capabilities: {}, clientInfo: { name: CLIENT_NAME, version: "1" } } }),
    });
    if (probe.status === 401) named = resourceMetadataURL(probe.headers.get("WWW-Authenticate"));
    probe.body && probe.body.cancel().catch(() => {});
  } catch { /* the well-known places next */ }
  let resource = null;
  for (const candidate of unique([named, wellKnown(mcp, "oauth-protected-resource"), `${mcp.origin}/.well-known/oauth-protected-resource`])) {
    const metadata = await getJSON(candidate);
    if (metadata && Array.isArray(metadata.authorization_servers) && metadata.authorization_servers.length) {
      resource = metadata;
      break;
    }
  }
  const issuer = resource ? String(resource.authorization_servers[0]) : mcp.origin;
  const as = await authorizationServerMetadata(issuer);
  if (!as) throw new Trouble("Stream's sign-in couldn't be found.");
  for (const name of ["authorization_endpoint", "token_endpoint", "registration_endpoint"]) {
    if (!as[name] || !safeURL(as[name])) throw new Trouble(`Stream's sign-in has no usable ${name}.`);
  }
  return {
    mcpUrl,
    resource: (resource && typeof resource.resource === "string" && resource.resource) || mcpUrl,
    issuer: as.issuer || issuer,
    authorizationEndpoint: as.authorization_endpoint,
    tokenEndpoint: as.token_endpoint,
    registrationEndpoint: as.registration_endpoint,
  };
}

function resourceMetadataURL(header) {
  const match = /resource_metadata="([^"]+)"/i.exec(header || "");
  return match && safeURL(match[1]) ? match[1] : null;
}

/// RFC 8414 and RFC 9728: the well-known name goes between the host and the path.
function wellKnown(url, name) {
  const path = url.pathname === "/" ? "" : url.pathname.replace(/\/$/, "");
  return `${url.origin}/.well-known/${name}${path}`;
}

async function authorizationServerMetadata(issuer) {
  if (!safeURL(issuer)) return null;
  const url = new URL(issuer);
  const path = url.pathname === "/" ? "" : url.pathname.replace(/\/$/, "");
  const candidates = [
    `${url.origin}/.well-known/oauth-authorization-server${path}`,
    `${url.origin}/.well-known/openid-configuration${path}`,
    path ? `${url.origin}${path}/.well-known/openid-configuration` : null,
  ];
  for (const candidate of unique(candidates)) {
    const metadata = await getJSON(candidate);
    if (metadata && metadata.authorization_endpoint && metadata.token_endpoint) return metadata;
  }
  return null;
}

/// Dynamic client registration (RFC 7591). A public client is asked for; a server that hands back a secret gets it
/// back the way its registration says (`token_endpoint_auth_method`).
async function register(server, redirectUri) {
  const response = await timedFetch(server.registrationEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      client_name: CLIENT_NAME, redirect_uris: [redirectUri], token_endpoint_auth_method: "none",
      grant_types: ["authorization_code", "refresh_token"], response_types: ["code"], scope: SCOPE,
    }),
  });
  const reply = await response.json().catch(() => null);
  if (!response.ok || !reply || !reply.client_id) throw new Trouble(`Stream's sign-in didn't register this relay (${response.status}).`);
  const secret = typeof reply.client_secret === "string" && reply.client_secret ? reply.client_secret : null;
  const named = typeof reply.token_endpoint_auth_method === "string" ? reply.token_endpoint_auth_method : null;
  return {
    clientId: reply.client_id, clientSecret: secret,
    authMethod: named || (secret ? "client_secret_basic" : "none"),
    redirectUri, issuer: server.issuer, registeredAt: Date.now(),
  };
}

/// The token endpoint, with the client as its registration said. A 400 or 401 (`invalid_grant`, a revoked token, a
/// client the server forgot) is a refusal; anything else is trouble to try again next minute.
async function tokenRequest(server, client, fields) {
  const body = new URLSearchParams();
  const headers = { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" };
  body.set("client_id", client.clientId);
  if (client.clientSecret && client.authMethod === "client_secret_post") body.set("client_secret", client.clientSecret);
  if (client.clientSecret && client.authMethod === "client_secret_basic") {
    headers.Authorization = `Basic ${btoa(`${encodeURIComponent(client.clientId)}:${encodeURIComponent(client.clientSecret)}`)}`;
  }
  for (const [name, value] of Object.entries(fields)) if (value) body.set(name, value);
  const response = await timedFetch(server.tokenEndpoint, { method: "POST", headers, body: body.toString() });
  const reply = await response.json().catch(() => null);
  if (response.status === 400 || response.status === 401) {
    throw new Refused(`Stream refused (${(reply && (reply.error_description || reply.error)) || response.status}).`);
  }
  if (!response.ok || !reply || !reply.access_token) throw new Trouble(`Stream's sign-in answered ${response.status}.`);
  return reply;
}

async function pkceChallenge(verifier) {
  return base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", utf8(verifier))));
}

/// Apple's provider token: `{"alg":"ES256","kid":<key id>}.{"iss":<team id>,"iat":<seconds>}`, signed with the .p8
/// key (PKCS#8, P-256). WebCrypto's ECDSA signature is the raw r||s JWS wants.
async function signProviderToken(pem, keyId, teamId, issuedAt) {
  const key = await crypto.subtle.importKey("pkcs8", pemBody(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(utf8(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = base64url(utf8(JSON.stringify({ iss: teamId, iat: issuedAt })));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(`${header}.${claims}`));
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

/// The key's bytes from its PEM text (with real new lines, or `\n` written out, as a secret may hold it).
function pemBody(pem) {
  const text = String(pem || "").replace(/\\n/g, "\n");
  const body = text.replace(/-----BEGIN [^-]+-----/, "").replace(/-----END [^-]+-----/, "").replace(/[^A-Za-z0-9+/=]/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/// Metadata: a GET that may follow a redirect (nothing secret rides on it).
async function getJSON(url) {
  if (!url || !safeURL(url)) return null;
  try {
    const response = await timedFetch(url, { headers: { Accept: "application/json" } }, "follow");
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

/// Every call out: `https` only (or this machine), 15 s at most, and a POST is never sent on to another address.
async function timedFetch(url, init, redirect = "manual") {
  if (!safeURL(url)) throw new Trouble("Stream gave an address that isn't https.");
  try {
    return await fetch(url, { ...init, redirect, signal: AbortSignal.timeout(OUTBOUND_TIMEOUT_MS) });
  } catch (error) {
    throw new Trouble(error && error.name === "TimeoutError" ? "Stream didn't answer in time." : "Stream couldn't be reached.");
  }
}

/// `https`, or plain `http` on this machine (the tests' pretend Stream and Apple).
function safeURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" || (url.protocol === "http:" && ["127.0.0.1", "localhost"].includes(url.hostname));
  } catch {
    return false;
  }
}

/// Trouble is said in status and tried again next minute; a refusal or a second 401 ends the connection; a poll whose
/// sign-in was replaced while Stream answered stops quietly.
class Trouble extends Error {}
class Refused extends Trouble {}
class Unauthorized extends Error {
  constructor() { super("Stream didn't accept the relay's sign-in."); }
}
class SessionGone extends Error {
  constructor() { super("Stream's server forgot the relay's session."); }
}
class Ended extends Error {
  constructor() { super(ENDED); }
}
class Superseded extends Error {
  constructor() { super("A newer sign-in replaced this one."); }
}

function words(error) {
  return (error && error.message) || "something went wrong.";
}

// MARK: - Small things

async function hasInboxKey(request, env) {
  const match = /^Bearer\s+(\S+)\s*$/i.exec(request.headers.get("Authorization") || "");
  return sameSecret(match ? match[1] : "", env.INBOX_KEY || "");
}

/// Both sides hashed first, so the compare is of two equal lengths and takes the same time whatever was sent.
async function sameSecret(given, expected) {
  const [a, b] = await Promise.all([digest(given), digest(expected)]);
  return timingSafeEqual(a, b) && given.length > 0 && expected.length > 0;
}

function timingSafeEqual(a, b) {
  if (crypto.subtle.timingSafeEqual) return crypto.subtle.timingSafeEqual(a, b);
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.min(a.length, b.length); i += 1) difference |= a[i] ^ b[i];
  return difference === 0;
}

async function digest(text) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", utf8(text)));
}

/// The words, lowered and with their spaces folded, hashed: how the two routes' copies of one capture are matched.
/// The words folded for matching the two routes: case, spaces and punctuation aside ("Task, buy milk." is "task buy
/// milk"), so a route that writes the same words a little differently still matches.
async function textHash(text) {
  const folded = String(text || "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  return folded ? hex(await digest(folded)) : null;
}

/// An id for an interaction that came without one (FNV-1a, 64 bits): stable for the same words and time.
function simpleHash(text) {
  let h = 0xcbf29ce484222325n;
  for (const byte of utf8(text)) h = BigInt.asUintN(64, (h ^ BigInt(byte)) * 0x100000001b3n);
  return h.toString(16).padStart(16, "0");
}

async function readJSON(request) {
  const raw = await readCapped(request, MAX_KEYED_BODY);
  if (!raw || !raw.length) return {};
  try {
    const value = JSON.parse(new TextDecoder().decode(raw));
    return isPlainObject(value) ? value : null;
  } catch {
    return null;
  }
}

/// The body, or null when it is over `limit` bytes (stops reading there).
async function readCapped(request, limit) {
  const declared = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declared) && declared > limit) return null;
  if (!request.body) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  return concat(...chunks);
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function page(title, message, status = 200) {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHTML(title)}</title>
<style>body{margin:0;padding:56px 24px;background:#111418;color:#e9ecef;font:17px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:30rem;margin:0 auto}h1{font-size:22px;margin:0 0 8px}p{margin:0;color:#a9b1ba}</style></head>
<body><main><h1>${escapeHTML(title)}</h1><p>${escapeHTML(message)}</p></main></body></html>`;
  return new Response(html, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
  });
}

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function iso(ms) {
  return typeof ms === "number" && Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function utf8(text) {
  return new TextEncoder().encode(text);
}

function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.byteLength, 0));
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.byteLength;
  }
  return out;
}

function hex(bytes) {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function hexBytes(text) {
  const out = new Uint8Array(text.length / 2);
  for (let i = 0; i < out.length; i += 1) out[i] = parseInt(text.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function randomHex(bytes) {
  return hex(crypto.getRandomValues(new Uint8Array(bytes)));
}

function randomToken(bytes) {
  return base64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
