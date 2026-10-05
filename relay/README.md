# AktifDesk relay (Railway)

Tiny WebSocket room bridge so a **phone host** and **client** on different networks can pair with the same 6-digit code.

## Deploy on Railway

1. Create a new Railway project → **Deploy from GitHub** (this repo) **or** empty project + this folder.
2. Set **Root Directory** to `relay` (important if the repo root is AktifDesk).
3. Railway detects `Dockerfile` / `railway.toml`. Deploy.
4. Generate a public domain (Railway → Settings → Networking → Generate Domain), e.g. `https://aktifdesk-relay-production.up.railway.app`.
5. In AktifDesk **Ayarlar → Uzak bağlantı**, set relay URL to:
   ```
   wss://YOUR-SUBDOMAIN.up.railway.app/aktifdesk-relay
   ```
   (`ws://` only for local testing.)

## Local

```bash
cd relay && npm install && npm start
# ws://127.0.0.1:8080/aktifdesk-relay
```

## Protocol

See comments in `server.js`. LAN discovery stays the fast path; relay is optional.

## Limits

- One host + one client per code room.
- Idle unpaired rooms expire (~15 min, `ROOM_TTL_MS`).
- Relays **control JSON only** (taps/keys/status). Not a video CDN — screen mirror still needs MediaProjection later.
