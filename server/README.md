# HITList backup receiver

Stores JSON snapshots pushed by the HITList app. Zero dependencies beyond Python 3.

```bash
cp .env.example .env
sed -i '' "s/change-me.*/$(openssl rand -hex 32)/" .env   # macOS; drop the '' on Linux
docker compose up -d --build
curl -s http://localhost:8787/health
```

Put `./data` (or whatever you mount at `/data`) inside the tree your B2 job backs up.
Expose the port only on your LAN / Tailscale, or behind your reverse proxy with TLS.
The app needs the base URL (e.g. `https://home.example.com/hitlist`) and the token.

Manual test:

```bash
curl -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data '{"version":1,"deviceName":"curl","tasks":[],"projects":[],"labels":[],"filters":[]}' \
  http://localhost:8787/snapshot
```
