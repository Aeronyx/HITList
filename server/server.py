#!/usr/bin/env python3
"""HITList backup receiver.

A tiny, dependency-free HTTP service that stores JSON snapshots pushed by the HITList app.
Snapshots land in DATA_DIR as timestamped files plus a `latest.json` pointer, so an existing
backup pipeline (e.g. the host's B2 job) picks them up with no extra configuration.

Endpoints (all require `Authorization: Bearer <HITLIST_TOKEN>`):
  PUT  /snapshot            store the JSON body; returns {"stored": "<filename>"}
  GET  /snapshot/latest     return the most recent snapshot
  GET  /snapshots           list stored snapshot filenames (newest first)
  GET  /snapshots/<name>    return one stored snapshot
  GET  /health              no auth; returns {"ok": true}
"""
import hmac
import json
import os
import re
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA_DIR = Path(os.environ.get("HITLIST_DATA_DIR", "/data"))
TOKEN = os.environ.get("HITLIST_TOKEN", "")
KEEP = int(os.environ.get("HITLIST_KEEP", "500"))
MAX_BYTES = int(os.environ.get("HITLIST_MAX_BYTES", str(25 * 1024 * 1024)))
PORT = int(os.environ.get("PORT", "8787"))
NAME_RE = re.compile(r"^\d{8}T\d{6}Z(-[A-Za-z0-9_-]{1,40})?\.json$")


def log(msg: str) -> None:
    print(f"{datetime.now(timezone.utc).isoformat()} {msg}", flush=True)


class Handler(BaseHTTPRequestHandler):
    server_version = "HITListBackup/1.0"

    def log_message(self, fmt, *args):  # quieter default logging
        log("%s %s" % (self.address_string(), fmt % args))

    # -- helpers -----------------------------------------------------------------
    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, status: int, obj) -> None:
        self._send(status, json.dumps(obj).encode())

    def _authorized(self) -> bool:
        if not TOKEN:
            return False
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        return hmac.compare_digest(header[7:].strip(), TOKEN)

    def _require_auth(self) -> bool:
        if self._authorized():
            return True
        self._json(401, {"error": "unauthorized"})
        return False

    # -- routes ------------------------------------------------------------------
    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"ok": True})
        if not self._require_auth():
            return
        if self.path == "/snapshots":
            return self._json(200, {"snapshots": list_snapshots()})
        if self.path == "/snapshot/latest":
            latest = DATA_DIR / "latest.json"
            if not latest.exists():
                return self._json(404, {"error": "no snapshots yet"})
            return self._send(200, latest.read_bytes())
        if self.path.startswith("/snapshots/"):
            name = self.path[len("/snapshots/"):]
            if not NAME_RE.match(name):
                return self._json(400, {"error": "bad name"})
            target = DATA_DIR / name
            if not target.exists():
                return self._json(404, {"error": "not found"})
            return self._send(200, target.read_bytes())
        self._json(404, {"error": "not found"})

    def do_HEAD(self):
        self.do_GET()

    def do_PUT(self):
        if self.path != "/snapshot":
            return self._json(404, {"error": "not found"})
        if not self._require_auth():
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BYTES:
            return self._json(413, {"error": f"body must be 1..{MAX_BYTES} bytes"})
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
            if not isinstance(payload, dict) or "tasks" not in payload or "version" not in payload:
                raise ValueError("not a HITList snapshot")
        except ValueError as e:
            return self._json(400, {"error": f"invalid snapshot: {e}"})

        device = re.sub(r"[^A-Za-z0-9_-]", "-", str(payload.get("deviceName", "")))[:40].strip("-")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        name = f"{stamp}-{device}.json" if device else f"{stamp}.json"
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = DATA_DIR / (name + ".tmp")
        tmp.write_bytes(body)
        os.replace(tmp, DATA_DIR / name)
        latest_tmp = DATA_DIR / "latest.json.tmp"
        latest_tmp.write_bytes(body)
        os.replace(latest_tmp, DATA_DIR / "latest.json")
        pruned = prune()
        log(f"stored {name} ({length} bytes, {len(payload.get('tasks', []))} tasks, pruned {pruned})")
        self._json(200, {"stored": name, "tasks": len(payload.get("tasks", [])), "pruned": pruned})

    def do_POST(self):
        # Allow POST as an alias for clients that can't PUT.
        self.do_PUT() if self.path == "/snapshot" else self._json(404, {"error": "not found"})


def list_snapshots():
    if not DATA_DIR.exists():
        return []
    names = [p.name for p in DATA_DIR.iterdir() if NAME_RE.match(p.name)]
    return sorted(names, reverse=True)


def prune() -> int:
    names = list_snapshots()
    extra = names[KEEP:]
    for n in extra:
        try:
            (DATA_DIR / n).unlink()
        except OSError:
            pass
    return len(extra)


def main():
    if not TOKEN or len(TOKEN) < 16:
        print("HITLIST_TOKEN must be set to at least 16 characters", file=sys.stderr)
        sys.exit(2)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log(f"listening on :{PORT}, storing in {DATA_DIR}, keeping {KEEP} snapshots")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
