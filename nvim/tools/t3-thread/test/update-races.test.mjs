// Transport races around a desktop update (HOTFIX T3UPD round 1: F01-F06, F13).
// Local fakes on 127.0.0.1, temp T3 homes and a stub CLI only.
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { EventEmitter } from "node:events";
import { startFakeT3 } from "./support/fake-t3.mjs";
import { startFeed } from "../threads.mjs";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const snapshot = [{ kind: "snapshot", snapshotSequence: 1, projection: { thread: { id: "t", title: "T" } } }];
const shell = { snapshotSequence: 1, projects: [], threads: [], archivedThreads: [] };
async function until(predicate, ms = 3000) {
  const end = Date.now() + ms;
  while (!predicate()) {
    if (Date.now() > end) return false;
    await sleep(10);
  }
  return true;
}
function setEnv(t, vars) {
  for (const [k, v] of Object.entries(vars)) {
    const old = process.env[k];
    t.after(() => (old === undefined ? delete process.env[k] : (process.env[k] = old)));
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
}
function t3home(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-races-"));
  fs.mkdirSync(path.join(home, "runtime"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const marker = path.join(home, "runtime", "desktop-update-in-progress");
  return {
    home,
    write() {
      fs.writeFileSync(`${marker}.tmp`, JSON.stringify({ startedAt: Date.now(), expiresAt: Date.now() + 60_000 }));
      fs.renameSync(`${marker}.tmp`, marker);
    },
    remove: () => fs.rmSync(marker, { force: true }),
  };
}
// A fresh adapter (module caches reset) pointed at `url` with a temp T3 home.
async function adapter(t, url, home, env = {}) {
  setEnv(t, { T3_URL: url, T3CODE_HOME: home.home, T3_SESSION_TOKEN: "fixture-token", ...env });
  return import(`../t3.mjs?races=${crypto.randomUUID()}`);
}
// A CLI stub that logs "<epoch ms> <args>" and prints `out` after `delay` ms.
function stub(t, home, { delay = 0, out = '{"token":"issued-fixture","expiresAt":"2099-01-01T00:00:00Z"}' } = {}) {
  const bin = path.join(home.home, "t3-stub");
  const log = path.join(home.home, "t3-stub.log");
  fs.writeFileSync(bin, `#!${process.execPath}\nrequire("fs").appendFileSync(${JSON.stringify(log)}, Date.now() + " " + process.argv.slice(2).join(" ") + "\\n");\nsetTimeout(() => process.stdout.write(${JSON.stringify(out)}), ${delay});\n`, { mode: 0o755 });
  return { bin, spawns: () => (fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n") : []) };
}
function feed(t, t3, options = {}) {
  const output = [];
  const f = startFeed(options, { openSocket: (...args) => t3.openShellSocket(...args), write: (l) => output.push(JSON.parse(l)) });
  t.after(() => f.close());
  return output;
}
const holdFirstTicket = (held) => (req, res, n) => {
  if (n !== 1) return false;
  held.push(res);
  return true;
};

test("F01: a feed ticket in flight at the marker is cancelled; no upgrade until release", async (t) => {
  const held = [];
  const fake = await startFakeT3({ initial: snapshot, shell, onTicket: holdFirstTicket(held) });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const output = feed(t, t3);
  assert.ok(await until(() => held.length === 1));
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 500), `pending ticket still open: ${fake.openConnections()}`);
  assert.ok(await until(() => output.at(-1)?.message === "T3 updating…", 500));
  held[0].writeHead(200, { "content-type": "application/json" });
  held[0].end('{"ticket":"late"}');
  await sleep(300);
  assert.equal(fake.counts.upgrades, 0, "the late ticket never upgrades");
  home.remove();
  assert.ok(await until(() => output.at(-1)?.type === "snapshot", 2000), "recovered");
  await sleep(200);
  assert.equal(fake.counts.upgrades, 1, "exactly one current-generation upgrade");
});

test("F01: an auth refresh that returns during the marker makes no POST", async (t) => {
  const fake = await startFakeT3({ initial: snapshot, onTicket: (req, res) => {
    if (req.headers.authorization === "Bearer issued-fixture") return false;
    res.writeHead(401);
    res.end();
    return true;
  } });
  t.after(() => fake.close());
  const home = t3home(t);
  const cli = stub(t, home, { delay: 500 });
  const t3 = await adapter(t, fake.url, home, { T3_SESSION_TOKEN: undefined, T3_BIN: cli.bin, HOME: home.home });
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => cli.spawns().length === 1), "issuing after the 401");
  home.write();
  assert.ok(await until(() => conns.at(-1) === "T3 updating…", 500));
  await sleep(900); // the CLI returns inside the marker window
  assert.equal(fake.tickets.length, 1, "no POST in the marker window");
  home.remove();
  assert.ok(await until(() => conns.at(-1) === "live", 3000), conns.join(" | "));
  assert.equal(fake.tickets.at(-1).auth, "Bearer issued-fixture");
});

test("F01: a ticket from a retired attempt never upgrades", async (t) => {
  const held = [];
  const fake = await startFakeT3({ initial: snapshot, onTicket: holdFirstTicket(held) });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => held.length === 1));
  home.write();
  assert.ok(await until(() => conns.at(-1) === "T3 updating…", 500));
  home.remove();
  assert.ok(await until(() => conns.at(-1) === "live", 2000), "new attempt is live");
  held[0].writeHead(200, { "content-type": "application/json" });
  held[0].end('{"ticket":"late"}');
  await sleep(300);
  assert.equal(fake.counts.upgrades, 1, "only the current attempt upgraded");
});

