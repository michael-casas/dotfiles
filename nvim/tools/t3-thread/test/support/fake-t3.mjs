// A local, synthetic stand-in for the T3 server: just enough HTTP and
// WebSocket (RFC 6455 text frames) for main.mjs to subscribe to one thread.
// Binds 127.0.0.1 on an ephemeral port; never talks to a real T3 server.
import http from "node:http";
import https from "node:https";
import crypto from "node:crypto";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function frame(text) {
  const body = Buffer.from(text);
  const n = body.length;
  const head = n < 126 ? Buffer.from([0x81, n]) : n < 65536 ? Buffer.alloc(4) : Buffer.alloc(10);
  if (n >= 126 && n < 65536) {
    head[0] = 0x81;
    head[1] = 126;
    head.writeUInt16BE(n, 2);
  } else if (n >= 65536) {
    head[0] = 0x81;
    head[1] = 127;
    head.writeBigUInt64BE(BigInt(n), 2);
  }
  return Buffer.concat([head, body]);
}

// Yields complete client frames ({opcode, text}) from a growing buffer.
function* parse(state) {
  for (;;) {
    const b = state.buf;
    if (b.length < 2) return;
    const opcode = b[0] & 0x0f;
    let len = b[1] & 0x7f;
    let off = 2;
    if (len === 126) {
      if (b.length < 4) return;
      len = b.readUInt16BE(2);
      off = 4;
    } else if (len === 127) {
      if (b.length < 10) return;
      len = Number(b.readBigUInt64BE(2));
      off = 10;
    }
    const masked = b[1] & 0x80;
    const mask = masked ? b.subarray(off, off + 4) : null;
    if (masked) off += 4;
    if (b.length < off + len) return;
    const payload = Buffer.from(b.subarray(off, off + len));
    if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
    state.buf = b.subarray(off + len);
    yield { opcode, text: payload.toString("utf8"), masked: !!mask };
  }
}

/**
 * startFakeT3({ initial }) -> { url, push(values), requests, connected, close() }
 * `initial` is the first Chunk for orchestration.subscribeThread.
 * `exitThread` answers subscribeThread with an immediate Exit (missing thread /
 * server not ready); `ticketStatus` overrides the websocket-ticket status.
 * `http`/`upgrades` count every HTTP request and websocket upgrade.
 * Hooks for transport tests: `onTicket(req, res, n)` may answer (or hold) a
 * ticket request itself and return true; `routes[path](req, res)` answers other
 * paths; `withholdClose` never answers a client close frame; `no101` accepts an
 * upgrade request but never completes the handshake. `tickets` logs
 * {at, auth} for every ticket request. `shell` answers subscribeShell.
 * `tls: {key, cert}` serves HTTPS/WSS. `beforeUpgrade(req)` runs before the
 * 101 is written; `closeFrames` counts client Close frames (`unmaskedClose`
 * those without a mask); `serverClose()` sends a Close (1000) to every socket.
 */
export async function startFakeT3({ initial, config = {}, exitThread = false, ticketStatus = 200, onTicket, routes = {},
  withholdClose = false, no101 = false, shell, port = 0, tls, beforeUpgrade }) {
  const tickets = [];
  const requestLog = [];
  const sockets = new Set();
  const requests = [];
  const commands = [];
  const counts = { http: 0, upgrades: 0, closeFrames: 0, unmaskedClose: 0 };
  let subscriber = null;
  let onSubscribe;
  const connected = new Promise((resolve) => (onSubscribe = resolve));
  const handler = (req, res) => {
    counts.http++;
    const route = routes[req.url.split("?")[0]];
    if (route) return route(req, res);
    if (req.method === "POST" && req.url.startsWith("/api/auth/websocket-ticket/rpc")) {
      tickets.push({ at: Date.now(), auth: req.headers.authorization });
      if (onTicket?.(req, res, tickets.length)) return;
      if (ticketStatus !== 200) {
        res.writeHead(ticketStatus);
        return res.end();
      }
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ ticket: "synthetic-ticket" }));
    }
    if (req.url.startsWith("/api/orchestration/shell")) {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ projects: [] }));
    }
    res.writeHead(404);
    res.end();
  };
  // withholdClose keeps the peer half-open after the client's EOF (TLS too).
  const server = tls ? https.createServer({ ...tls, allowHalfOpen: withholdClose }, handler) : http.createServer(handler);
  server.on("upgrade", (req, socket) => {
    counts.upgrades++;
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
    socket.on("error", () => {});
    if (withholdClose) socket.allowHalfOpen = true;
    if (no101) return;
    beforeUpgrade?.(req);
    const key = req.headers["sec-websocket-key"];
    const accept = crypto.createHash("sha1").update(key + GUID).digest("base64");
    socket.write(
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
        `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
    );
    const state = { buf: Buffer.alloc(0) };
    const send = (msg) => socket.write(frame(JSON.stringify(msg)));
    socket.on("data", (data) => {
      state.buf = Buffer.concat([state.buf, data]);
      for (const { opcode, text, masked } of parse(state)) {
        if (opcode === 8) {
          counts.closeFrames++;
          if (!masked) counts.unmaskedClose++;
          return withholdClose ? undefined : socket.end();
        }
        if (opcode !== 1) continue;
        const m = JSON.parse(text);
        if (m._tag === "Ack") counts.acks = (counts.acks || 0) + 1;
        if (m._tag !== "Request") continue;
        requests.push(m.tag);
        requestLog.push({ tag: m.tag, at: Date.now() });
        if (m.tag === "orchestration.dispatchCommand") commands.push(m.payload);
        if (m.tag === "orchestration.subscribeThread" && exitThread) {
          send({ _tag: "Exit", requestId: m.id, exit: { _tag: "Failure", cause: [] } });
        } else if (m.tag === "orchestration.subscribeShell" && shell) {
          send({ _tag: "Chunk", requestId: m.id, values: [{ kind: "snapshot", snapshot: shell }] });
        } else if (m.tag === "orchestration.subscribeThread") {
          subscriber = send;
          send({ _tag: "Chunk", requestId: m.id, values: initial });
          onSubscribe();
        } else {
          send({ _tag: "Exit", requestId: m.id, exit: { _tag: "Success", value: m.tag === "server.getConfig" ? config : {} } });
        }
      }
    });
  });
  const tcp = new Set(); // every open TCP connection, HTTP keep-alive included
  server.on("connection", (s) => {
    tcp.add(s);
    s.on("close", () => tcp.delete(s));
  });
  if (port === 3773) throw new Error("fake T3 refuses the live port");
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  return {
    url: `${tls ? "https" : "http"}://127.0.0.1:${server.address().port}`,
    requestLog,
    serverClose() {
      for (const s of sockets) s.write(Buffer.from([0x88, 0x02, 0x03, 0xe8]));
    },
    requests,
    commands,
    counts,
    tickets,
    connected,
    openConnections: () => tcp.size,
    openSockets: () => sockets.size,
    dropAll() {
      for (const s of sockets) s.destroy();
    },
    push(values) {
      assertSubscribed(subscriber);
      subscriber({ _tag: "Chunk", requestId: "1", values });
    },
    close() {
      for (const s of sockets) s.destroy();
      for (const s of tcp) s.destroy(); // held test responses must not block close
      return new Promise((resolve) => server.close(resolve));
    },
  };
}

function assertSubscribed(subscriber) {
  if (!subscriber) throw new Error("fake T3: no subscriber yet");
}
