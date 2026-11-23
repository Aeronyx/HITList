// A pretend Stream for test.sh: an MCP server and its OAuth sign-in on 127.0.0.1, in memory, Node's built-ins only.
//
//   node test/fake-stream.mjs <port>
//
// It answers as the MCP authorization spec asks: a 401 that names its protected-resource metadata, that metadata, an
// authorization server with a path in its issuer (so the well-known rule is exercised), dynamic client registration,
// an authorization endpoint that approves at once (the sign-in a person would do), PKCE checked at the token
// endpoint, refresh tokens, and `get_recent_interactions` over JSON-RPC. Test controls live under /__fake/.
import http from "node:http";
import crypto from "node:crypto";

const port = Number(process.argv[2] || 8801);
const base = `http://127.0.0.1:${port}`;
const issuer = `${base}/auth`;
const resource = `${base}/mcp`;

const clients = new Map(); // client_id → registration
const codes = new Map(); // code → { clientId, redirectUri, challenge, resource }
let access = new Set();
const refresh = new Map(); // refresh token → clientId
let interactions = []; // newest first
let refuseRefresh = false;
let shape = "text"; // "text" (JSON in a text content) or "structured"
const log = { registrations: [], authorizations: [], grants: [], methods: [], arguments: [] };

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

function token(prefix) {
  return `${prefix}-${crypto.randomBytes(12).toString("hex")}`;
}

function challengeOf(verifier) {
  return crypto.createHash("sha256").update(verifier).digest("base64url");
}

function issue(clientId) {
  const a = token("at");
  const r = token("rt");
  access.add(a);
  refresh.set(r, clientId);
  return { access_token: a, token_type: "Bearer", expires_in: 3600, refresh_token: r, scope: "stream" };
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
      token_endpoint_auth_methods_supported: ["none"], scopes_supported: ["stream", "stream.write"],
    });
  }
  if (req.method === "POST" && path === "/auth/register") {
    const reg = JSON.parse(body || "{}");
    log.registrations.push(reg);
    const ok = reg.client_name && Array.isArray(reg.redirect_uris) && reg.redirect_uris.length
      && reg.token_endpoint_auth_method === "none"
      && ["authorization_code", "refresh_token"].every((g) => (reg.grant_types || []).includes(g));
    if (!ok) return send(res, 400, { error: "invalid_client_metadata" });
    const clientId = `fake-client-${clients.size + 1}`;
    clients.set(clientId, reg);
    return send(res, 201, { client_id: clientId, client_name: reg.client_name, redirect_uris: reg.redirect_uris, token_endpoint_auth_method: "none" });
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
    log.grants.push({ grant_type: p.grant_type, resource: p.resource, client_id: p.client_id });
    if (p.resource !== resource) return send(res, 400, { error: "invalid_target" });
    if (p.grant_type === "authorization_code") {
      const pending = codes.get(p.code);
      codes.delete(p.code);
      if (!pending || pending.clientId !== p.client_id || pending.redirectUri !== p.redirect_uri
          || challengeOf(p.code_verifier || "") !== pending.challenge) return send(res, 400, { error: "invalid_grant" });
      return send(res, 200, issue(p.client_id));
    }
    if (p.grant_type === "refresh_token") {
      const owner = refresh.get(p.refresh_token);
      if (refuseRefresh || !owner || owner !== p.client_id) return send(res, 400, { error: "invalid_grant" });
      refresh.delete(p.refresh_token);
      return send(res, 200, issue(owner));
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
    if (message.method === "notifications/initialized") { res.writeHead(202); return res.end(); }
    const reply = (result) => send(res, 200, { jsonrpc: "2.0", id: message.id, result });
    if (message.method === "initialize") {
      return reply({ protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "pretend-stream", version: "1" } });
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
      return reply(shape === "structured"
        ? { structuredContent: payload, content: [{ type: "text", text: JSON.stringify(payload) }] }
        : { content: [{ type: "text", text: JSON.stringify(payload) }] });
    }
    return send(res, 200, { jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "Method not found" } });
  }

  // Test controls.
  if (req.method === "POST" && path === "/__fake/interactions") { interactions = JSON.parse(body || "[]"); return send(res, 200, { ok: true }); }
  if (req.method === "POST" && path === "/__fake/expire") { access = new Set(); return send(res, 200, { ok: true }); }
  if (req.method === "POST" && path === "/__fake/refuse-refresh") { refuseRefresh = true; return send(res, 200, { ok: true }); }
  if (req.method === "POST" && path === "/__fake/allow-refresh") { refuseRefresh = false; return send(res, 200, { ok: true }); }
  if (req.method === "POST" && path === "/__fake/shape") { shape = body.trim() || "text"; return send(res, 200, { ok: true }); }
  if (req.method === "GET" && path === "/__fake/log") return send(res, 200, log);
  return send(res, 404, { error: "not found" });
});

server.listen(port, "127.0.0.1", () => console.log(`pretend Stream on ${base}`));
