// BATDD-T3STRIKE-04 / -05: the real main.mjs client on a real PTY (python
// pty-run.py: TIOCSWINSZ -> kernel SIGWINCH), subscribed to a local synthetic
// T3 server. Raw terminal bytes are measured per phase. Normal non-CI Ink.
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { startFakeT3 } from "./support/fake-t3.mjs";
import * as S from "./support/synthetic-thread.mjs";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const MAIN = here("../main.mjs");
const PTY = here("./support/pty-run.py");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ESC = "\x1b";

// Whole-screen or scrollback clears, including home + erase-to-end forms.
const CLEARS = [
  ["CSI 2J", /\x1b\[2J/g],
  ["CSI 3J", /\x1b\[3J/g],
  ["home + erase to end", /\x1b\[(?:1;1)?H\x1b\[0?J/g],
  ["RIS", /\x1bc/g],
];
// One Ink log-update erase of the previous live frame: (2K 1A)* 2K G.
const ERASE_BATCH = /(?:\x1b\[2K\x1b\[1A)*\x1b\[2K\x1b\[G/g;
const count = (text, needle) => text.split(needle).length - 1;

async function client({ rows, cols, initial }) {
  const fake = await startFakeT3({ initial });
  const env = { ...process.env, T3_URL: fake.url, T3_SESSION_TOKEN: "synthetic", FORCE_COLOR: "3", TERM: "xterm-256color", COLORTERM: "truecolor" };
  for (const k of ["CONTINUOUS_INTEGRATION", "BUILD_NUMBER", "RUN_ID", "T3_THREAD_DEBUG"]) delete env[k];
  // Ink's is-in-ci also treats any CI_* key as CI; CI=0 is its supported
  // override, so the child always renders interactively.
  env.CI = "0";
  const child = spawn("python3", [PTY, String(rows), String(cols), "--", process.execPath, MAIN, S.THREAD_ID], {
    env,
    stdio: ["pipe", "pipe", "inherit"],
  });
  let out = Buffer.alloc(0);
  let exited = null;
  child.stdout.on("data", (d) => (out = Buffer.concat([out, d])));
  child.on("exit", (code) => (exited = code));
  const marks = [];
  const api = {
    fake,
    get text() {
      return out.toString("latin1");
    },
    get exited() {
      return exited;
    },
    mark(label) {
      marks.push({ label, offset: out.length, at: Date.now() });
    },
    // Bytes and elapsed ms between two marks.
    phase(from, to) {
      const a = marks.find((m) => m.label === from);
      const b = marks.find((m) => m.label === to);
      return { text: out.subarray(a.offset, b.offset).toString("latin1"), ms: b.at - a.at };
    },
    resize(r, c) {
      child.stdin.write(`resize ${r} ${c}\n`);
    },
    async until(pred, ms = 8000) {
      const end = Date.now() + ms;
      while (!pred(api.text)) {
        if (Date.now() > end) throw new Error(`timed out; output tail: ${JSON.stringify(api.text.slice(-400))}`);
        if (exited !== null) throw new Error(`client exited ${exited}: ${JSON.stringify(api.text.slice(-400))}`);
        await sleep(20);
      }
    },
    async stop() {
      if (exited === null) {
        child.stdin.end();
        await new Promise((r) => child.once("exit", r));
      }
      await fake.close();
    },
  };
  return api;
}

function clears(text) {
  return CLEARS.filter(([, re]) => (text.match(re) || []).length).map(([name]) => name);
}

// Rows of the last live frame: bytes after the last erase batch, one PTY
// newline per row (log-update ends each frame with a newline).
function lastFrameRows(text) {
  const batches = [...text.matchAll(ERASE_BATCH)];
  const tail = batches.length ? text.slice(batches.at(-1).index + batches.at(-1)[0].length) : text;
  return count(tail, "\n");
}

test("BATDD-T3STRIKE-04: height shrink during a long stream never clears or replays history", async () => {
  const c = await client({ rows: 24, cols: 80, initial: [S.snapshot({ stream: S.longStream(0) })] });
  try {
    await c.until((t) => t.includes("chunk 0") && t.includes(S.historyMarker(7)));
    await sleep(400);
    for (let i = 0; i < S.HISTORY_RUNS; i++)
      assert.equal(count(c.text, S.historyMarker(i)), 1, `${S.historyMarker(i)} committed once before resize`);
    assert.ok(lastFrameRows(c.text) >= 20, "precondition: a capped 20-row live stream fills the 24-row terminal");
    c.mark("before-resize");
    c.resize(12, 80);
    await sleep(300);
    c.mark("after-resize");
    for (let i = 1; i <= 5; i++) {
      c.fake.push([S.snapshot({ seq: 1 + i, stream: S.longStream(i) })]);
      await sleep(80);
    }
    // At 12 rows the layout has no body rows left for the preview text, so
    // the chunks are delivered and rendered without visible stream lines.
    await sleep(300);
    c.mark("end");
    const shrink = c.phase("before-resize", "after-resize").text;
    const whole = c.phase("before-resize", "end").text;
    // Report every violated invariant together.
    const problems = [];
    for (const name of clears(shrink)) problems.push(`resize emitted ${name}`);
    for (const name of clears(c.phase("after-resize", "end").text)) problems.push(`continuing stream emitted ${name}`);
    for (let i = 0; i < S.HISTORY_RUNS; i++) {
      const n = count(whole, S.historyMarker(i));
      if (n) problems.push(`${S.historyMarker(i)} emitted again ${n}x`);
    }
    if (lastFrameRows(whole) > 11) problems.push(`live region has ${lastFrameRows(whole)} rows on a 12-row terminal`);
    if (c.exited !== null) problems.push("client process exited (recreated)");
    const subscriptions = c.fake.requests.filter((r) => r === "orchestration.subscribeThread").length;
    if (subscriptions !== 1) problems.push(`${subscriptions} subscriptions (reconnect/recreate)`);
    assert.deepEqual(problems, [], "24->12 shrink during a long stream");
  } finally {
    await c.stop();
  }
});

test("BATDD-T3STRIKE-05: stable-size idle and streaming redraws are bounded", async () => {
  const c = await client({ rows: 24, cols: 80, initial: [S.snapshot()] });
  try {
    await c.until((t) => t.includes(S.historyMarker(7)));
    await sleep(500);
    c.mark("settled");
    c.fake.push([S.snapshot({ seq: 2 })]); // unchanged idle rerender
    await sleep(300);
    c.mark("idle-rerender");
    await sleep(1200); // any idle repeating timer would repaint here
    c.mark("idle-wait");
    assert.equal(c.phase("settled", "idle-rerender").text.length, 0, "unchanged idle rerender emits no bytes");
    assert.equal(c.phase("idle-rerender", "idle-wait").text.length, 0, "no idle repeating repaint");

    const startedAt = new Date().toISOString();
    c.fake.push([S.snapshot({ seq: 3, stream: S.longStream(0), startedAt })]);
    await c.until((t) => t.includes("chunk 0"));
    await sleep(200);
    c.mark("stream-start");
    for (let i = 1; i <= 5; i++) {
      c.fake.push([S.snapshot({ seq: 3 + i, stream: S.longStream(i), startedAt })]);
      await sleep(80);
    }
    await c.until((t) => t.includes("chunk 5"));
    await sleep(100);
    c.mark("stream-end");
    const stream = c.phase("stream-start", "stream-end");
    assert.deepEqual(clears(stream.text), [], "no full clear while streaming");
    for (let i = 0; i < S.HISTORY_RUNS; i++)
      assert.equal(count(stream.text, S.historyMarker(i)), 0, `no Static replay of ${S.historyMarker(i)}`);
    const batches = (stream.text.match(ERASE_BATCH) || []).length;
    // A working run repaints its elapsed-time status once a second; allow
    // those ticks, never more than one erase-and-redraw per changed frame.
    const ticks = Math.ceil(stream.ms / 1000);
    assert.ok(batches >= 5, `each of 5 updates repaints the live frame, got ${batches}`);
    assert.ok(batches <= 5 + ticks, `at most one erase/redraw per update (+${ticks} timer ticks), got ${batches}`);

    c.fake.push([S.snapshot({ seq: 20, extra: 1 })]); // the run finishes: a new commit
    await c.until((t) => t.includes(S.historyMarker(8)));
    await sleep(300);
    c.mark("commit");
    const commit = c.phase("stream-end", "commit").text;
    assert.deepEqual(clears(commit), [], "final commit appends without clearing");
    assert.equal(count(c.text, S.historyMarker(8)), 1, "new commit appears once");
    for (let i = 0; i < S.HISTORY_RUNS; i++) assert.equal(count(c.text, S.historyMarker(i)), 1, `${S.historyMarker(i)} once overall`);
    assert.equal(c.exited, null);
  } finally {
    await c.stop();
  }
});
