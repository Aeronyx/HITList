// A pretend Stream and a pretend Apple push service for test.sh, on 127.0.0.1, in memory, Node's built-ins only.
//
//   node test/fake-stream.mjs <port> [<apns public key .pem> <key id> <team id>]
//
// Stream: answers as the MCP authorization spec asks: a 401 that names its protected-resource metadata, that metadata,
// an authorization server with a path in its issuer (so the well-known rule is exercised), dynamic client registration,
// an authorization endpoint that approves at once (the sign-in a person would do), PKCE checked at the token endpoint,
// refresh tokens (each token carries the number of the sign-in it came from), and `get_recent_interactions` over
// JSON-RPC. `POST /__fake/mode` makes it misbehave the ways a real server might (sessions, prose, event streams, slow
// or refused refreshes, a client secret, no refresh token).
//
// Apple: `POST /3/device/<token>` checks the headers, the payload and that the provider token verifies with the key's
// public half, and answers as `mode.apns` says. Test controls live under /__fake/.
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";

const port = Number(process.argv[2] || 8801);
const apnsPublicKey = process.argv[3] ? fs.readFileSync(process.argv[3], "utf8") : null;
const apnsKeyID = process.argv[4] || null;
const apnsTeamID = process.argv[5] || null;
const base = `http://127.0.0.1:${port}`;
const issuer = `${base}/auth`;
const resource = `${base}/mcp`;

const clients = new Map(); // client_id → registration
const codes = new Map(); // code → { clientId, redirectUri, challenge }
let access = new Map(); // access token → grant
const refresh = new Map(); // refresh token → { clientId, grant }
let grants = 0;
let interactions = []; // newest first
let sessions = 0;
let session404s = 0;
let mode = {};
const log = { registrations: [], authorizations: [], grants: [], methods: [], arguments: [], accessGrants: [], pushes: [] };

function send(res, status, body, headers = {}) {
  const text = body === undefined ? "" : typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(status, { "Content-Type": typeof body === "string" ? "text/plain" : "application/json", ...headers });
  res.end(text);
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
  });
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const token = (prefix) => `${prefix}-${crypto.randomBytes(12).toString("hex")}`;
const challengeOf = (verifier) => crypto.createHash("sha256").update(verifier).digest("base64url");

function issue(clientId, grant) {
  const a = token(`at-g${grant}`);
  access.set(a, grant);
  const reply = { access_token: a, token_type: "Bearer", expires_in: 3600, scope: "stream" };
  if (!mode.noRefreshToken) {
    const r = token(`rt-g${grant}`);
    refresh.set(r, { clientId, grant });
    reply.refresh_token = r;
  }
  return reply;
}

/// The client a token request names, checked as its registration said it would authenticate.
function clientOf(req, p) {
  const basic = /^Basic (.+)$/i.exec(req.headers.authorization || "");
  let id = p.client_id;
  let secret = p.client_secret;
  if (basic) [id, secret] = Buffer.from(basic[1], "base64").toString().split(":");
  const client = clients.get(id);
  if (!client) return null;
  if (client.secret && client.secret !== secret) return null;
  return id;
}

