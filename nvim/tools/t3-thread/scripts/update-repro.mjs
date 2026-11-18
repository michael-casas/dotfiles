#!/usr/bin/env node
// Reproduce a T3 desktop update against an ISOLATED server and measure how
// envi's clients behave. Never touches the live server, ~/.t3 or the envi
// session-token file: everything lives in a fresh temp directory.
//
//   node scripts/update-repro.mjs [--clients N] [--client-root DIR]
//     [--restart-delay MS] [--release-delay MS] [--observe MS] [--label TEXT]
//     [--mode update|e1|e2] [--runs N]
//
// 1. `t3 serve --base-dir <tmp>/home` on a free 127.0.0.1 port (output discarded:
//    it prints a pairing QR code), a 0600 token for that base dir, one project
//    and one message-less thread (no agent turn runs).
// 2. N sidebar feeds and N thread TUIs (in PTYs) from --client-root, with
//    T3_URL, T3_SESSION_TOKEN, T3CODE_HOME=<tmp>/home, HOME=<tmp>/client-home and
//    T3_BIN pointing at a stub that only logs (it never runs the real CLI).
// 3. The desktop protocol: write the marker atomically, SIGTERM (SIGKILL after
//    5 s), stay down for --restart-delay (simulated migrations; a sentinel on
//    the port counts client connects), restart, wait until server-runtime.json
//    shows the new pid, wait --release-delay, remove the marker.
// Stress modes (server shutdown with clients attached, Amendment 1):
//   e1  6 TUIs + 1 feed on the thread, `kill -STOP` every client, SIGTERM the
//       server; --runs (5) times. Pass: every exit within 1 s.
//   e2  3 TUIs on a nonexistent thread (old clients spin on it), SIGTERM at a
//       random phase of the spin; --runs (20) times. Pass: every exit within 1 s.
//   marker-lead  N feeds + N TUIs; marker, wait 0/50/200 ms, SIGTERM; plus
//       marker, 200 ms, SIGSTOP every client, SIGTERM. --runs (3) per case.
//       Reports exit time and client sockets ESTABLISHED at SIGTERM (lsof).
// Prints one JSON report on stdout. Cleans up on success, failure and SIGINT.
import fs from "node:fs";
import os from "node:os";
import net from "node:net";
import path from "node:path";
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i < 0 ? fallback : process.argv[i + 1];
};
const N = Number(arg("--clients", 3));
// realpath: threads.mjs compares argv[1] with its own (resolved) URL, and /tmp is a symlink on macOS.
const root = fs.realpathSync(path.resolve(arg("--client-root", path.join(here, ".."))));
const restartDelay = Number(arg("--restart-delay", 5000));
const releaseDelay = Number(arg("--release-delay", 2000));
const observe = Number(arg("--observe", 12000));
const mode = arg("--mode", "update");
// e1 control knobs: which clients to SIGSTOP (all|none|feed|tuis), how many TUIs.
const freeze = arg("--freeze", "all");
const e1Tuis = Number(arg("--tuis", 6));
const T3 = process.env.T3_REAL_BIN || path.join(os.homedir(), ".t3/bin/t3");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const run = promisify(execFile);

const base = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-repro-"));
const home = path.join(base, "home");
const project = path.join(base, "project");
const runtimeFile = path.join(home, "userdata", "server-runtime.json");
const marker = path.join(home, "runtime", "desktop-update-in-progress");
const spawnLog = path.join(base, "cli-spawns.log");
for (const dir of [home, project, path.join(base, "client-home"), path.join(home, "runtime")])
  fs.mkdirSync(dir, { recursive: true });

const children = new Set();
function track(child) {
  children.add(child);
  child.on("exit", () => children.delete(child));
  return child;
}
let cleaned = false;
async function cleanup() {
  if (cleaned) return;
  cleaned = true;
  for (const c of children) c.kill("SIGTERM");
  await sleep(children.size ? 500 : 0);
  for (const c of children) c.kill("SIGKILL");
  fs.rmSync(base, { recursive: true, force: true });
}
process.once("SIGINT", () => cleanup().then(() => process.exit(130)));
process.once("SIGTERM", () => cleanup().then(() => process.exit(143)));
process.on("uncaughtException", (e) => {
  process.stderr.write(`update-repro: ${e.message}\n`);
  cleanup().then(() => process.exit(1));
});

