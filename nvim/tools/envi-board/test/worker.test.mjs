import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
const main = new URL("../main.mjs", import.meta.url).pathname;
function client() {
  const child = spawn(process.execPath, [main, "worker"], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  let buffer = "",
    frames = [],
    errors = "";
  child.stdout.on("data", (b) => {
    buffer += b;
    let end;
    while ((end = buffer.indexOf("\n")) >= 0) {
      frames.push(JSON.parse(buffer.slice(0, end)));
      buffer = buffer.slice(end + 1);
    }
  });
  child.stderr.on("data", (b) => {
    errors += b;
  });
  const until = async (predicate) => {
    for (let i = 0; i < 300; i++) {
      const value = predicate(frames);
      if (value) return value;
      if (child.exitCode !== null)
        assert.fail("worker exited before reply: " + errors);
      await new Promise((r) => setTimeout(r, 10));
    }
    assert.fail("worker response deadline");
  };
  const send = (o) => child.stdin.write(JSON.stringify(o) + "\n");
  return { child, send, until, frames };
}
const decode = (frames, end) =>
  JSON.parse(
    frames
      .filter((f) => f.type === "chunk" && f.seq === end.seq)
      .sort((a, b) => a.index - b.index)
      .map((f) => f.data)
      .join(""),
  );
test("private stdio open supports split UTF8, complete bounded snapshots, source denial and EOF cleanup", async () => {
  const c = client(),
    path = new URL("./fixtures/example.wb.md", import.meta.url).pathname;
  try {
    const frame = Buffer.from(
      JSON.stringify({ v: 1, id: "open-🙂", op: "open", path, width: 80 }) +
        "\n",
    );
    const at = frame.indexOf(Buffer.from("🙂"));
    c.child.stdin.write(frame.subarray(0, at + 1));
    c.child.stdin.write(frame.subarray(at + 1));
    const end = await c.until((fs) => fs.find((f) => f.type === "end"));
    let data = decode(c.frames, end);
    assert.ok(data.rows.some((s) => s.includes("flowchart LR")));
    assert.ok(data.mapping.some((m) => m.id === "source-options"));
    assert.equal(data.path, path);
    assert.ok(
      c.frames.every((f) => Buffer.byteLength(JSON.stringify(f)) < 256 * 1024),
    );
    c.send({
      v: 1,
      id: 2,
      op: "source",
      block: "source-options",
      expectedHash: data.hash,
    });
    const source = await c.until((fs) =>
      fs.find((f) => f.type === "source" && f.id === 2),
    );
    assert.equal(source.value.state, "unavailable");
    c.send({
      v: 1,
      id: 3,
      op: "source",
      block: "source-options",
      expectedHash: "old",
    });
    assert.equal(
      (await c.until((fs) => fs.find((f) => f.id === 3))).type,
      "error",
    );
    c.child.stdin.end();
    await new Promise((resolve) => c.child.once("exit", resolve));
    assert.equal(c.child.exitCode, 0);
  } finally {
    c.child.stdin.destroy();
    if (c.child.exitCode === null) c.child.kill();
  }
});
test("worker rejects malformed, oversized and executable requests with safe errors; initial invalid remains visible", async () => {
  const c = client(),
    dir = mkdtempSync(join(tmpdir(), "board-worker-"));
  try {
    const path = join(dir, "bad.wb.md");
    writeFileSync(path, "broken\x1b🙂");
    c.child.stdin.write("not json\n");
    await c.until((fs) => fs.find((f) => f.type === "error"));
    c.send({ v: 1, id: 9, op: "exec", command: "never-run" });
    assert.equal(
      (await c.until((fs) => fs.find((f) => f.id === 9))).type,
      "error",
    );
    c.send({ v: 1, id: 10, op: "open", path });
    const end = await c.until((fs) => fs.find((f) => f.type === "end"));
    const data = decode(c.frames, end);
    assert.ok(data.rows.some((s) => s.includes("U+001B")));
    assert.equal(data.stale, true);
    c.child.stdin.write("x".repeat(256 * 1024 + 1) + "\n");
    await c.until((fs) => fs.filter((f) => f.type === "error").length >= 3);
    c.send({ v: 1, id: 11, op: "close" });
    await new Promise((resolve) => c.child.once("exit", resolve));
    assert.equal(c.child.exitCode, 0);
  } finally {
    c.child.stdin.destroy();
    if (c.child.exitCode === null) c.child.kill();
    rmSync(dir, { recursive: true });
  }
});
