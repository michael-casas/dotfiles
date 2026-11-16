// A local, synthetic stand-in for the T3 server: just enough HTTP and
// WebSocket (RFC 6455 text frames) for main.mjs to subscribe to one thread.
// Binds 127.0.0.1 on an ephemeral port; never talks to a real T3 server.
import http from "node:http";
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
    yield { opcode, text: payload.toString("utf8") };
  }
}

/**
 * startFakeT3({ initial }) -> { url, push(values), requests, connected, close() }
 * `initial` is the first Chunk for orchestration.subscribeThread.
 */
export async function startFakeT3({ initial }) {
  const sockets = new Set();
  const requests = [];
  const commands = [];
  let subscriber = null;
  let onSubscribe;
  const connected = new Promise((resolve) => (onSubscribe = resolve));
  const server = http.createServer((req, res) => {
    if (req.method === "POST" && req.url.startsWith("/api/auth/websocket-ticket/rpc")) {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ ticket: "synthetic-ticket" }));
    }
    if (req.url.startsWith("/api/orchestration/shell")) {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ projects: [] }));
    }
    res.writeHead(404);
    res.end();
  });
  server.on("upgrade", (req, socket) => {
    const key = req.headers["sec-websocket-key"];
    const accept = crypto.createHash("sha1").update(key + GUID).digest("base64");
    socket.write(
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
        `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
    );
    sockets.add(socket);
    const state = { buf: Buffer.alloc(0) };
    const send = (msg) => socket.write(frame(JSON.stringify(msg)));
    socket.on("data", (data) => {
      state.buf = Buffer.concat([state.buf, data]);
      for (const { opcode, text } of parse(state)) {
        if (opcode === 8) return socket.end();
        if (opcode !== 1) continue;
        const m = JSON.parse(text);
        if (m._tag !== "Request") continue;
        requests.push(m.tag);
        if (m.tag === "orchestration.dispatchCommand") commands.push(m.payload);
        if (m.tag === "orchestration.subscribeThread") {
          subscriber = send;
          send({ _tag: "Chunk", requestId: m.id, values: initial });
          onSubscribe();
        } else {
          send({ _tag: "Exit", requestId: m.id, exit: { _tag: "Success", value: {} } });
        }
      }
    });
    socket.on("close", () => sockets.delete(socket));
    socket.on("error", () => {});
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}`,
    requests,
    commands,
    connected,
    push(values) {
      assertSubscribed(subscriber);
      subscriber({ _tag: "Chunk", requestId: "1", values });
    },
    close() {
      for (const s of sockets) s.destroy();
      return new Promise((resolve) => server.close(resolve));
    },
  };
}

function assertSubscribed(subscriber) {
  if (!subscriber) throw new Error("fake T3: no subscriber yet");
}