test("F01: closing a client with its ticket pending closes the request", async (t) => {
  const held = [];
  const fake = await startFakeT3({ initial: snapshot, onTicket: holdFirstTicket(held) });
  t.after(() => fake.close());
  const t3 = await adapter(t, fake.url, t3home(t));
  const close = t3.subscribe("t", {});
  assert.ok(await until(() => held.length === 1));
  close();
  assert.ok(await until(() => fake.openConnections() === 0, 500), "request closed");
  held[0].writeHead(200, { "content-type": "application/json" });
  held[0].end('{"ticket":"late"}');
  await sleep(300);
  assert.equal(fake.counts.upgrades, 0);
});

test("F01/F13: a project lookup paused at the marker is cancelled, not cached, and refilled after", async (t) => {
  const held = [];
  let shellReads = 0;
  const fake = await startFakeT3({ initial: snapshot, routes: { "/api/orchestration/shell": (req, res) => {
    if (++shellReads === 1) return held.push(res);
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ projects: [{ id: "p", title: "Proj", workspaceRoot: "/projects/proj" }] }));
  } } });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const first = t3.projects();
  assert.ok(await until(() => held.length === 1));
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 1500), "lookup cancelled");
  assert.equal((await first).size, 0);
  const during = fake.counts.http;
  assert.equal((await t3.projects()).size, 0, "still updating");
  assert.equal(fake.counts.http, during, "no request during the marker");
  home.remove();
  const after = await t3.projects();
  assert.deepEqual([...after], [["p", { title: "Proj", workspaceRoot: "/projects/proj" }]]);
  assert.equal(shellReads, 2, "one post-release lookup");
});

test("F02: a peer that never answers the close frame cannot keep the thread socket", async (t) => {
  const fake = await startFakeT3({ initial: snapshot, withholdClose: true });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => conns.at(-1) === "live"));
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 500), "socket released without the peer's reply");
  assert.equal(conns.at(-1), "T3 updating…");
  await sleep(500);
  assert.equal(fake.counts.upgrades, 1, "no reconnect during the marker");
  home.remove();
  assert.ok(await until(() => conns.at(-1) === "live" && fake.counts.upgrades === 2, 2000), "one recovery");
});

test("F02: a peer that never answers the close frame cannot keep the feed socket", async (t) => {
  const fake = await startFakeT3({ initial: snapshot, shell, withholdClose: true });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const output = feed(t, t3);
  assert.ok(await until(() => output.at(-1)?.type === "snapshot"));
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 500), "socket released without the peer's reply");
  await sleep(500);
  assert.equal(fake.counts.upgrades, 1, "no reconnect during the marker");
  home.remove();
  assert.ok(await until(() => fake.counts.upgrades === 2 && output.at(-1)?.type === "snapshot", 2000), "one recovery");
});