const freePort = () => new Promise((resolve) => {
  const s = net.createServer().listen(0, "127.0.0.1", () => {
    const { port } = s.address();
    s.close(() => resolve(port));
  });
});
const exited = (child, ms) => new Promise((resolve) => {
  if (child.exitCode !== null || child.signalCode !== null) return resolve(true);
  const t = setTimeout(() => resolve(false), ms);
  child.once("exit", () => { clearTimeout(t); resolve(true); });
});
const readRuntime = () => { try { return JSON.parse(fs.readFileSync(runtimeFile, "utf8")); } catch { return null; } };

async function serve(port, previousPid) {
  const child = track(spawn(T3, ["serve", "--base-dir", home, "--port", String(port), "--host", "127.0.0.1",
    "--no-browser", project], { stdio: "ignore" }));
  // Like desktop releaseUpdateMarker: poll every 100 ms for the new pid and our port.
  for (let i = 0; i < 900; i++) {
    const r = readRuntime();
    if (r && r.port === port && r.pid !== previousPid) return { child, runtime: r };
    if (child.exitCode !== null) throw new Error("isolated t3 serve exited during startup");
    await sleep(100);
  }
  throw new Error("isolated t3 serve did not publish server-runtime.json");
}

async function dispatch(url, token, payload) {
  const r = await fetch(`${url}/api/auth/websocket-ticket/rpc`, { method: "POST", headers: { authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`ticket HTTP ${r.status}`);
  const ws = new WebSocket(`${url.replace(/^http/, "ws")}/ws?orchestrationProtocol=2&wsTicket=${encodeURIComponent((await r.json()).ticket)}`);
  return new Promise((resolve, reject) => {
    ws.onopen = () => ws.send(JSON.stringify({ _tag: "Request", id: "1", tag: "orchestration.dispatchCommand", payload, headers: [] }));
    ws.onmessage = (e) => {
      const m = JSON.parse(String(e.data));
      if (m._tag !== "Exit") return;
      ws.close();
      m.exit?._tag === "Success" ? resolve() : reject(new Error(`${payload.type} failed`));
    };
    ws.onerror = () => reject(new Error("dispatch socket error"));
  });
}

// Spans are flushed when they end, so read the trace after the clients left.
function traceSpans() {
  const dir = path.join(home, "userdata", "logs");
  return fs.readdirSync(dir).filter((f) => f.startsWith("server.trace.ndjson")).flatMap((f) =>
    fs.readFileSync(path.join(dir, f), "utf8").split("\n").flatMap((line) => {
      try {
        const s = JSON.parse(line); // only name, path and start time are used
        return [{ name: s.name, path: s.attributes?.["url.path"], agent: s.attributes?.["user_agent.original"], at: Number(BigInt(s.startTimeUnixNano) / 1_000_000n) }];
      } catch { return []; }
    }));
}

const CLIENT_PATHS = ["/api/auth/websocket-ticket/rpc", "/ws", "/api/orchestration/shell"];

async function setup() {
  const port = await freePort();
  const url = `http://127.0.0.1:${port}`;
  const server = await serve(port);
  const { stdout } = await run(T3, ["auth", "session", "issue", "--base-dir", home, "--scope", "orchestration:read",
    "--scope", "orchestration:operate", "--ttl", "30m", "--label", "t3upd-repro", "--token-only"]);
  const token = stdout.trim();
  fs.writeFileSync(path.join(base, "token"), token, { mode: 0o600 });
  const added = await run(T3, ["project", "add", "--base-dir", home, project]);
  const projectId = /Added project (\S+)/.exec(added.stdout)?.[1];
  const threadId = crypto.randomUUID();
  await dispatch(url, token, { type: "thread.create", commandId: crypto.randomUUID(), threadId, projectId,
    title: "t3upd repro", modelSelection: { instanceId: "codex", model: "gpt-5.4" }, runtimeMode: "full-access",
    interactionMode: "default", branch: null, worktreePath: null, createdBy: "user", creationSource: "web" });
  const stub = path.join(base, "t3-stub");
  fs.writeFileSync(stub, `#!${process.execPath}\nrequire("fs").appendFileSync(${JSON.stringify(spawnLog)}, Date.now() + " " + process.argv.slice(2, 4).join(" ") + "\\n");\nprocess.exit(1);\n`, { mode: 0o755 });
  const env = { ...process.env, HOME: path.join(base, "client-home"), T3CODE_HOME: home, T3_URL: url,
    T3_SESSION_TOKEN: token, T3_BIN: stub, T3_THREAD_DEBUG: "" };
  return { port, server, threadId, env };
}

function attach(env, { feeds: nf, tuis: nt, thread }) {
  const feeds = Array.from({ length: nf }, () => {
    const child = track(spawn(process.execPath, [path.join(root, "threads.mjs")], { env, stdio: ["ignore", "pipe", "ignore"] }));
    const feed = { child, snapshots: [] };
    let buf = "";
    child.stdout.on("data", (d) => {
      const lines = (buf += d).split("\n");
      buf = lines.pop();
      for (const l of lines) if (l.includes('"type":"snapshot"')) feed.snapshots.push(Date.now());
    });
    return feed;
  });
  const tuis = Array.from({ length: nt }, () => {
    const child = track(spawn("python3", [path.join(here, "../test/support/pty-run.py"), "40", "120", "--",
      process.execPath, path.join(root, "main.mjs"), thread], { env, stdio: ["pipe", "pipe", "ignore"] }));
    child.stdout.resume();
    return child;
  });
  return { feeds, tuis };
}
async function ready(feeds) {
  for (let i = 0; i < 100 && feeds.some((f) => !f.snapshots.length); i++) await sleep(100);
  await sleep(3000);
}
// Node client pids: the feed itself and each PTY runner's child.
async function clientPids({ feeds, tuis }) {
  const kids = await Promise.all(tuis.map((c) => run("pgrep", ["-P", String(c.pid)]).then((r) => r.stdout.trim().split("\n").map(Number), () => [])));
  return [...feeds.map((f) => f.child.pid), ...kids.flat()].filter(Boolean);
}
// SIGTERM the server; ms until it exited (SIGKILL after 10 s, reported as killed).
async function terminate(server) {
  const at = Date.now();
  server.child.kill("SIGTERM");
  const graceful = await exited(server.child, 10_000);
  if (!graceful) server.child.kill("SIGKILL");
  await exited(server.child, 5000);
  return { exitMs: Date.now() - at, killed: !graceful };
}
// Client-side TCP connections to the isolated server (lsof, names only).
async function established(port) {
  const r = await run("lsof", ["-nP", `-iTCP@127.0.0.1:${port}`, "-sTCP:ESTABLISHED", "-Fn"]).catch((e) => e);
  return String(r.stdout || "").split("\n").filter((l) => l.startsWith("n") && l.endsWith(`->127.0.0.1:${port}`)).length;
}
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor((xs.length - 1) / 2)];
const signal = (pids, sig) => pids.filter((pid) => { try { process.kill(pid, sig); return true; } catch { return false; } });
const killAll = (clients) => {
  for (const c of [...clients.feeds.map((f) => f.child), ...clients.tuis]) c.kill("SIGKILL");
};
const upgrades = () => traceSpans().filter((s) => s.name === "GET" && s.path === "/ws").length;

// E1: frozen clients must not hold the server's shutdown.
async function e1(ctx, runs) {
  const results = [];
  let server = ctx.server;
  for (let i = 0; i < runs; i++) {
    const clients = attach(ctx.env, { feeds: 1, tuis: e1Tuis, thread: ctx.threadId });
    await ready(clients.feeds);
    const pids = freeze === "none" ? [] : await clientPids({
      feeds: freeze === "tuis" ? [] : clients.feeds, tuis: freeze === "feed" ? [] : clients.tuis });
    signal(pids, "SIGSTOP");
    results.push({ stoppedClients: pids.length, ...(await terminate(server)) });
    signal(pids, "SIGKILL");
    killAll(clients);
    if (i < runs - 1) server = await serve(ctx.port, server.runtime.pid);
  }
  return { mode: "e1", freeze, tuis: e1Tuis, runs: results,
    pass: results.every((r) => r.exitMs < 1000 && (freeze !== "all" || r.stoppedClients === e1Tuis + 1)) };
}

// E2: clients spinning on a missing thread, SIGTERM at a random phase.
async function e2(ctx, runs) {
  const clients = attach(ctx.env, { feeds: 0, tuis: 3, thread: crypto.randomUUID() });
  const results = [];
  let server = ctx.server;
  await sleep(2000);
  for (let i = 0; i < runs; i++) {
    const phase = Math.round(Math.random() * 1000);
    await sleep(1500 + phase);
    results.push({ phaseMs: phase, ...(await terminate(server)) });
    if (i < runs - 1) server = await serve(ctx.port, server.runtime.pid);
  }
  killAll(clients);
  await sleep(1000);
  return { mode: "e2", runs: results, wsUpgradesTotal: upgrades(),
    pass: results.every((r) => r.exitMs < 1000) };
}

// Exact-lead runs SIGTERM at exactly N ms and report only the exit time.
// Sampled runs count sockets first (lsof takes ~80 ms), then SIGTERM, and
// report the real marker-to-SIGTERM lead: sampling lengthens short leads.
async function markerLead(ctx, runs) {
  const clients = attach(ctx.env, { feeds: N, tuis: N, thread: ctx.threadId });
  let server = ctx.server;
  const results = [];
  const cases = [[0, false, false], [50, false, false], [200, false, false],
    [0, false, true], [50, false, true], [200, false, true], [200, true, true]];
  for (const [lead, frozen, sampled] of cases) for (let i = 0; i < runs; i++) {
    for (let j = 0; j < 300 && (await established(ctx.port)) < 2 * N; j++) await sleep(100);
    await sleep(1000);
    const before = await established(ctx.port);
    const at = Date.now();
    fs.writeFileSync(`${marker}.tmp`, JSON.stringify({ startedAt: at, expiresAt: at + 60_000 }));
    fs.renameSync(`${marker}.tmp`, marker);
    await sleep(lead);
    const pids = frozen ? await clientPids(clients) : [];
    const stopped = signal(pids, "SIGSTOP").length;
    const establishedAtTerm = sampled ? await established(ctx.port) : null;
    const effectiveLeadMs = Date.now() - at;
    const stop = await terminate(server);
    const alive = [...clients.tuis, ...clients.feeds.map((f) => f.child)].filter((c) => c.exitCode === null).length;
    results.push({ leadMs: lead, frozen, sampled, effectiveLeadMs, before, establishedAtTerm, stopped, alive, ...stop });
    signal(pids, "SIGCONT");
    fs.rmSync(marker, { force: true });
    server = await serve(ctx.port, server.runtime.pid);
  }
  killAll(clients);
  const summary = cases.map(([lead, frozen, sampled]) => {
    const rs = results.filter((r) => r.leadMs === lead && r.frozen === frozen && r.sampled === sampled);
    return { leadMs: lead, frozen, sampled, medianEffectiveLeadMs: median(rs.map((r) => r.effectiveLeadMs)),
      medianExitMs: median(rs.map((r) => r.exitMs)), killed: rs.filter((r) => r.killed).length,
      established: sampled ? rs.map((r) => `${r.establishedAtTerm}/${r.before}`) : undefined };
  });
  return { mode: "marker-lead", clients: { feeds: N, tuis: N }, summary, runs: results };
}

async function update(ctx) {
  const { port } = ctx;
  const first = ctx.server;
  const clients = attach(ctx.env, { feeds: N, tuis: N, thread: ctx.threadId });
  const { feeds, tuis } = clients;
  await ready(feeds);

  const t = {};
  t.marker = Date.now();
  fs.writeFileSync(`${marker}.tmp`, JSON.stringify({ startedAt: t.marker, expiresAt: t.marker + 60_000 }));
  fs.renameSync(`${marker}.tmp`, marker);
  const stop = await terminate(first);
  t.exit = Date.now();
  let downtimeConnects = 0;
  const sentinel = net.createServer((s) => { downtimeConnects++; s.destroy(); }).listen(port, "127.0.0.1");
  await sleep(restartDelay);
  await new Promise((r) => sentinel.close(r));
  const second = await serve(port, first.runtime.pid);
  t.ready = Date.now();
  await sleep(releaseDelay);
  fs.rmSync(marker, { force: true });
  t.release = Date.now();
  await sleep(observe);

  for (const c of tuis) c.stdin.end("stop\n");
  for (const f of feeds) f.child.kill("SIGTERM");
  await sleep(2000);
  const spans = traceSpans();
  await terminate(second);

  const inWindow = (s) => s.at >= t.marker && s.at < t.release;
  const http = spans.filter((s) => /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/.test(s.name) && inWindow(s));
  const liveMs = (tag) => {
    const starts = spans.filter((s) => s.name === `ws.rpc.orchestration.${tag}` && s.at >= t.ready).map((s) => s.at).sort((a, b) => a - b);
    return starts.length < N ? null : starts[N - 1] - t.release;
  };
  const spawns = fs.existsSync(spawnLog)
    ? fs.readFileSync(spawnLog, "utf8").trim().split("\n").map((l) => Number(l.split(" ")[0])) : [];
  return {
    mode: "update",
    serverVersion: second.runtime.serverVersion,
    clients: { feeds: N, tuis: N },
    timings: { serverExitMs: t.exit - t.marker, killed: stop.killed, restartDelayMs: restartDelay,
      releaseDelayMs: releaseDelay, markerWindowMs: t.release - t.marker },
    markerWindow: {
      // Requests on envi client paths; other paths (e.g. the server's own
      // telemetry POST /batch/) are listed separately.
      clientRequests: http.filter((s) => CLIENT_PATHS.includes(s.path)).length,
      ticketPosts: http.filter((s) => s.path === CLIENT_PATHS[0]).length,
      wsUpgrades: http.filter((s) => s.path === "/ws").length,
      downtimeConnectAttempts: downtimeConnects,
      otherRequests: http.filter((s) => !CLIENT_PATHS.includes(s.path))
        .map((s) => `${s.name} ${s.path} (${String(s.agent).split(" ")[0]})`),
    },
    // Negative: the last client was already subscribed before the marker went.
    recovery: { tuisLiveMs: liveMs("subscribeThread"), feedsLiveMs: liveMs("subscribeShell"),
      feedsSnapshotMs: Math.max(...feeds.map((f) => (f.snapshots.find((s) => s >= t.release) ?? NaN) - t.release)) },
    cliSpawns: { markerWindow: spawns.filter((s) => s >= t.marker && s < t.release).length, total: spawns.length },
  };
}

try {
  const ctx = await setup();
  const runs = Number(arg("--runs", { e2: 20, "marker-lead": 3 }[mode] ?? 5));
  const modes = { e1, e2, "marker-lead": markerLead, update };
  if (!modes[mode]) throw new Error(`unknown --mode ${mode}`);
  const report = await modes[mode](ctx, runs);
  if (report.runs?.length && mode !== "marker-lead") report.medianExitMs = median(report.runs.map((r) => r.exitMs));
  process.stdout.write(`${JSON.stringify({ label: arg("--label", path.basename(root)), ...report }, null, 2)}\n`);
} catch (e) {
  process.stderr.write(`update-repro: ${e.message}\n`);
  process.exitCode = 1;
} finally {
  await cleanup();
}