function verifyProviderToken(header) {
  const problems = [];
  const match = /^bearer (.+)$/i.exec(header || "");
  if (!match) return ["no bearer token"];
  const [h, c, s] = match[1].split(".");
  try {
    const head = JSON.parse(Buffer.from(h, "base64url"));
    const claims = JSON.parse(Buffer.from(c, "base64url"));
    if (head.alg !== "ES256") problems.push(`alg ${head.alg}`);
    if (head.kid !== apnsKeyID) problems.push(`kid ${head.kid}`);
    if (claims.iss !== apnsTeamID) problems.push(`iss ${claims.iss}`);
    if (!(Math.abs(Date.now() / 1000 - claims.iat) < 3600)) problems.push(`iat ${claims.iat}`);
    const ok = crypto.verify("sha256", Buffer.from(`${h}.${c}`), { key: apnsPublicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(s, "base64url"));
    if (!ok) problems.push("signature");
  } catch (error) {
    problems.push(`unreadable token: ${error.message}`);
  }
  return problems;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, base);
  const body = await readBody(req);
  const path = url.pathname;

  // Protected-resource metadata (RFC 9728), at the path-inserted place and the root.
  if (req.method === "GET" && (path === "/.well-known/oauth-protected-resource/mcp" || path === "/.well-known/oauth-protected-resource")) {
    return send(res, 200, { resource, authorization_servers: [issuer], scopes_supported: ["stream", "stream.write"] });
  }
  // Authorization server metadata (RFC 8414): the issuer has a path, so only the inserted form answers.
  if (req.method === "GET" && path === "/.well-known/oauth-authorization-server/auth") {
    return send(res, 200, {
      issuer, authorization_endpoint: `${issuer}/authorize`, token_endpoint: `${issuer}/token`,
      registration_endpoint: `${issuer}/register`, response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"], code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post"], scopes_supported: ["stream", "stream.write"],
    });
  }
  if (req.method === "POST" && path === "/auth/register") {
    const reg = JSON.parse(body || "{}");
    log.registrations.push(reg);
    const ok = reg.client_name && Array.isArray(reg.redirect_uris) && reg.redirect_uris.length
      && ["authorization_code", "refresh_token"].every((g) => (reg.grant_types || []).includes(g));
    if (!ok) return send(res, 400, { error: "invalid_client_metadata" });
    const clientId = `fake-client-${clients.size + 1}`;
    const secret = mode.clientSecret ? token("secret") : null;
    clients.set(clientId, { ...reg, secret });
    return send(res, 201, {
      client_id: clientId, client_name: reg.client_name, redirect_uris: reg.redirect_uris,
      ...(secret ? { client_secret: secret, token_endpoint_auth_method: "client_secret_post" } : { token_endpoint_auth_method: "none" }),
    });
  }
  if (req.method === "GET" && path === "/auth/authorize") {
    const p = Object.fromEntries(url.searchParams);
    log.authorizations.push(p);
    const client = clients.get(p.client_id);
    const valid = client && client.redirect_uris.includes(p.redirect_uri) && p.response_type === "code"
      && p.code_challenge_method === "S256" && p.code_challenge && p.state && p.scope === "stream" && p.resource === resource;
    if (!valid) return send(res, 400, "bad authorization request");
    const code = token("code");
    codes.set(code, { clientId: p.client_id, redirectUri: p.redirect_uri, challenge: p.code_challenge });
    const back = new URL(p.redirect_uri);
    back.searchParams.set("code", code);
    back.searchParams.set("state", p.state);
    res.writeHead(302, { Location: back.toString() });
    return res.end();
  }
  if (req.method === "POST" && path === "/auth/token") {
    const p = Object.fromEntries(new URLSearchParams(body));
    const clientId = clientOf(req, p);
    log.grants.push({ grant_type: p.grant_type, resource: p.resource, client_id: p.client_id, secret: Boolean(p.client_secret) });
    if (!clientId) return send(res, 401, { error: "invalid_client" });
    if (p.resource !== resource) return send(res, 400, { error: "invalid_target" });
    if (p.grant_type === "authorization_code") {
      const pending = codes.get(p.code);
      codes.delete(p.code);
      if (!pending || pending.clientId !== clientId || pending.redirectUri !== p.redirect_uri
          || challengeOf(p.code_verifier || "") !== pending.challenge) return send(res, 400, { error: "invalid_grant" });
      grants += 1;
      return send(res, 200, issue(clientId, grants));
    }
    if (p.grant_type === "refresh_token") {
      const owner = refresh.get(p.refresh_token);
      if (mode.refreshDelayMs) await wait(mode.refreshDelayMs);
      if (mode.refuseRefresh || !owner || owner.clientId !== clientId || owner.grant === mode.refuseRefreshGrant) {
        return send(res, 400, { error: "invalid_grant" });
      }
      refresh.delete(p.refresh_token);
      return send(res, 200, issue(owner.clientId, owner.grant));
    }
    return send(res, 400, { error: "unsupported_grant_type" });
  }
  if (req.method === "POST" && path === "/mcp") {
    const auth = (req.headers.authorization || "").replace(/^Bearer /, "");
    if (!access.has(auth)) {
      return send(res, 401, { error: "invalid_token" }, {
        "WWW-Authenticate": `Bearer resource_metadata="${base}/.well-known/oauth-protected-resource/mcp"`,
      });
    }
    const message = JSON.parse(body || "{}");
    log.methods.push(message.method);
    log.accessGrants.push(access.get(auth));
    if (mode.mcpDelayMs) await wait(mode.mcpDelayMs);
    if (mode.session404 && req.headers["mcp-session-id"]) {
      session404s += 1;
      // A relay that keeps asking is slowed down, so a broken one can't flood this Mac.
      if (session404s > 50) await wait(20_000);
      return send(res, 404, { error: "session not found" });
    }
    if (message.method === "notifications/initialized") { res.writeHead(202); return res.end(); }
    const reply = (result, headers = {}) => send(res, 200, { jsonrpc: "2.0", id: message.id, result }, headers);
    if (message.method === "initialize") {
      sessions += 1;
      return reply({ protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "pretend-stream", version: "1" } },
        mode.sessionIds ? { "Mcp-Session-Id": `sess-${sessions}` } : {});
    }
    if (message.method === "tools/list") {
      return reply({ tools: [{
        name: "get_recent_interactions",
        description: "What the user has said to Stream lately, newest first.",
        inputSchema: { type: "object", properties: { limit: { type: "integer", maximum: 100 }, days: { type: "integer" } } },
      }] });
    }
    if (message.method === "tools/call" && message.params && message.params.name === "get_recent_interactions") {
      log.arguments.push(message.params.arguments);
      const payload = { interactions };
      if (mode.prose) return reply({ content: [{ type: "text", text: "You said three things lately; ask me for details." }] });
      const result = mode.shape === "structured"
        ? { structuredContent: payload, content: [{ type: "text", text: JSON.stringify(payload) }] }
        : { content: [{ type: "text", text: JSON.stringify(payload) }] };
      if (mode.sse) {
        // One event for the call, then the stream stays open: a relay that reads to the end waits for nothing.
        res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" });
        res.write(`event: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: message.id, result })}\n\n`);
        setTimeout(() => res.end(), 20_000);
        return undefined;
      }
      return reply(result);
    }
    return send(res, 200, { jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "Method not found" } });
  }

  // Apple's push service.
  const device = /^\/3\/device\/([0-9a-f]+)$/.exec(path);
  if (req.method === "POST" && device) {
    const problems = verifyProviderToken(req.headers.authorization);
    if (req.headers["apns-push-type"] !== "background") problems.push(`apns-push-type ${req.headers["apns-push-type"]}`);
    if (req.headers["apns-priority"] !== "5") problems.push(`apns-priority ${req.headers["apns-priority"]}`);
    if (req.headers["apns-topic"] !== "com.trammells.hitlist") problems.push(`apns-topic ${req.headers["apns-topic"]}`);
    let payload = null;
    try { payload = JSON.parse(body); } catch { problems.push("payload not JSON"); }
    if (!payload || !payload.aps || payload.aps["content-available"] !== 1 || !payload.hitlist || payload.hitlist.inbox !== 1) {
      problems.push(`payload ${body}`);
    }
    if (mode.apnsDelayMs) await wait(mode.apnsDelayMs);
    const answer = (mode.apns || {})[device[1]];
    const expire = mode.apnsExpireOnce && !log.pushes.some((p) => p.expired);
    log.pushes.push({ token: device[1], problems, at: Date.now(), expired: Boolean(expire) });
    if (expire) return send(res, 403, { reason: "ExpiredProviderToken" });
    if (answer) return send(res, answer[0], { reason: answer[1] });
    if (problems.length) return send(res, 400, { reason: "BadRequest", problems });
    return send(res, 200, "", { "apns-id": crypto.randomUUID() });
  }

  // Test controls.
  if (req.method === "POST" && path === "/__fake/interactions") { interactions = JSON.parse(body || "[]"); return send(res, 200, { ok: true }); }
  if (req.method === "POST" && path === "/__fake/expire") { access = new Map(); return send(res, 200, { ok: true }); }
  if (req.method === "POST" && path === "/__fake/mode") { mode = { ...mode, ...JSON.parse(body || "{}") }; return send(res, 200, mode); }
  if (req.method === "GET" && path === "/__fake/log") return send(res, 200, { ...log, sessions, session404s, grantCount: grants });
  return send(res, 404, { error: "not found" });
});

server.listen(port, "127.0.0.1", () => console.log(`pretend Stream and Apple on ${base}`));