test("F02: a websocket handshake still in progress is released by the marker", async (t) => {
  const fake = await startFakeT3({ initial: snapshot, no101: true });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => fake.counts.upgrades === 1));
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 500), "pending handshake released");
  assert.equal(conns.at(-1), "T3 updating…");
});

test("F03: the thread command CLI never runs against an unreachable server", async (t) => {
  const home = t3home(t);
  const cli = stub(t, home, { out: "[]" });
  const t3 = await adapter(t, "http://127.0.0.1:1", home, { T3_BIN: cli.bin });
  await assert.rejects(t3.list("p"), /not reachable/);
  await assert.rejects(t3.start("p", "hello"), /not reachable/);
  assert.deepEqual(cli.spawns(), []);
});

test("F03: a marker that appears during the liveness check stops the CLI", async (t) => {
  const held = [];
  const fake = await startFakeT3({ initial: snapshot, routes: { "/.well-known/t3/environment": (req, res) => held.push(res) } });
  t.after(() => fake.close());
  const home = t3home(t);
  const cli = stub(t, home, { out: "[]" });
  const t3 = await adapter(t, fake.url, home, { T3_BIN: cli.bin });
  const listing = t3.list("p");
  assert.ok(await until(() => held.length === 1), "liveness checked first");
  home.write();
  held[0].end("{}");
  await assert.rejects(listing, /T3 is updating/);
  assert.deepEqual(cli.spawns(), []);
});

test("F03: a live server still runs the command CLI once and returns its result", async (t) => {
  const fake = await startFakeT3({ initial: snapshot, routes: { "/.well-known/t3/environment": (req, res) => res.end("{}") } });
  t.after(() => fake.close());
  const home = t3home(t);
  const cli = stub(t, home, { out: '[{"id":"t1"}]' });
  const t3 = await adapter(t, fake.url, home, { T3_BIN: cli.bin });
  assert.deepEqual(await t3.list("p"), [{ id: "t1" }]);
  assert.equal(cli.spawns().length, 1);
  assert.match(cli.spawns()[0], / thread list --project p --json$/);
});

// fs.watch replacement whose watchers can be failed on demand.
function failingWatch(t) {
  const watchers = [];
  const original = fs.watch;
  fs.watch = () => {
    const w = new EventEmitter();
    w.close = () => {};
    watchers.push(w);
    return w;
  };
  t.after(() => (fs.watch = original));
  return () => watchers.forEach((w) => w.emit("error", new Error("watch invalidated")));
}

test("F05: after a watcher error a live client still releases on the marker", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const home = t3home(t);
  const fail = failingWatch(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => conns.at(-1) === "live"));
  fail();
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 1500), "released by the fallback check");
  home.remove();
  assert.ok(await until(() => conns.at(-1) === "live", 1500), "resumed within about 1 s");
});

test("F05: after a watcher error a held client still resumes promptly", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const home = t3home(t);
  home.write();
  const fail = failingWatch(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => conns.at(-1) === "T3 updating…"));
  fail();
  const requests = fake.counts.http;
  home.remove();
  assert.ok(await until(() => conns.at(-1) === "live", 1500), "resumed within about 1 s");
  assert.equal(requests, 0, "no network while held");
});

test("F05: a replaced runtime directory keeps detecting later updates", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  assert.ok(await until(() => conns.at(-1) === "live"));
  for (let cycle = 1; cycle <= 2; cycle++) {
    fs.rmSync(path.join(home.home, "runtime"), { recursive: true });
    fs.mkdirSync(path.join(home.home, "runtime"));
    await sleep(50);
    home.write();
    assert.ok(await until(() => fake.openConnections() === 0, 1500), `cycle ${cycle}: released`);
    home.remove();
    assert.ok(await until(() => conns.at(-1) === "live", 1500), `cycle ${cycle}: resumed`);
  }
});

