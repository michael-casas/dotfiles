import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
const main = new URL("../main.mjs", import.meta.url).pathname;
function client(env = {}) {
  const child = spawn(process.execPath, [main, "worker"], {
    stdio: ["pipe", "pipe", "pipe"],
    env: { ...process.env, ...env },
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

test("worker echoes the requested absolute path even when internal resolution normalizes missing/../", async () => {
  const c = client(),
    dir = mkdtempSync(join(tmpdir(), "board-worker-path-"));
  try {
    writeFileSync(
      join(dir, "ok.wb.md"),
      readFileSync(new URL("./fixtures/example.wb.md", import.meta.url)),
    );
    const path = dir + "/nosuch/../ok.wb.md";
    c.send({ v: 1, id: 20, op: "open", path });
    const end = await c.until((fs) =>
      fs.find((f) => f.type === "end" && f.id === 20),
    );
    const data = decode(c.frames, end);
    assert.equal(
      data.path,
      path,
      "reply identity must not change during internal path resolution",
    );
    assert.ok(data.rows.some((s) => s.includes("flowchart LR")));
    c.child.stdin.end();
    await new Promise((resolve) => c.child.once("exit", resolve));
    assert.equal(c.child.exitCode, 0);
  } finally {
    c.child.stdin.destroy();
    if (c.child.exitCode === null) c.child.kill();
    rmSync(dir, { recursive: true });
  }
});

test("worker labels pending renders and retains completed diagrams across resize and theme changes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "board-worker-render-"));
  const hubFile = join(dir, "theme.json");
  const hub = JSON.parse(
    readFileSync(new URL("../../../../theme/theme.json", import.meta.url)),
  );
  // The child gets its own theme file through the test client's explicit env.
  // Never modify the host's actual hub.
  writeFileSync(hubFile, JSON.stringify(hub));
  const workerClient = client({ ENVI_THEME_FILE: hubFile });
  try {
    const path = new URL("./fixtures/example.wb.md", import.meta.url).pathname;
    workerClient.send({ v: 1, id: 30, op: "open", path });
    const first = await workerClient.until((fs) =>
      fs.find((f) => f.type === "end"),
    );
    const initial = decode(workerClient.frames, first);
    assert.ok(
      initial.rows.some((s) => s.includes("rendering…")),
      "in-flight render is explicitly labeled",
    );
    const complete = await workerClient.until((fs) =>
      fs
        .filter((f) => f.type === "end")
        .map((e) => decode(fs, e))
        .find(
          (d) =>
            d.rows.filter((s) => s.includes("approximate text")).length === 2,
        ),
    );
    const previous = workerClient.frames.length;
    workerClient.send({ v: 1, id: 31, op: "render", width: 140 });
    // Invalid source provides an ordered barrier without requesting a snapshot.
    workerClient.send({ v: 1, id: 32, op: "source", expectedHash: "old" });
    await workerClient.until((fs) =>
      fs.find((f) => f.type === "error" && f.id === 32),
    );
    assert.equal(
      workerClient.frames.slice(previous).filter((f) => f.type === "begin")
        .length,
      0,
      "settled resize emits no snapshot",
    );
    hub.active = "gruvbox-dark";
    writeFileSync(hubFile, JSON.stringify(hub));
    const repainted = await workerClient.until((fs) =>
      fs
        .filter((f) => f.type === "end")
        .map((e) => decode(fs, e))
        .find((d) => d.theme.id === "gruvbox-dark"),
    );
    assert.equal(
      repainted.rows.filter((s) => s.includes("approximate text")).length,
      2,
      "theme-only update retains graphs",
    );
    for (const end of workerClient.frames
      .slice(previous)
      .filter((f) => f.type === "end"))
      assert.equal(
        decode(workerClient.frames, end).rows.filter((s) =>
          s.includes("approximate text"),
        ).length,
        2,
      );
    assert.equal(repainted.hash, complete.hash);
    workerClient.child.stdin.end();
    await new Promise((resolve) => workerClient.child.once("exit", resolve));
    assert.equal(workerClient.child.exitCode, 0);
  } finally {
    workerClient.child.stdin.destroy();
    if (workerClient.child.exitCode === null) workerClient.child.kill();
    rmSync(dir, { recursive: true });
  }
});

test("settled success and failure skip renderer/Ruby and frames on resize; theme publishes only once", async () => {
  const dir = mkdtempSync(join(tmpdir(), "board-worker-noop-"));
  const log = join(dir, "jobs.log"),
    path = join(dir, "demo.wb.md"),
    hubFile = join(dir, "theme.json");
  const hub = JSON.parse(
    readFileSync(new URL("../../../../theme/theme.json", import.meta.url)),
  );
  hub.active = "nord";
  writeFileSync(hubFile, JSON.stringify(hub));
  writeFileSync(log, "");
  const example = readFileSync(
    new URL("./fixtures/example.wb.md", import.meta.url),
    "utf8",
  );
  // One success and one allowlisted diagram rejected by strict merminal.
  writeFileSync(
    path,
    example.replace(
      /sequenceDiagram[\s\S]*?```/,
      "flowchart LR\n A[First] --> B\n A[Second] --> C\n```",
    ),
  );
  const c = client({
    ENVI_THEME_FILE: hubFile,
    ENVI_BOARD_TEST_RENDER_LOG: log,
    NODE_OPTIONS: `--import=${new URL("./fixtures/render-probe.mjs", import.meta.url).href}`,
  });
  const jobs = () => readFileSync(log, "utf8").trim().split("\n");
  try {
    c.send({ v: 1, id: 40, op: "open", path });
    await c.until((fs) =>
      fs
        .filter((f) => f.type === "end")
        .map((e) => decode(fs, e))
        .find(
          (d) =>
            d.rows.some((s) => s.includes("approximate text")) &&
            d.rows.some((s) => s.includes("partial output discarded")),
        ),
    );
    assert.equal(jobs().filter((s) => s === "ruby").length, 2);
    const beforeJobs = jobs(),
      beforeFrames = c.frames.length;
    for (let id = 41; id <= 45; id++)
      c.send({ v: 1, id, op: "render", width: id * 3 });
    c.send({ v: 1, id: 46, op: "source", expectedHash: "old" });
    await c.until((fs) => fs.find((f) => f.type === "error" && f.id === 46));
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(
      c.frames.slice(beforeFrames).filter((f) => f.type === "begin").length,
      0,
      "resize must not repaint an unchanged board",
    );
    assert.deepEqual(
      jobs(),
      beforeJobs,
      "resize must call neither renderer nor Ruby",
    );
    hub.active = "gruvbox-dark";
    writeFileSync(hubFile, JSON.stringify(hub));
    await c.until((fs) =>
      fs
        .slice(beforeFrames)
        .filter((f) => f.type === "end")
        .map((e) => decode(fs, e))
        .find((d) => d.theme.id === "gruvbox-dark"),
    );
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(
      c.frames.slice(beforeFrames).filter((f) => f.type === "begin").length,
      1,
      "theme sends only the changed palette",
    );
    assert.deepEqual(
      jobs(),
      beforeJobs,
      "theme must call neither renderer nor Ruby",
    );
    c.child.stdin.end();
    await new Promise((resolve) => c.child.once("exit", resolve));
    assert.equal(c.child.exitCode, 0);
  } finally {
    c.child.stdin.destroy();
    if (c.child.exitCode === null) c.child.kill();
    rmSync(dir, { recursive: true });
  }
});

test("worker resize and R retry only transient failures on an unchanged board", async () => {
  for (const op of ["render", "refresh"]) {
    const dir = mkdtempSync(join(tmpdir(), "board-worker-retry-"));
    const log = join(dir, "jobs.log");
    writeFileSync(log, "");
    const c = client({
      ENVI_BOARD_TEST_RENDER_LOG: log,
      ENVI_BOARD_TEST_TIMEOUT_ONCE: "1",
      NODE_OPTIONS: `--import=${new URL("./fixtures/render-probe.mjs", import.meta.url).href}`,
    });
    const jobs = () => readFileSync(log, "utf8").trim().split("\n");
    try {
      c.send({
        v: 1,
        id: 70,
        op: "open",
        path: new URL("./fixtures/example.wb.md", import.meta.url).pathname,
      });
      await c.until((fs) =>
        fs
          .filter((f) => f.type === "end")
          .map((e) => decode(fs, e))
          .find(
            (d) =>
              d.rows.some((s) => s.includes("renderer time/output limit")) &&
              d.rows.some((s) => s.includes("approximate text")),
          ),
      );
      assert.equal(jobs().filter((s) => s === "ruby").length, 2);
      c.send({ v: 1, id: 71, op, width: 120 });
      await c.until((fs) =>
        fs
          .filter((f) => f.type === "end" && f.id === 71)
          .map((e) => decode(fs, e))
          .find(
            (d) =>
              d.rows.filter((s) => s.includes("approximate text")).length === 2,
          ),
      );
      assert.equal(
        jobs().filter((s) => s === "render").length,
        3,
        "retry only failed diagram",
      );
      assert.equal(
        jobs().filter((s) => s === "ruby").length,
        3,
        "retry starts a real Ruby job",
      );
      const before = c.frames.length;
      c.send({ v: 1, id: 72, op, width: 90 });
      c.send({ v: 1, id: 73, op: "source", expectedHash: "old" });
      await c.until((fs) => fs.find((f) => f.type === "error" && f.id === 73));
      assert.equal(
        c.frames.slice(before).filter((f) => f.type === "begin").length,
        0,
      );
      assert.equal(jobs().filter((s) => s === "render").length, 3);
      c.child.stdin.end();
      await new Promise((resolve) => c.child.once("exit", resolve));
      assert.equal(c.child.exitCode, 0);
    } finally {
      c.child.stdin.destroy();
      if (c.child.exitCode === null) c.child.kill();
      rmSync(dir, { recursive: true });
    }
  }
});
