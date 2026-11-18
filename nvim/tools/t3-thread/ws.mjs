// Minimal RFC 6455 client over node:http that owns its TCP socket. The global
// WebSocket cannot be torn down without the peer's close reply, and a stopping
// T3 server waits on every open client socket; close() here sends a close frame
// and releases the socket at once, whatever the peer does.
// Interface: readyState, send(text), close(), onopen, onmessage({data}), onclose.
import crypto from "node:crypto";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import tls from "node:tls";

export const OPEN = 1;
const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function frame(opcode, payload) {
  const n = payload.length;
  const head = n < 126 ? Buffer.from([0x80 | opcode, 0x80 | n])
    : n < 65536 ? Buffer.from([0x80 | opcode, 0x80 | 126, n >> 8, n & 255])
    : Buffer.concat([Buffer.from([0x80 | opcode, 0x80 | 127]), Buffer.alloc(8)]);
  if (n >= 65536) head.writeBigUInt64BE(BigInt(n), 2);
  const mask = crypto.randomBytes(4);
  const body = Buffer.from(payload);
  for (let i = 0; i < n; i++) body[i] ^= mask[i % 4];
  return Buffer.concat([head, mask, body]);
}

export function connectWs(url, { signal } = {}) {
  const ws = { readyState: 0 };
  const key = crypto.randomBytes(16).toString("base64");
  const target = url.replace(/^ws/, "http");
  let socket, raw, closing, buffer = Buffer.alloc(0), parts = [], done = false;
  // WSS runs TLS over our own TCP socket (raw), so a release can reset it.
  const secure = target.startsWith("https:");
  const req = (secure ? https : http).request(target, { agent: secure ? undefined : false, headers: {
    Connection: "Upgrade", Upgrade: "websocket", "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": key },
    ...(secure && { createConnection: (o) => tls.connect({ ...o, socket: (raw = net.connect(o.port, o.hostname || o.host)) }) }) });
  // A reset (RST) is noticed by a peer that has not read EOF; only TCP can do it.
  const drop = (s) => {
    try { (raw ?? s).resetAndDestroy(); } catch {} // TCP reset first (under TLS too) ...
    s.destroy(); // ... then the outer socket; for plain TCP this is a no-op
  };
  const finish = () => {
    if (done) return;
    done = true;
    const upgraded = ws.readyState === OPEN;
    ws.readyState = 3;
    socket?.destroy();
    if (!upgraded) req.destroy(); // after an upgrade it would take the socket with it
    signal?.removeEventListener("abort", ws.close);
    ws.onclose?.();
  };
  function read(chunk) {
    buffer = Buffer.concat([buffer, chunk]);
    while (!done && buffer.length >= 2) {
      let len = buffer[1] & 127, at = 2;
      if (len === 126) { if (buffer.length < 4) return; len = buffer.readUInt16BE(2); at = 4; }
      else if (len === 127) { if (buffer.length < 10) return; len = Number(buffer.readBigUInt64BE(2)); at = 10; }
      const mask = buffer[1] & 128 ? buffer.subarray(at, (at += 4)) : null;
      if (buffer.length < at + len) return;
      const opcode = buffer[0] & 15, fin = buffer[0] & 128;
      const data = Buffer.from(buffer.subarray(at, at + len));
      buffer = buffer.subarray(at + len);
      if (mask) for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
      if (opcode === 8) { // peer-initiated: one masked Close back, then wait (bounded) for its TCP close
        closing = socket;
        socket = undefined;
        closing.write(frame(8, data.subarray(0, 2)));
        setTimeout(ws.release, 1000).unref();
        return finish();
      }
      if (opcode === 9) socket.write(frame(10, data));
      if (opcode >= 8) continue;
      parts.push(data);
      if (fin) {
        const text = Buffer.concat(parts).toString("utf8");
        parts = [];
        ws.onmessage?.({ data: text });
      }
    }
  }
  req.on("upgrade", (res, s, head) => {
    socket = s;
    if (done) return s.destroy();
    if (res.headers["sec-websocket-accept"] !== crypto.createHash("sha1").update(key + GUID).digest("base64"))
      return finish();
    s.setNoDelay(true);
    s.on("data", read);
    s.on("close", finish);
    s.on("error", finish);
    ws.readyState = OPEN;
    ws.onopen?.();
    if (head.length) read(head);
  });
  req.on("response", (res) => { res.resume(); finish(); });
  req.on("error", finish);
  req.end();
  ws.send = (text) => { if (ws.readyState === OPEN) socket.write(frame(1, Buffer.from(text))); };
  // Closed for the caller at once. An open socket sends a close frame (1000)
  // and is reset 100 ms later unless the peer has closed by then (no FIN first:
  // a peer that has read our EOF stops reading and would miss the reset). A
  // pending handshake is reset straight away.
  ws.close = () => {
    if (done) return;
    const s = socket ?? req.socket;
    socket = undefined;
    try {
      if (ws.readyState === OPEN) {
        s.write(frame(8, Buffer.from([0x03, 0xe8])));
        setTimeout(() => s.destroyed || drop(s), 100).unref();
      } else if (s && !s.destroyed) drop(s);
    } finally {
      finish(); // retired whatever the teardown did
    }
  };
  // A socket still closing after a peer's Close (see above): release it now.
  ws.release = () => { if (closing && !closing.destroyed) drop(closing); closing = undefined; };
  if (signal?.aborted) queueMicrotask(ws.close);
  else signal?.addEventListener("abort", ws.close, { once: true });
  return ws;
}
