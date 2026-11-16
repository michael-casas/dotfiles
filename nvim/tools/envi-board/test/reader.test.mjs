import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  readFileSync,
  writeFileSync,
  renameSync,
  unlinkSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
const main = new URL("../main.mjs", import.meta.url).pathname;
const example = readFileSync(
  new URL("./fixtures/example.wb.md", import.meta.url),
);
const cli = (...args) =>
  spawnSync(process.execPath, [main, ...args], {
    encoding: "utf8",
    timeout: 10000,
  });

test("CLI render always escapes terminal bytes and preserves original Mermaid source", () => {
  const dir = mkdtempSync(join(tmpdir(), "board-"));
  try {
    const path = join(dir, "demo.wb.md");
    writeFileSync(
      path,
      Buffer.concat([example, Buffer.from("\n\x1b]52;c;hostile\x07\n")]),
    );
    const before = statSync(path);
    const r = cli("render", "--", path);
    assert.equal(r.status, 0, r.stderr);
    assert.ok(!r.stdout.includes("\x1b"));
    assert.match(r.stdout, /U\+001B/);
    assert.match(r.stdout, /flowchart LR/);
    assert.equal(statSync(path).mtimeMs, before.mtimeMs);
  } finally {
    rmSync(dir, { recursive: true });
  }
});
test("CLI strict unresolved references, unknown switches and non-TTY interactive refusal", () => {
  const path = new URL("./fixtures/example.wb.md", import.meta.url).pathname;
  assert.equal(cli("validate", "--json", "--", path).status, 0);
  assert.equal(cli("validate", "--json", "--strict", "--", path).status, 1);
  assert.equal(cli("open", "--", path).status, 2);
  assert.equal(cli("validate", "--unrecognized", "--", path).status, 2);
});
test("session retains last good marked STALE on invalid/delete, recovers atomic saves, suppresses no-op, closes twice", async () => {
  const { BoardSession } = await import("../session.mjs");
  const dir = mkdtempSync(join(tmpdir(), "board-")),
    path = join(dir, "demo.wb.md");
  writeFileSync(path, example);
  const s = new BoardSession({ path });
  let count = 0;
  const events = [];
  s.subscribe((x) => {
    count++;
    events.push(x);
  });
  try {
    await s.refresh();
    const hash = s.snapshot.document.hash;
    await s.refresh();
    assert.equal(count, 1);
    writeFileSync(path, "broken");
    await s.refresh();
    assert.equal(s.snapshot.stale, true);
    assert.equal(s.snapshot.document.hash, hash);
    unlinkSync(path);
    await s.refresh();
    assert.equal(s.snapshot.stale, true);
    writeFileSync(
      path + ".tmp",
      example.toString().replace("# File-first board viewer", "# New title"),
    );
    renameSync(path + ".tmp", path);
    await s.refresh();
    assert.equal(s.snapshot.stale, false);
    assert.notEqual(s.snapshot.document.hash, hash);
    s.close();
    s.close();
    await s.refresh();
    assert.equal(s.closed, true);
  } finally {
    s.close();
    rmSync(dir, { recursive: true });
  }
});
test("directory watcher sees atomic replacement/deletion/recreation; initial invalid is raw safe source", async () => {
  const { BoardSession } = await import("../session.mjs");
  const dir = mkdtempSync(join(tmpdir(), "board-")),
    path = join(dir, "demo.wb.md");
  writeFileSync(path, "invalid\x1b");
  const s = new BoardSession({ path });
  s.start();
  const wait = async (fn) => {
    for (let i = 0; i < 100; i++) {
      if (fn()) return;
      await new Promise((r) => setTimeout(r, 20));
    }
    assert.fail("watch event not published");
  };
  try {
    await wait(() => s.snapshot);
    assert.equal(s.snapshot.document.valid, false);
    writeFileSync(path + ".tmp", example);
    renameSync(path + ".tmp", path);
    await wait(() => s.snapshot.document.valid);
    unlinkSync(path);
    await wait(() => s.snapshot.stale);
    writeFileSync(path, example);
    await wait(() => !s.snapshot.stale);
  } finally {
    s.close();
    rmSync(dir, { recursive: true });
  }
});
test("Ink viewport is bounded at short/80x24/wide sizes, safe and horizontally pans graph/source", async () => {
  const { viewport } = await import("../view.mjs");
  for (const [width, height] of [
    [80, 24],
    [150, 40],
    [20, 5],
  ]) {
    const rows = viewport(["x".repeat(1000), "🙂".repeat(100), "last"], {
      width,
      height,
      top: 0,
      left: 0,
    });
    assert.ok(rows.length < height);
    assert.ok(rows.every((s) => Array.from(s).length <= width));
  }
  assert.equal(
    viewport(["abcdef"], { width: 3, height: 5, left: 2 })[0],
    "cde",
  );
});

