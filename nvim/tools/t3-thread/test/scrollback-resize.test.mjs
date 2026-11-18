// BATDD-T3STRIKE-04 / -05: the real main.mjs client on a real PTY (python
// pty-run.py: TIOCSWINSZ -> kernel SIGWINCH), subscribed to a local synthetic
// T3 server. Raw terminal bytes are measured per phase. Normal non-CI Ink.
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
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

async function client({ rows, cols, initial, missedResize = false }) {
  const fake = await startFakeT3({ initial });
  const env = { ...process.env, T3_URL: fake.url, T3_SESSION_TOKEN: "synthetic", FORCE_COLOR: "3", TERM: "xterm-256color", COLORTERM: "truecolor" };
  for (const k of ["CONTINUOUS_INTEGRATION", "BUILD_NUMBER", "RUN_ID", "T3_THREAD_DEBUG"]) delete env[k];
  // Ink's is-in-ci also treats any CI_* key as CI; CI=0 is its supported
  // override, so the child always renders interactively.
  env.CI = "0";
  const child = spawn("python3", [PTY, String(rows), String(cols), "--", process.execPath, ...(missedResize ? ["--import", here("./support/missed-resize.mjs")] : []), MAIN, S.THREAD_ID], {
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
    input(text) { child.stdin.write(`input ${Buffer.from(text).toString("hex")}\n`); },
    resize(r, c) {
      child.stdin.write(`resize ${r} ${c}\n`);
    },
    async until(pred, ms = 8000) {
      const end = Date.now() + ms;
      while (!pred(api.text)) {
        if (Date.now() > end) throw new Error(`timed out; output tail: ${JSON.stringify(api.text.slice(-400))}; replies: ${JSON.stringify(api.text.match(/\x1b\]7503[^\x1b]*/g))}`);
        if (exited !== null) throw new Error(`client exited ${exited}: ${JSON.stringify(api.text.slice(-400))}; replies: ${JSON.stringify(api.text.match(/\x1b\]7503[^\x1b]*/g))}`);
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

const plain = text => text.replace(/\x1b\][\s\S]*?(?:\x07|\x1b\\)/g, "").replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "");
function assertReplay(text, cols) {
  assert.equal(count(text, "\x1b[3J"), 1, "one scrollback clear");
  assert.equal(count(text, "\x1b[2J"), 1, "one screen clear");
  const replay = plain(text.slice(text.indexOf("\x1b[3J")));
  for (let i = 0; i < S.HISTORY_RUNS; i++) {
    assert.equal(count(replay, S.historyMarker(i)), 1, "every committed answer once");
    const line = replay.split(/\r?\n/).find(l => l.includes(S.historyMarker(i)));
    const left = 3 + Math.floor((cols - 6 - Math.min(92, cols - 6)) / 2);
    assert.equal(line.indexOf(S.historyMarker(i)), left, "history begins at current centered column");
  }
}

test("H1-01/03/05: width bursts rebuild all history exactly once at the final width without server traffic", async () => {
  const c = await client({rows: 40, cols: 100, initial: [S.snapshot()]});
  try {
    await c.until(t => t.includes(S.historyMarker(7)));
    await sleep(300);
    const requests = [...c.fake.requests];
    c.mark("before");
    for (const cols of [120, 140, 160]) { c.resize(40, cols); await sleep(40); }
    await sleep(450); c.mark("after");
    assertReplay(c.phase("before", "after").text, 160);
    assert.deepEqual(c.fake.requests, requests, "reflow sends no RPCs");
    assert.deepEqual(c.fake.commands, []);
    c.mark("resync");
    c.fake.push([S.snapshot({seq: 2})]);
    await sleep(250); c.mark("settled");
    for (let i = 0; i < S.HISTORY_RUNS; i++) assert.equal(count(c.phase("resync", "settled").text, S.historyMarker(i)), 0);
    c.mark("back"); c.resize(40, 100); await sleep(450); c.mark("back-end");
    assertReplay(c.phase("back", "back-end").text, 100);
  } finally { await c.stop(); }
});

test("H1-02: row-only and return-to-original width bursts leave history untouched", async () => {
  const c = await client({rows: 40, cols: 100, initial: [S.snapshot()]});
  try {
    await c.until(t => t.includes(S.historyMarker(7))); await sleep(300);
    c.mark("before"); c.resize(35, 100); await sleep(300);
    c.resize(35, 140); await sleep(40); c.resize(35, 100); await sleep(450); c.mark("after");
    const bytes = c.phase("before", "after").text;
    assert.deepEqual(clears(bytes), []);
    assert.equal(count(bytes, S.historyMarker(0)), 0);
  } finally { await c.stop(); }
});

test("H1-04/05: action 9 reconciles real dimensions immediately, reports pre-check width, never sends", async () => {
  const c = await client({rows: 40, cols: 100, initial: [S.snapshot()]});
  try {
    await c.until(t => t.includes(S.historyMarker(7))); await sleep(300);
    const requests = [...c.fake.requests];
    c.mark("before"); c.resize(38, 160);
    await sleep(40); // kernel SIGWINCH updates Node stdout before the local check; still inside debounce
    c.input("\x1b[>777;9;41u");
    await c.until(t => t.includes("\x1b]7503;envi-t3-layout=41;cols=160;rows=38;frozen=100;reflowed=1\x1b\\"));
    await sleep(350); c.mark("after");
    assertReplay(c.phase("before", "after").text, 160);
    c.mark("check"); c.input("\x1b[>777;9;42u");
    await c.until(t => t.includes("\x1b]7503;envi-t3-layout=42;cols=160;rows=38;frozen=160;reflowed=0\x1b\\"));
    c.mark("checked");
    assert.deepEqual(clears(c.phase("check", "checked").text), []);
    assert.deepEqual(c.fake.requests, requests);
    assert.deepEqual(c.fake.commands, []);
  } finally { await c.stop(); }
});

test("H1-04: layout check repairs missed resize events without changing the draft", async () => {
  const c = await client({rows: 40, cols: 100, initial: [S.snapshot()], missedResize: true});
  try {
    await c.until(t => t.includes(S.historyMarker(7))); await sleep(300);
    c.input("DRAFT_PRESERVED"); await c.until(t => t.includes("DRAFT_PRESERVED"));
    c.resize(37, 160); await sleep(300); // no React size update or automatic reflow
    c.mark("check"); c.input("\x1b[>777;9;43u");
    await c.until(t => t.includes("\x1b]7503;envi-t3-layout=43;cols=160;rows=37;frozen=100;reflowed=1\x1b\\"));
    await sleep(150); c.mark("checked");
    const bytes = c.phase("check", "checked").text;
    assertReplay(bytes, 160);
    assert.ok(plain(bytes).includes("DRAFT_PRESERVED"));
    assert.deepEqual(c.fake.commands, []);
  } finally { await c.stop(); }
});

function assertPostFlushReply(bytes, id, cols, rows, frozen) {
  const reply = `\x1b]7503;envi-t3-layout=${id};cols=${cols};rows=${rows};frozen=${frozen};reflowed=1\x1b\\`;
  assert.equal(count(bytes, reply), 1, "one completion notification per rebuild");
  const start = bytes.indexOf("\x1b[3J");
  const end = bytes.indexOf(reply);
  assert.ok(start >= 0 && start < end, "completion follows the clear");
  // Inspect the entire history batch, including the last answer's final row
  // and trailing blank lines, not merely its first visible marker.
  const before = plain(bytes.slice(start, end));
  assert.equal(count(before, "last row 7"), 1, "last history row is printed before completion");
  assert.ok(before.slice(before.indexOf("last row 7")).startsWith("last row 7\r\n\r\n\r\n"), "last history row and both separators precede completion");
  const after = plain(bytes.slice(end + reply.length));
  for (let i = 0; i < S.HISTORY_RUNS; i++) {
    assert.equal(count(before, S.historyMarker(i)), 1, "all history precedes completion");
    assert.equal(count(after, S.historyMarker(i)), 0, "no history appears after completion");
  }
}

test("H1-amend-1: automatic reflow notifies id 0 only after the complete history batch", async () => {
  const c = await client({rows: 40, cols: 100, initial: [S.snapshot()]});
  try {
    await c.until(t => t.includes(S.historyMarker(7))); await sleep(300);
    assert.equal(count(c.text, "envi-t3-layout=0;"), 0, "startup without rebuild emits no notification");
    c.mark("before"); c.resize(39, 160); await sleep(500); c.mark("after");
    const bytes = c.phase("before", "after").text;
    assertReplay(bytes, 160);
    assertPostFlushReply(bytes, 0, 160, 39, 100);
    c.mark("noop"); c.resize(38, 160); await sleep(300); c.mark("noop-end");
    assert.equal(count(c.phase("noop", "noop-end").text, "envi-t3-layout=0;"), 0, "rows-only resize never notifies rebuild");
    assert.deepEqual(c.fake.commands, []);
  } finally { await c.stop(); }
});

test("H1-amend-1: solicited reflow completion follows all reprinted bytes without a second id-0 notification", async () => {
  const c = await client({rows: 40, cols: 100, initial: [S.snapshot()], missedResize: true});
  try {
    await c.until(t => t.includes(S.historyMarker(7))); await sleep(300);
    c.resize(38, 160); await sleep(100);
    c.mark("before"); c.input("\x1b[>777;9;51u");
    await c.until(t => t.includes("envi-t3-layout=51;cols=160;rows=38;frozen=100;reflowed=1"));
    await sleep(350); c.mark("after");
    const bytes = c.phase("before", "after").text;
    assertPostFlushReply(bytes, 51, 160, 38, 100);
    assert.equal(count(bytes, "envi-t3-layout=0;"), 0, "solicited rebuild has only its correlated completion");
    assert.deepEqual(c.fake.commands, []);
  } finally { await c.stop(); }
});

// Every destructive clear must carry a complete replacement immediately,
// before a completion notification tells viewers they may replay the core.
function assertHistorySurvives(bytes) {
  const chunks = bytes.split("\x1b[2J\x1b[3J\x1b[H");
  for (const chunk of chunks.slice(1)) {
    const history = plain(chunk.split("\x1b]7503;")[0]);
    for (let i = 0; i < S.HISTORY_RUNS; i++)
      assert.equal(count(history, S.historyMarker(i)), 1, "each full clear must immediately restore every committed answer");
  }
}

test("H1-r1: fixed live parts on a one-row PTY cannot erase committed history", async () => {
  const initial = S.snapshot();
  const card = {id:"q",type:"user_input_request",requestId:"request",questions:[{id:"q1",question:"Synthetic question",options:[{label:"One"},{label:"Two"}]}]};
  initial.projection.runtimeRequests = [{id:"request",kind:"user_input",status:"pending",responseCapability:{type:"resumable"}}];
  initial.projection.turnItems.push(card);
  initial.projection.visibleTurnItems.push({position:99,item:card});
  const c = await client({rows: 30, cols: 100, initial: [initial], missedResize: true});
  try {
    await c.until(t=>t.includes(S.historyMarker(7))); await sleep(300);
    c.mark("before"); c.resize(1,100); await sleep(80);
    c.input("\x1b[>777;9;61u"); await sleep(400); c.mark("after");
    assertHistorySurvives(c.phase("before","after").text);
    assert.deepEqual(c.fake.commands, []);
  } finally { await c.stop(); }
});

test("H1-r1: row shrink with a missed size event restores history before any destructive repaint", async () => {
  const c = await client({rows: 30, cols: 100, initial:[S.snapshot({stream:S.longStream(0)})], missedResize:true});
  try {
    await c.until(t=>t.includes(S.historyMarker(7)) && t.includes("chunk 0")); await sleep(300);
    c.mark("before"); c.resize(8,100); await sleep(80);
    c.fake.push([S.snapshot({seq:2,stream:S.longStream(1)})]);
    await sleep(400); c.mark("after");
    const bytes=c.phase("before","after").text;
    assert.ok(bytes.includes("\x1b[3J"), "exercise real Ink full-height path with stale React dimensions");
    assertHistorySurvives(bytes);
    assertPostFlushReply(bytes, 0, 100, 8, 100);
    assert.deepEqual(c.fake.commands, []);
  } finally { await c.stop(); }
});

test("H1-r1: fixed parts and a multiline draft stay bounded on a tiny normal-resize PTY", async () => {
  const c=await client({rows:30,cols:100,initial:[S.snapshot()]});
  try {
    await c.until(t=>t.includes(S.historyMarker(7))); await sleep(250);
    c.input("one\ntwo\nthree\nfour\nfive\nsix"); await sleep(150);
    c.mark("before"); c.resize(5,100); await sleep(350); c.mark("after");
    const bytes=c.phase("before","after").text;
    assertHistorySurvives(bytes);
    assert.deepEqual(clears(bytes),[],"normal resize hard cap prevents Ink full-height clear");
    assert.ok(plain(bytes).includes("Completed"),"status survives bottom clipping");
  } finally { await c.stop(); }
});