test("F06: update and restart notices are shown over a pending request, which returns after", async (t) => {
  const pendingSnapshot = [{ kind: "snapshot", snapshotSequence: 1, projection: {
    thread: { id: "t", title: "T" }, runtimeRequests: [{ id: "r1", kind: "command_approval", status: "pending" }] } }];
  const fake = await startFakeT3({ initial: pendingSnapshot });
  t.after(() => fake.close());
  const port = Number(new URL(fake.url).port);
  const home = t3home(t);
  const runtime = (pid, serverVersion) => {
    fs.mkdirSync(path.join(home.home, "userdata"), { recursive: true });
    fs.writeFileSync(path.join(home.home, "userdata", "server-runtime.json"),
      JSON.stringify({ pid, startedAt: `2026-11-17T21:0${pid}:00.000Z`, serverVersion, port }));
  };
  runtime(1, "v1");
  const t3 = await adapter(t, fake.url, home);
  // What the status line shows: recomputed on every state or connection change.
  let state = null, conn = "connecting";
  const labels = [];
  const show = () => {
    const label = t3.statusLabel(state, conn)[0];
    if (labels.at(-1) !== label) labels.push(label);
  };
  const close = t3.subscribe("t", {
    onState: (s) => { state = s; show(); },
    onConn: (c) => { conn = c; show(); },
  });
  t.after(close);
  assert.ok(await until(() => state && labels.at(-1) === "Pending Approval"), labels.join(" | "));
  home.write();
  assert.ok(await until(() => labels.at(-1) === "T3 updating…", 500), labels.join(" | "));
  runtime(2, "v2");
  home.remove();
  assert.ok(await until(() => labels.at(-1) === "T3 server restarted (v2)", 2000), labels.join(" | "));
  assert.ok(await until(() => labels.at(-1) === "Pending Approval", 6000), labels.join(" | "));
  assert.equal(labels.filter((l) => l.startsWith("T3 server restarted")).length, 1);
});

test("F06: statusLabel puts connection notices above a pending request", async () => {
  const { statusLabel } = await import("../t3.mjs");
  const state = { runtimeRequests: new Map([["a", { kind: "command", status: "pending" }]]) };
  assert.deepEqual(statusLabel(state, "T3 updating…"), ["T3 updating…", "warning"]);
  assert.deepEqual(statusLabel(state, "T3 server restarted (fixture)"), ["T3 server restarted (fixture)", "info"]);
  assert.deepEqual(statusLabel(state, "live"), ["Pending Approval", "warning"]);
  assert.deepEqual(statusLabel(state, "offline"), ["Pending Approval", "warning"]);
});

// ── round 2: handshake boundary, WSS teardown, peer-initiated close ─────────
import tls from "node:tls";
import { execFileSync } from "node:child_process";

// fs.watch that never fires: the subscribe boundary alone must stop RPCs.
function deadWatch(t) {
  const original = fs.watch;
  fs.watch = () => Object.assign(new EventEmitter(), { close() {} });
  t.after(() => (fs.watch = original));
}
// A throwaway localhost certificate, trusted for this process only.
let certs;
function tlsFixture(t) {
  if (!certs) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-tls-"));
    execFileSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=127.0.0.1",
      "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost", "-keyout", path.join(dir, "key.pem"), "-out", path.join(dir, "cert.pem")], { stdio: "ignore" });
    certs = { key: fs.readFileSync(path.join(dir, "key.pem")), cert: fs.readFileSync(path.join(dir, "cert.pem")) };
    fs.rmSync(dir, { recursive: true, force: true });
  }
  const before = tls.getCACertificates("default");
  tls.setDefaultCACertificates([...before, certs.cert.toString()]);
  t.after(() => tls.setDefaultCACertificates(before));
  return certs;
}
function uncaught(t) {
  const seen = [];
  const record = (e) => seen.push(e.code || e.message);
  process.on("uncaughtException", record);
  t.after(() => process.off("uncaughtException", record));
  return seen;
}