test("public render produces approximate graph AND original source; render-check diagnoses unsupported separately", () => {
  const path = new URL("./fixtures/example.wb.md", import.meta.url).pathname;
  const r = cli("render", "--", path);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /approximate text/);
  assert.match(r.stdout, /┌|─/);
  assert.match(r.stdout, /flowchart LR/);
  const check = cli("validate", "--json", "--render-check", "--", path);
  assert.equal(check.status, 0, check.stdout);
  assert.ok(
    JSON.parse(check.stdout).renderChecks.every(
      (x) => x.kind === "text-approximate",
    ),
  );
});

test("FIFO board input is refused promptly rather than blocking the safe reader", async () => {
  const { execFileSync } = await import("node:child_process");
  const { readBoard } = await import("../session.mjs");
  const dir = mkdtempSync(join(tmpdir(), "board-fifo-"));
  try {
    const path = join(dir, "pipe.wb.md");
    execFileSync("mkfifo", [path]);
    await assert.rejects(readBoard(path));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("initial missing file gives a safe snapshot and can manually recover without changing source", async () => {
  const { BoardSession } = await import("../session.mjs");
  const dir = mkdtempSync(join(tmpdir(), "board-missing-")),
    path = join(dir, "new.wb.md");
  const s = new BoardSession({ path });
  try {
    await s.refresh();
    assert.equal(s.snapshot.document, null);
    assert.equal(s.snapshot.stale, true);
    writeFileSync(path, example);
    await s.retry();
    assert.equal(s.snapshot.stale, false);
    assert.equal(s.snapshot.document.valid, true);
  } finally {
    s.close();
    rmSync(dir, { recursive: true });
  }
});

test("projection splits all multiline metadata/status into physical rows with stable mapping", async () => {
  const { parseBoard } = await import("../document.mjs");
  const { project, viewport } = await import("../view.mjs");
  const bytes = Buffer.from(
    example
      .toString()
      .replace('"author": "reviewer-demo"', '"author": "reviewer\\ndemo"')
      .replace(
        '"label": "Existing clipboard option; evidence pin, not board implementation"',
        '"label": "Evidence\\nlabel\\rnext\\r\\nlast"',
      ),
  );
  const document = parseBoard(bytes);
  assert.equal(document.valid, true);
  const view = project({
    document,
    stale: true,
    error: "failed\nretry\rnow",
    watchError: "watch\r\nretry",
  });
  assert.ok(
    view.rows.every((row) => !/[\r\n]/.test(row)),
    "every projected row is one physical line",
  );
  assert.equal(view.rows.length, view.mapping.length);
  const author = view.rows.indexOf("reviewer");
  assert.ok(author >= 0);
  assert.equal(view.rows[author + 1], "demo:");
  assert.equal(view.mapping[author].id, "thread-fallback");
  assert.deepEqual(view.mapping[author], view.mapping[author + 1]);
  const label = view.rows.indexOf("[source source-options] Evidence");
  assert.deepEqual(view.rows.slice(label + 1, label + 4), [
    "label",
    "next",
    "last",
  ]);
  for (const item of view.mapping.slice(label, label + 4))
    assert.equal(item.id, "source-options");
  assert.ok(viewport(view.rows, { width: 80, height: 24 }).length <= 22);
});

test("watch failure is published on unchanged bytes and manual retry publishes recovery", async () => {
  const { BoardSession } = await import("../session.mjs");
  const { project } = await import("../view.mjs");
  const dir = mkdtempSync(join(tmpdir(), "board-watch-error-")),
    path = join(dir, "demo.wb.md");
  writeFileSync(path, example);
  const session = new BoardSession({ path }),
    events = [];
  session.subscribe((s) => events.push(s));
  session.start();
  try {
    await session.refresh();
    const initial = session.snapshot;
    session.watcher.emit("error", new Error("synthetic watch error"));
    await session.refresh();
    assert.ok(
      session.snapshot.watchError,
      "watch failure must be visible even with an unchanged hash",
    );
    assert.ok(session.snapshot.generation > initial.generation);
    assert.ok(
      project(session.snapshot).rows.some((r) =>
        r.includes("Watch unavailable"),
      ),
    );
    const failed = session.snapshot;
    await session.retry();
    assert.equal(session.snapshot.watchError, null);
    assert.ok(session.snapshot.generation > failed.generation);
    assert.equal(session.snapshot.document.hash, initial.document.hash);
    assert.equal(
      events.length,
      3,
      "initial, failed watcher, recovered watcher; no duplicate hash notifications",
    );
  } finally {
    session.close();
    rmSync(dir, { recursive: true });
  }
});
