import { StringDecoder } from "node:string_decoder";
import { isAbsolute, resolve } from "node:path";
import { BoardSession } from "./session.mjs";
import { DiagramRenderer } from "./renderer.mjs";
import { project } from "./view.mjs";
import { pinnedSource } from "./source.mjs";
const FRAME = 256 * 1024,
  TOTAL = 32 * 1024 * 1024;

export async function worker() {
  let session = null,
    renderer = null,
    bindings = {},
    width = 80,
    serial = 0,
    closed = false,
    requestId = null,
    renderToken = 0,
    diagrams = new Map();
  let buffer = "",
    discard = false,
    queue = Promise.resolve(),
    pending = 0,
    deferredPublish = false;
  const decoder = new StringDecoder("utf8");
  const send = (value) => {
    if (!closed)
      process.stdout.write(JSON.stringify({ v: 1, ...value }) + "\n");
  };
  const error = (id = null) =>
    send({
      id,
      type: "error",
      message: "Invalid, stale, unsupported or oversized board request",
    });
  const theme = (t) => ({
    id: t.id,
    tokens: Object.fromEntries(
      Object.entries(t.tokens).map(([k, v]) => [
        k,
        typeof v === "string" && /^#[a-f0-9]{6}$/i.test(v) ? v : null,
      ]),
    ),
  });
  const publish = () => {
    if (!session?.snapshot || closed) return;
    if (process.stdout.writableLength > TOTAL) {
      deferredPublish = true;
      return;
    }
    const snap = session.snapshot,
      doc = snap.document,
      view = project(snap, { diagrams });
    const payload = JSON.stringify({
      path: session.path,
      generation: snap.generation,
      hash: doc?.hash ?? null,
      stale: snap.stale,
      rows: view.rows,
      mapping: view.mapping,
      theme: theme(snap.theme),
      sections:
        doc?.valid && !doc.opaque
          ? doc.blocks
              .filter((b) => b.kind === "heading" && b.level === 2)
              .map((b) => ({ id: b.id, line: b.line }))
          : [],
    });
    if (Buffer.byteLength(payload) > TOTAL) {
      error(requestId);
      return;
    }
    const seq = ++serial;
    // Split JSON string at code-point boundaries; a chunk is never interpreted
    // independently. Publish only after end and count/byte/generation checks.
    const chunks = [];
    let chunk = "",
      bytes = 0;
    for (const ch of payload) {
      const n = Buffer.byteLength(ch);
      if (bytes + n > 48 * 1024) {
        chunks.push(chunk);
        chunk = "";
        bytes = 0;
      }
      chunk += ch;
      bytes += n;
    }
    if (chunk) chunks.push(chunk);
    send({
      id: requestId,
      type: "begin",
      seq,
      generation: snap.generation,
      count: chunks.length,
      bytes: Buffer.byteLength(payload),
    });
    chunks.forEach((data, index) =>
      send({ id: requestId, type: "chunk", seq, index, data }),
    );
    send({ id: requestId, type: "end", seq, generation: snap.generation });
  };
  const cleanup = () => {
    if (closed) return;
    session?.close();
    renderer?.close();
    closed = true;
    process.stdin.pause();
    process.stdin.removeAllListeners("data");
    process.stdin.destroy();
  };
  const refreshRendering = (snap) => {
    const token = ++renderToken,
      doc = snap.document;
    diagrams = new Map();
    publish();
    if (!doc?.valid || doc.opaque) return;
    (async () => {
      for (const b of doc.blocks.filter((b) => b.kind === "mermaid")) {
        const result = await renderer.render(b.content, {
          width,
          theme: JSON.stringify(snap.theme),
          revision: doc.hash,
        });
        if (
          closed ||
          token !== renderToken ||
          session?.snapshot?.document?.hash !== doc.hash
        )
          return;
        diagrams.set(b.id, result);
        publish();
      }
    })();
  };
  const handle = async (req) => {
    if (
      !req ||
      req.v !== 1 ||
      !["open", "refresh", "render", "source", "close"].includes(req.op) ||
      !["string", "number"].includes(typeof req.id)
    ) {
      error(req?.id);
      return;
    }
    if (req.op === "close") {
      send({ id: req.id, type: "closed" });
      cleanup();
      return;
    }
    if (req.op === "open") {
      if (
        typeof req.path !== "string" ||
        !isAbsolute(req.path) ||
        req.path.includes("\0")
      ) {
        error(req.id);
        return;
      }
      const b = req.bindings ?? {};
      if (
        !b ||
        typeof b !== "object" ||
        Array.isArray(b) ||
        Object.entries(b).some(
          ([k, v]) =>
            !/^[a-z][a-z0-9-]{0,63}$/.test(k) ||
            typeof v !== "string" ||
            !isAbsolute(v),
        )
      ) {
        error(req.id);
        return;
      }
      session?.close();
      renderer?.close();
      bindings = b;
      width = Math.max(20, Math.min(400, Number(req.width) || 80));
      requestId = req.id;
      diagrams = new Map();
      renderer = new DiagramRenderer();
      session = new BoardSession({ path: resolve(req.path) });
      session.subscribe(refreshRendering);
      session.start();
      return;
    }
    if (!session?.snapshot) {
      error(req.id);
      return;
    }
    requestId = req.id;
    if (req.op === "refresh") {
      await session.retry();
      publish();
      return;
    }
    if (req.op === "render") {
      width = Math.max(20, Math.min(400, Number(req.width) || 80));
      refreshRendering(session.snapshot);
      return;
    }
    if (req.op === "source") {
      const doc = session.snapshot.document;
      if (
        session.snapshot.stale ||
        !doc?.valid ||
        doc.opaque ||
        req.expectedHash !== doc.hash
      ) {
        error(req.id);
        return;
      }
      const block = doc.blocks.find(
        (b) => b.id === req.block && b.kind === "wb-source",
      );
      if (!block) {
        error(req.id);
        return;
      }
      const owner = session,
        value = await pinnedSource(block.record, bindings);
      if (
        owner !== session ||
        doc.hash !== session.snapshot.document?.hash ||
        session.snapshot.stale
      ) {
        error(req.id);
        return;
      }
      // Huge line ranges remain bounded; source response must fit one frame.
      const reply = {
        id: req.id,
        type: "source",
        hash: doc.hash,
        block: block.id,
        value,
      };
      if (Buffer.byteLength(JSON.stringify(reply)) > FRAME - 100) {
        error(req.id);
        return;
      }
      send(reply);
    }
  };
  const line = (raw) => {
    if (!raw.trim()) return;
    if (Buffer.byteLength(raw) > FRAME || pending >= 64) {
      error();
      return;
    }
    let req;
    try {
      req = JSON.parse(raw);
    } catch {
      error();
      return;
    }
    pending++;
    queue = queue
      .then(() => {
        if (!closed) return handle(req);
      })
      .catch(() => error(req.id))
      .finally(() => pending--);
  };
  process.stdin.on("data", (bytes) => {
    buffer += decoder.write(bytes);
    let at;
    while ((at = buffer.indexOf("\n")) >= 0) {
      const raw = buffer.slice(0, at);
      buffer = buffer.slice(at + 1);
      if (discard) discard = false;
      else line(raw);
    }
    if (Buffer.byteLength(buffer) > FRAME) {
      buffer = "";
      discard = true;
      error();
    }
  });
  process.stdin.once("end", () => {
    decoder.end();
    void queue.finally(cleanup);
  });
  process.stdout.on("drain", () => {
    if (deferredPublish) {
      deferredPublish = false;
      publish();
    }
  });
  process.stdout.once("error", cleanup);
  process.once("SIGINT", cleanup);
  process.once("SIGTERM", cleanup);
  await new Promise((done) => {
    const tick = setInterval(() => {
      if (closed) {
        clearInterval(tick);
        done();
      }
    }, 25);
  });
}