for (const client of ["thread", "feed"])
test(`F01: a marker published during the ${client} handshake stops it before any RPC`, async (t) => {
  deadWatch(t);
  const home = t3home(t);
  let once = true;
  const fake = await startFakeT3({ initial: snapshot, shell, beforeUpgrade: () => once && (once = false, home.write()) });
  t.after(() => fake.close());
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  if (client === "thread") t.after(t3.subscribe("t", { onConn: (c) => conns.push(c) }));
  else { const out = feed(t, t3); conns.push = (c) => Array.prototype.push.call(conns, c); setInterval(() => out.length && conns.push(out.at(-1).message ?? out.at(-1).type), 20).unref(); }
  assert.ok(await until(() => fake.counts.upgrades === 1));
  assert.ok(await until(() => fake.openConnections() === 0, 500), "released at the subscribe boundary");
  await sleep(200);
  assert.deepEqual(fake.requestLog, [], "no RPC after the marker was published");
  home.remove();
  assert.ok(await until(() => fake.requestLog.length > 0, 2000), "recovered after the marker cleared");
});

test("F01: an update cancels a pending command liveness check", async (t) => {
  const held = [];
  const fake = await startFakeT3({ initial: snapshot, routes: { "/.well-known/t3/environment": (req, res) => held.push(res) } });
  t.after(() => fake.close());
  const home = t3home(t);
  const cli = stub(t, home, { out: "[]" });
  const t3 = await adapter(t, fake.url, home, { T3_BIN: cli.bin });
  let outcome = "pending";
  const listing = t3.list("p").then(() => (outcome = "ran"), (e) => (outcome = e.message));
  assert.ok(await until(() => held.length === 1));
  home.write();
  assert.ok(await until(() => fake.openConnections() === 0, 1500), "liveness request cancelled");
  assert.ok(await until(() => outcome !== "pending", 200));
  assert.match(outcome, /T3 is updating/);
  await listing;
  assert.deepEqual(cli.spawns(), []);
});

// Amendment 8: WSS (and any non-loopback endpoint) uses the platform WebSocket,
// with its own TLS, SNI and certificate checks; the owned transport is
// plaintext loopback ws:// only.
for (const client of ["thread", "feed"])
test(`F02/A8: a wss://localhost ${client} sends SNI "localhost" for HTTPS and WSS and goes live`, async (t) => {
  const fake = await startFakeT3({ initial: snapshot, shell, tls: tlsFixture(t), requireSni: "localhost" });
  t.after(() => fake.close());
  const t3 = await adapter(t, fake.url.replace("127.0.0.1", "localhost"), t3home(t));
  if (client === "thread") t.after(t3.subscribe("t", {}));
  else feed(t, t3);
  assert.ok(await until(() => fake.requestLog.length > 0, 3000), `subscribed; SNI seen: ${JSON.stringify(fake.servernames)}`);
  assert.deepEqual([...new Set(fake.servernames.map((s) => `${s.kind}:${s.name}`))].sort(), ["https:localhost", "wss:localhost"]);
});

for (const client of ["thread", "feed"])
test(`A8: WSS ${client} smoke: connect, marker, graceful close, hold, release, recover`, async (t) => {
  const errors = uncaught(t);
  const fake = await startFakeT3({ initial: snapshot, shell, tls: tlsFixture(t) });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const states = [];
  if (client === "thread") t.after(t3.subscribe("t", { onConn: (c) => states.push(c) }));
  else { const out = feed(t, t3); setInterval(() => states.push(out.at(-1)?.message ?? out.at(-1)?.type), 20).unref(); }
  assert.ok(await until(() => fake.requestLog.length > 0));
  home.write();
  assert.ok(await until(() => fake.counts.closeFrames === 1, 500), "graceful Close sent on the marker");
  assert.ok(await until(() => fake.openSockets() === 0, 1000), "the WSS connection is gone");
  assert.ok(await until(() => states.at(-1) === "T3 updating…", 500));
  await sleep(300);
  assert.equal(fake.counts.upgrades, 1, "no attempt during the hold");
  home.remove();
  assert.ok(await until(() => fake.counts.upgrades === 2 && fake.requestLog.length > 1, 2000), "one recovery over WSS");
  assert.deepEqual(errors, []);
});

