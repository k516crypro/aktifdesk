'use strict';

/**
 * AktifDesk pairing relay — bridges one host + one client WebSocket per room.
 *
 * Protocol (JSON text frames until paired; then opaque forward both ways):
 *   Host  -> { v:1, type:"hello", role:"host", code:"482913", deviceId, name }
 *   Relay <- { v:1, type:"waiting" }
 *   Client-> { v:1, type:"hello", role:"client", code:"482913", deviceId, name, pairKey? }
 *   Both  <- { v:1, type:"paired", peer:{ id, name, role } }
 *   After that: every text/binary frame is forwarded to the peer.
 *
 * Health: GET /  and GET /health -> 200 JSON
 * Env: PORT (Railway), ROOM_TTL_MS (default 15 min idle)
 */

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT || 8080);
const ROOM_TTL_MS = Number(process.env.ROOM_TTL_MS || 15 * 60 * 1000);
const MAX_CODE_LEN = 16;

/** @type {Map<string, { host?: SocketState, client?: SocketState, createdAt: number }>} */
const rooms = new Map();

/**
 * @typedef {{ ws: import('ws').WebSocket, role: string, deviceId: string, name: string, code: string, pairKey?: string, peer?: SocketState }} SocketState
 */

function send(ws, obj) {
  if (ws.readyState === 1) ws.send(JSON.stringify(obj));
}

function normalizeCode(raw) {
  return String(raw || '').replace(/\D/g, '').slice(0, MAX_CODE_LEN);
}

function roomKey(code) {
  return normalizeCode(code);
}

function cleanupRoom(code) {
  const r = rooms.get(code);
  if (!r) return;
  if (!r.host && !r.client) rooms.delete(code);
}

function detach(state) {
  if (!state) return;
  const code = state.code;
  const room = rooms.get(code);
  if (room) {
    if (room.host === state) room.host = undefined;
    if (room.client === state) room.client = undefined;
    cleanupRoom(code);
  }
  const peer = state.peer;
  if (peer) {
    peer.peer = undefined;
    try {
      send(peer.ws, { v: 1, type: 'peer_left' });
    } catch (_) {}
  }
  state.peer = undefined;
}

function pair(a, b) {
  a.peer = b;
  b.peer = a;
  send(a.ws, { v: 1, type: 'paired', peer: { id: b.deviceId, name: b.name, role: b.role } });
  send(b.ws, { v: 1, type: 'paired', peer: { id: a.deviceId, name: a.name, role: a.role } });
}

function sweep() {
  const now = Date.now();
  for (const [code, room] of rooms) {
    const idleHost = room.host && !room.host.peer;
    const idleClient = room.client && !room.client.peer;
    if ((idleHost || idleClient) && now - room.createdAt > ROOM_TTL_MS) {
      if (room.host) {
        try { room.host.ws.close(4000, 'ttl'); } catch (_) {}
      }
      if (room.client) {
        try { room.client.ws.close(4000, 'ttl'); } catch (_) {}
      }
      rooms.delete(code);
    }
  }
}
setInterval(sweep, 60_000).unref?.();

const server = http.createServer((req, res) => {
  const url = req.url || '/';
  if (url === '/' || url.startsWith('/health')) {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      service: 'aktifdesk-relay',
      rooms: rooms.size,
      version: 1,
    }));
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('AktifDesk relay — connect via WebSocket at /aktifdesk-relay\n');
});

const wss = new WebSocketServer({ server, path: '/aktifdesk-relay' });

wss.on('connection', (ws) => {
  /** @type {SocketState | null} */
  let state = null;
  let paired = false;

  ws.on('message', (data, isBinary) => {
    if (paired && state?.peer) {
      try {
        if (state.peer.ws.readyState === 1) {
          state.peer.ws.send(data, { binary: !!isBinary });
        }
      } catch (_) {}
      return;
    }

    if (isBinary) return;
    let msg;
    try {
      msg = JSON.parse(String(data));
    } catch (_) {
      send(ws, { v: 1, type: 'error', error: 'invalid_json' });
      return;
    }

    if (msg?.type !== 'hello' || (msg.role !== 'host' && msg.role !== 'client')) {
      send(ws, { v: 1, type: 'error', error: 'expected_hello' });
      return;
    }

    const code = roomKey(msg.code);
    if (code.length < 4) {
      send(ws, { v: 1, type: 'error', error: 'bad_code' });
      return;
    }

    const deviceId = String(msg.deviceId || '').slice(0, 64) || `anon-${Math.random().toString(36).slice(2, 10)}`;
    const name = String(msg.name || msg.role).slice(0, 64);
    const pairKey = msg.pairKey ? String(msg.pairKey).slice(0, 128) : undefined;

    let room = rooms.get(code);
    if (!room) {
      room = { createdAt: Date.now() };
      rooms.set(code, room);
    }

    if (msg.role === 'host') {
      if (room.host && room.host.ws.readyState === 1 && room.host.ws !== ws) {
        try { room.host.ws.close(4001, 'replaced'); } catch (_) {}
        detach(room.host);
      }
      state = { ws, role: 'host', deviceId, name, code, pairKey };
      room.host = state;
      room.createdAt = Date.now();
      if (room.client && room.client.ws.readyState === 1) {
        pair(state, room.client);
        paired = true;
        room.client.peer && (paired = true);
      } else {
        send(ws, { v: 1, type: 'waiting' });
      }
    } else {
      if (room.client && room.client.ws.readyState === 1 && room.client.ws !== ws) {
        try { room.client.ws.close(4001, 'replaced'); } catch (_) {}
        detach(room.client);
      }
      state = { ws, role: 'client', deviceId, name, code, pairKey };
      room.client = state;
      room.createdAt = Date.now();
      if (room.host && room.host.ws.readyState === 1) {
        pair(room.host, state);
        paired = true;
      } else {
        send(ws, { v: 1, type: 'waiting' });
      }
    }

    if (state?.peer) paired = true;
  });

  ws.on('close', () => {
    detach(state);
    state = null;
    paired = false;
  });

  ws.on('error', () => {
    detach(state);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`aktifdesk-relay listening on :${PORT}  path=/aktifdesk-relay`);
});