test("A8: only plaintext loopback ws:// uses the owned transport", async () => {
  const { ownsTransport } = await import("../ws.mjs");
  for (const url of ["ws://127.0.0.1:1/ws", "ws://127.9.0.1:1/ws", "ws://localhost:1/ws", "ws://[::1]:1/ws"])
    assert.equal(ownsTransport(url), true, url);
  for (const url of ["wss://127.0.0.1:1/ws", "wss://localhost/ws", "ws://192.0.2.1:1/ws", "ws://t3.example.test/ws", "ws://127.0.0.1.example.test/ws"])
    assert.equal(ownsTransport(url), false, url);
});

for (const client of ["thread", "feed"])
test(`F14: a peer-initiated close is acknowledged once (masked); the ${client} reconnects once`, async (t) => {
  const fake = await startFakeT3({ initial: snapshot, shell });
  t.after(() => fake.close());
  const t3 = await adapter(t, fake.url, t3home(t));
  if (client === "thread") t.after(t3.subscribe("t", {}));
  else feed(t, t3);
  assert.ok(await until(() => fake.requestLog.length > 0));
  fake.serverClose();
  assert.ok(await until(() => fake.counts.closeFrames === 1, 500), "acknowledged");
  assert.equal(fake.counts.unmaskedClose, 0, "client frames are masked");
  assert.ok(await until(() => fake.counts.upgrades === 2, 3000), "eligible reconnect");
  await sleep(300);
  assert.equal(fake.counts.closeFrames, 1, "no duplicate Close");
  assert.equal(fake.counts.upgrades, 2, "one connection-loss transition");
});

test("F14: a close from both sides at once sends a single Close frame and holds", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const conns = [];
  t.after(t3.subscribe("t", { onConn: (c) => conns.push(c) }));
  assert.ok(await until(() => conns.at(-1) === "live"));
  fake.serverClose();
  home.write();
  assert.ok(await until(() => conns.at(-1) === "T3 updating…", 1500));
  await sleep(300);
  assert.equal(fake.counts.closeFrames <= 1, true, `close frames: ${fake.counts.closeFrames}`);
  assert.equal(fake.counts.upgrades, 1, "no reconnect during the marker");
});

// ── round 3: peer-first close vs marker; default-port identity ──────────────
for (const client of ["thread", "feed"])
test(`F15: a ws ${client} socket closing peer-first is still released by the marker`, async (t) => {
  const fake = await startFakeT3({ initial: snapshot, shell, withholdClose: true });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const states = [];
  if (client === "thread") t.after(t3.subscribe("t", { onConn: (c) => states.push(c) }));
  else { const out = feed(t, t3); setInterval(() => { const m = out.at(-1)?.message; if (m && states.at(-1) !== m) states.push(m); }, 5).unref(); }
  assert.ok(await until(() => fake.requestLog.length > 0));
  fake.serverClose();
  assert.ok(await until(() => fake.counts.closeFrames === 1, 500), "acknowledged");
  home.write(); // the peer withholds its TCP close: only our release can end it
  assert.ok(await until(() => fake.openConnections() === 0, 500), "peer end sees the connection gone");
  assert.ok(await until(() => states.at(-1) === "T3 updating…", 500));
  assert.equal(fake.counts.closeFrames, 1, "one acknowledgement");
  assert.equal(fake.counts.unmaskedClose, 0);
  assert.ok(states.filter((s) => /reconnecting/.test(s)).length <= 1, `one loss transition: ${states.join(" | ")}`);
  await sleep(300);
  assert.equal(fake.counts.upgrades, 1, "no upgrade during the hold");
  home.remove();
  assert.ok(await until(() => fake.counts.upgrades === 2, 2000), "one eligible recovery");
});

// Two generations closing peer-first at once (round 4): both half-open peers
// are released on the marker, and on disposal.
for (const client of ["thread", "feed"]) for (const via of ["marker", "dispose"])
test(`F15: two ${client} sockets closing peer-first are both released (${via})`, async (t) => {
  const fake = await startFakeT3({ initial: snapshot, shell, withholdClose: true });
  t.after(() => fake.close());
  const home = t3home(t);
  const t3 = await adapter(t, fake.url, home);
  const states = [];
  let dispose;
  if (client === "thread") t.after((dispose = t3.subscribe("t", { onConn: (c) => states.push(c) })));
  else {
    const f = startFeed({}, { openSocket: (...args) => t3.openShellSocket(...args), write: (l) => states.push(JSON.parse(l).message) });
    t.after((dispose = () => f.close()));
  }
  const subscriptions = () => fake.requests.filter((r) => r.startsWith("orchestration.subscribe")).length;
  assert.ok(await until(() => subscriptions() === 1));
  fake.serverClose();
  assert.ok(await until(() => fake.counts.closeFrames === 1, 500), "first acknowledgement");
  assert.ok(await until(() => subscriptions() === 2, 1000), "second generation subscribed");
  fake.serverClose();
  assert.ok(await until(() => fake.counts.closeFrames === 2, 500), "second acknowledgement");
  assert.equal(fake.openSockets(), 2, "both peers are deliberately half-open");
  const at = Date.now();
  if (via === "marker") home.write();
  else dispose();
  assert.ok(await until(() => fake.openSockets() === 0, 150), `both released; ${fake.openSockets()} open after ${Date.now() - at} ms`);
  assert.equal(fake.counts.closeFrames, 2, "one acknowledgement each");
  assert.equal(fake.counts.unmaskedClose, 0);
  assert.equal(states.filter((s) => /reconnecting/.test(s ?? "")).length, 2, `one loss transition each: ${states.join(" | ")}`);
  if (via === "dispose") return;
  await sleep(300);
  assert.equal(fake.counts.upgrades, 2, "no upgrade during the hold");
  home.remove();
  assert.ok(await until(() => subscriptions() === 3, 2000), "one eligible recovery");
});

for (const [name, url, runtimePort, notices] of [
  ["default https", "https://127.0.0.1", 443, 1],
  ["literal :443", "https://127.0.0.1:443", 443, 1],
  ["wrong-port record", "https://127.0.0.1", 8443, 0],
])
test(`F16: restart notice over ${name}`, async (t) => {
  const fake = await startFakeT3({ initial: snapshot, tls: tlsFixture(t) });
  t.after(() => fake.close());
  const https = (await import("node:https")).default;
  const request = https.request;
  // Route the default-port request to the fixture; the logical port stays 443.
  https.request = function (target, ...rest) {
    const u = new URL(target);
    if (!u.port) u.port = new URL(fake.url).port;
    return request.call(this, u, ...rest);
  };
  t.after(() => (https.request = request));
  // WSS uses the platform WebSocket (Amendment 8): route its default port too.
  const Platform = globalThis.WebSocket;
  globalThis.WebSocket = class extends Platform {
    constructor(target, ...rest) {
      const u = new URL(target);
      if (!u.port) u.port = new URL(fake.url).port;
      super(u, ...rest);
    }
  };
  t.after(() => (globalThis.WebSocket = Platform));
  const home = t3home(t);
  const runtime = (pid) => {
    fs.mkdirSync(path.join(home.home, "userdata"), { recursive: true });
    fs.writeFileSync(path.join(home.home, "userdata", "server-runtime.json"),
      JSON.stringify({ pid, startedAt: `s${pid}`, serverVersion: `v${pid}`, port: runtimePort }));
  };
  runtime(1);
  const t3 = await adapter(t, url, home);
  const conns = [];
  t.after(t3.subscribe("t", { onConn: (c) => conns.push(c) }));
  assert.ok(await until(() => conns.at(-1) === "live"));
  runtime(2);
  fake.dropAll();
  assert.ok(await until(() => fake.counts.upgrades === 2 && conns.at(-1) !== "connecting", 3000));
  await sleep(100);
  assert.equal(conns.filter((c) => c.startsWith("T3 server restarted")).length, notices, conns.join(" | "));
});
