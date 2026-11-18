#!/usr/bin/env node
// Reproduce a T3 desktop update against an ISOLATED server and measure how
// envi's clients behave. Never touches the live server, ~/.t3 or the envi
// session-token file: everything lives in a fresh temp directory, and server
// output (it prints a pairing QR code) is discarded.
//
//   node scripts/update-repro.mjs [--mode update|marker-lead|e1|e2|lifecycle]
//     [--clients N] [--client-root DIR] [--runs N] [--label TEXT]
//     [--restart-delay MS] [--release-delay MS] [--observe MS] [--ready-timeout MS]
//     [--freeze all|none] [--tuis N] [--fault no-first-chunk|sampler] [--pid-log FILE]
//
// Setup: `t3 serve --base-dir <tmp>/home` on a free 127.0.0.1 port, a 0600 token
// for that base dir, one project and one message-less thread (no agent turn).
// Clients come from --client-root (any checkout): N sidebar feeds and N thread
// TUIs in PTYs, with T3_URL, T3_SESSION_TOKEN, T3CODE_HOME=<tmp>/home,
// HOME=<tmp>/client-home and T3_BIN pointing at a stub that only logs.
// Every client must show the thread's title before a trial and (update mode)
// a new title dispatched right after the marker is released; a client that
// does not makes the evidence invalid.
//
// Desktop protocol (update, lifecycle): write the marker (tmp + rename),
// SIGTERM, SIGKILL after 5 s (BACKEND stop grace); stay down --restart-delay
// (a sentinel on the port counts client connects); restart; the successor is
// ready once server-runtime.json shows the launched pid and our port AND
// /.well-known/t3/environment answers 2xx; after --release-delay the marker is
// removed only if it still holds what we wrote (desktop releaseUpdateMarker).
//
// Stress modes keep an explicit 10 s observation deadline for frozen clients
// (named in the JSON): e1 freezes all clients; marker-lead freezes the server
// and clients at exactly 0/50/200 ms after the marker to count each client's
// ESTABLISHED sockets, then (except the frozen variant) thaws the clients and
// SIGTERMs the server; e2 measures old clients spinning on a missing thread
// against a same-session unfrozen control (Amendment 4 gate).
//
// One JSON report on stdout ({valid:false, error} on failure, exit 1). Owns
// every process it starts, PTY grandchildren included; on exit, failure,
// SIGINT or SIGTERM it stops them all and waits before removing the temp dir.
import fs from "node:fs";
import os from "node:os";
import net from "node:net";
import path from "node:path";
import http from "node:http";
import { spawn, execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { connectWs } from "../ws.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i < 0 ? fallback : process.argv[i + 1];
};
const mode = arg("--mode", "update");
const N = Number(arg("--clients", 3));
// realpath: threads.mjs compares argv[1] with its own resolved URL (/tmp is a symlink on macOS).
const root = fs.realpathSync(path.resolve(arg("--client-root", path.join(here, ".."))));
const restartDelay = Number(arg("--restart-delay", 5000));
const releaseDelay = Number(arg("--release-delay", 2000));
const observe = Number(arg("--observe", 12000));
const readyTimeout = Number(arg("--ready-timeout", 60000));
const fault = arg("--fault", "");
const pidLog = arg("--pid-log");
const T3 = process.env.T3_REAL_BIN || path.join(os.homedir(), ".t3/bin/t3");
const DESKTOP_STOP_GRACE = 5000; // SIGTERM, then SIGKILL (desktop backend stop)
const OBSERVATION_DEADLINE = 10000; // frozen-client stress modes only
const TITLES = ["t3upd-a", "t3upd-b"];
const CLIENT_PATHS = ["/api/auth/websocket-ticket/rpc", "/ws", "/api/orchestration/shell", "/.well-known/t3/environment"];
const HARNESS_UA = "t3upd-repro-harness";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor((xs.length - 1) / 2)];

const base = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-repro-"));
const home = path.join(base, "home");
const project = path.join(base, "project");
const runtimeFile = path.join(home, "userdata", "server-runtime.json");
const marker = path.join(home, "runtime", "desktop-update-in-progress");
const spawnLog = path.join(base, "cli-spawns.log");
for (const dir of [home, project, path.join(base, "client-home"), path.join(home, "runtime")])
  fs.mkdirSync(dir, { recursive: true });
const log = (line) => pidLog && fs.appendFileSync(pidLog, `${line}\n`);
log(`base ${base}`);

// ── process ownership ────────────────────────────────────────────────────────
const owned = new Set(); // ChildProcess handles
const strays = new Set(); // pids we do not parent: PTY runners' TUIs
let cleaning = false;
function own(child) {
  if (cleaning) {
    child.kill("SIGKILL");
    throw new Error("cleanup in progress");
  }
  owned.add(child);
  log(`own ${child.pid}`);
  child.once("exit", () => owned.delete(child));
  return child;
}
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const signal = (pids, sig) => pids.filter((pid) => { try { process.kill(pid, sig); return true; } catch { return false; } });
const kids = (pid) => { try { return execFileSync("pgrep", ["-P", String(pid)]).toString().trim().split("\n").map(Number).filter(Boolean); } catch { return []; } };
// The real t3 (Electron as Node) must not inherit a test guard or our T3 env.
const t3env = () => {
  const env = { ...process.env, T3CODE_HOME: home };
  for (const k of ["NODE_OPTIONS", "T3UPD_GUARD_HOME", "T3UPD_GUARD_REAL_HOME", "T3_URL", "T3_SESSION_TOKEN"]) delete env[k];
  return env;
};
function t3(args) {
  return new Promise((resolve, reject) => {
    const child = own(spawn(T3, args, { env: t3env(), stdio: ["ignore", "pipe", "ignore"] }));
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.once("exit", (code, sig) => (code === 0 ? resolve(out) : reject(new Error(`t3 ${args[0]} ${args[1] || ""} exited ${code ?? sig}`))));
  });
}
async function cleanup() {
  if (cleaning) return;
  cleaning = true;
  for (const c of owned) for (const k of kids(c.pid)) strays.add(k);
  const pids = () => [...[...owned].map((c) => c.pid), ...[...strays].filter(alive)];
  signal(pids(), "SIGCONT");
  signal(pids(), "SIGTERM");
  for (let i = 0; i < 20 && pids().length; i++) await sleep(100);
  signal(pids(), "SIGKILL");
  for (let i = 0; i < 50 && pids().length; i++) await sleep(100);
  fs.rmSync(base, { recursive: true, force: true });
}
process.once("SIGINT", () => cleanup().then(() => process.exit(130)));
process.once("SIGTERM", () => cleanup().then(() => process.exit(143)));
process.on("uncaughtException", (e) => {
  process.stdout.write(`${JSON.stringify({ mode, valid: false, error: e.message })}\n`);
  cleanup().then(() => process.exit(1));
});

// ── server lifecycle ─────────────────────────────────────────────────────────
const freePort = () => new Promise((resolve) => {
  const s = net.createServer().listen(0, "127.0.0.1", () => {
    const { port } = s.address();
    s.close(() => resolve(port));
  });
});
const exited = (child, ms) => new Promise((resolve) => {
  if (child.exitCode !== null || child.signalCode !== null) return resolve(true);
  const timer = setTimeout(() => resolve(false), ms);
  child.once("exit", () => { clearTimeout(timer); resolve(true); });
});
const readRuntime = () => { try { return JSON.parse(fs.readFileSync(runtimeFile, "utf8")); } catch { return null; } };
const envStatus = (port) => new Promise((resolve) => {
  const req = http.get({ host: "127.0.0.1", port, path: "/.well-known/t3/environment", agent: false,
    headers: { "user-agent": HARNESS_UA }, timeout: 1000 }, (res) => { res.resume(); resolve(res.statusCode); });
  req.on("error", () => resolve(0));
  req.on("timeout", () => req.destroy());
});
// Ready = the launched process published our port AND answers the environment endpoint.
async function serve(port) {
  const child = own(spawn(T3, ["serve", "--base-dir", home, "--port", String(port), "--host", "127.0.0.1",
    "--no-browser", project], { env: t3env(), stdio: "ignore" }));
  const deadline = Date.now() + readyTimeout;
  let seen = null;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) throw new Error("isolated t3 serve exited during startup");
    const r = readRuntime();
    if (r?.pid === child.pid && r.port === port) {
      const status = await envStatus(port);
      seen = { pid: r.pid, port, envStatus: status };
      if (status >= 200 && status < 300) return { child, runtime: r, readyAt: Date.now(), ...seen };
    } else if (r) seen = { pid: r.pid, port: r.port, expectedPid: child.pid };
    await sleep(100);
  }
  throw new Error(`successor not ready: ${JSON.stringify(seen)}`);
}
async function terminate(server, deadlineMs, deadlineKind) {
  const termAt = Date.now();
  server.child.kill("SIGTERM");
  const graceful = await exited(server.child, deadlineMs);
  if (!graceful) server.child.kill("SIGKILL");
  await exited(server.child, 5000);
  return { termAt, exitAt: Date.now(), exitMs: Date.now() - termAt, killed: !graceful, deadline: { kind: deadlineKind, ms: deadlineMs } };
}
function writeMarker() {
  const at = Date.now();
  const body = JSON.stringify({ startedAt: at, expiresAt: at + 60_000 });
  fs.writeFileSync(`${marker}.tmp`, body);
  fs.renameSync(`${marker}.tmp`, marker);
  return { at, body };
}
// Like desktop releaseUpdateMarker: remove only the marker contents we wrote.
function release(written) {
  let current = null;
  try { current = fs.readFileSync(marker, "utf8"); } catch {}
  if (current !== written.body) return { released: false, preserved: current !== null };
  fs.rmSync(marker, { force: true });
  return { released: true, at: Date.now() };
}

// ── setup and clients ────────────────────────────────────────────────────────
function dispatch(url, token, payload) {
  return new Promise((resolve, reject) => {
    const req = http.request(`${url}/api/auth/websocket-ticket/rpc`, { method: "POST", agent: false,
      headers: { authorization: `Bearer ${token}`, "user-agent": HARNESS_UA } }, (res) => {
      let body = "";
      res.on("data", (d) => (body += d));
      res.on("end", () => {
        if (res.statusCode !== 200) return reject(new Error(`ticket HTTP ${res.statusCode}`));
        const ws = connectWs(`${url.replace(/^http/, "ws")}/ws?orchestrationProtocol=2&wsTicket=${encodeURIComponent(JSON.parse(body).ticket)}`);
        ws.onopen = () => ws.send(JSON.stringify({ _tag: "Request", id: "1", tag: "orchestration.dispatchCommand", payload, headers: [] }));
        ws.onmessage = (e) => {
          const m = JSON.parse(String(e.data));
          if (m._tag !== "Exit") return;
          m.exit?._tag === "Success" ? resolve() : reject(new Error(`${payload.type} failed`));
          ws.close();
        };
        ws.onclose = () => reject(new Error("dispatch socket closed"));
      });
    });
    req.on("error", reject);
    req.end();
  });
}
async function setup() {
  const port = await freePort();
  const url = `http://127.0.0.1:${port}`;
  const server = await serve(port);
  const token = (await t3(["auth", "session", "issue", "--base-dir", home, "--scope", "orchestration:read",
    "--scope", "orchestration:operate", "--ttl", "30m", "--label", "t3upd-repro", "--token-only"])).trim();
  fs.writeFileSync(path.join(base, "token"), token, { mode: 0o600 });
  const projectId = /Added project (\S+)/.exec(await t3(["project", "add", "--base-dir", home, project]))?.[1];
  const threadId = crypto.randomUUID();
  await dispatch(url, token, { type: "thread.create", commandId: crypto.randomUUID(), threadId, projectId,
    title: TITLES[0], modelSelection: { instanceId: "codex", model: "gpt-5.4" }, runtimeMode: "full-access",
    interactionMode: "default", branch: null, worktreePath: null, createdBy: "user", creationSource: "web" });
  const stub = path.join(base, "t3-stub");
  fs.writeFileSync(stub, `#!${process.execPath}\nrequire("fs").appendFileSync(${JSON.stringify(spawnLog)}, Date.now() + " " + process.argv.slice(2, 4).join(" ") + "\\n");\nprocess.exit(1);\n`, { mode: 0o755 });
  const env = { ...process.env, HOME: path.join(base, "client-home"), T3CODE_HOME: home, T3_URL: url,
    T3_SESSION_TOKEN: token, T3_BIN: stub, T3_THREAD_DEBUG: "" };
  return { port, url, token, server, threadId, env, rename: (title) =>
    dispatch(url, token, { type: "thread.metadata.update", commandId: crypto.randomUUID(), threadId, title }) };
}

// Each client records when it first showed each title: feeds in their
// snapshots, TUIs in their OSC 7501 status reports (msg = thread title).
function attach(env, { feeds: nf, tuis: nt, thread, deadThread = 0 }) {
  const clients = [];
  for (let i = 0; i < nf; i++) {
    const child = own(spawn(process.execPath, [path.join(root, "threads.mjs")], { env, stdio: ["ignore", "pipe", "ignore"] }));
    const c = { kind: "feed", child, pid: child.pid, seen: {} };
    let buf = "";
    child.stdout.on("data", (d) => {
      const lines = (buf += d).split("\n");
      buf = lines.pop();
      for (const l of lines) for (const t of TITLES) if (l.includes('"type":"snapshot"') && l.includes(`"title":"${t}"`)) c.seen[t] ??= Date.now();
    });
    clients.push(c);
  }
  for (let i = 0; i < nt; i++) {
    const id = i < deadThread ? crypto.randomUUID() : thread;
    const child = own(spawn("python3", [path.join(here, "../test/support/pty-run.py"), "40", "120", "--",
      process.execPath, path.join(root, "main.mjs"), id], { env, stdio: ["pipe", "pipe", "ignore"] }));
    const c = { kind: "tui", child, seen: {} };
    let buf = "";
    child.stdout.on("data", (d) => {
      buf = (buf + d.toString("latin1")).slice(-4096);
      for (const t of TITLES) if (buf.includes(`app=t3:msg=${t}\x1b\\`)) c.seen[t] ??= Date.now();
    });
    clients.push(c);
  }
  return clients;
}
async function clientPids(clients) {
  for (let i = 0; i < 50; i++) {
    for (const c of clients) if (c.kind === "tui" && !c.pid) {
      c.pid = kids(c.child.pid)[0];
      if (c.pid) { strays.add(c.pid); log(`grandchild ${c.pid}`); }
    }
    if (clients.every((c) => c.pid)) return clients.map((c) => c.pid);
    await sleep(100);
  }
  throw new Error("a TUI process did not start");
}
// Every client must show `title`; returns per-client times or throws (invalid evidence).
async function observed(clients, title, ms, since = 0) {
  const end = Date.now() + ms;
  while (Date.now() < end && clients.some((c) => !c.seen[title])) await sleep(50);
  const missing = clients.filter((c) => !c.seen[title]).map((c) => `${c.kind}:${c.pid}`);
  if (missing.length) throw new Error(`no "${title}" observation from ${missing.join(", ")}`);
  return clients.map((c) => ({ kind: c.kind, pid: c.pid, ms: c.seen[title] - since }));
}
const stopClients = async (clients) => {
  for (const c of clients) if (c.kind === "tui") c.child.stdin.end("stop\n");
  signal(clients.map((c) => c.pid).filter(Boolean), "SIGTERM");
  for (let i = 0; i < 30 && clients.some((c) => c.child.exitCode === null); i++) await sleep(100);
  signal(clients.map((c) => c.pid).filter(Boolean), "SIGKILL");
  for (const c of clients) c.child.kill("SIGKILL");
};
// Per-client ESTABLISHED connections to the server (lsof; names only). A
// failed sampler is invalid evidence, never "zero sockets".
function sockets(port, pids) {
  const sampler = fault === "sampler" ? "/usr/bin/false" : "lsof";
  let out = "";
  try {
    out = execFileSync(sampler, ["-nP", "-a", "-p", pids.join(","), `-iTCP@127.0.0.1:${port}`, "-sTCP:ESTABLISHED", "-Fpn"],
      { stdio: ["ignore", "pipe", "pipe"] }).toString();
  } catch (e) {
    if (e.status !== 1 || String(e.stderr || "").trim() || fault === "sampler") throw new Error("socket sampler failed");
  }
  const counts = Object.fromEntries(pids.map((p) => [p, 0]));
  let pid;
  for (const line of out.split("\n")) {
    if (line[0] === "p") pid = Number(line.slice(1));
    else if (line[0] === "n" && line.endsWith(`->127.0.0.1:${port}`) && pid in counts) counts[pid]++;
  }
  return counts;
}
const established = (port, pids) => Object.values(sockets(port, pids)).reduce((a, b) => a + b, 0);
async function connectedAll(port, pids, ms = 30000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (Object.values(sockets(port, pids)).every((n) => n > 0)) return;
    await sleep(200);
  }
  throw new Error("not every client reconnected");
}
const stopped = (pids) => pids.filter((pid) => {
  try { return execFileSync("ps", ["-o", "stat=", "-p", String(pid)]).toString().includes("T"); } catch { return false; }
}).length;

// Spans are flushed when they end: read the trace after the clients left.
function traceSpans() {
  const dir = path.join(home, "userdata", "logs");
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => f.startsWith("server.trace.ndjson")).flatMap((f) =>
    fs.readFileSync(path.join(dir, f), "utf8").split("\n").flatMap((line) => {
      try {
        const s = JSON.parse(line); // only name, path, user agent and start time are used
        return [{ name: s.name, path: s.attributes?.["url.path"], agent: s.attributes?.["user_agent.original"],
          at: Number(BigInt(s.startTimeUnixNano) / 1_000_000n) }];
      } catch { return []; }
    }));
}
const isHttp = (s) => /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/.test(s.name);

// ── modes ────────────────────────────────────────────────────────────────────
async function lifecycle() {
  const port = await freePort();
  const first = await serve(port);
  const written = writeMarker();
  const stop = await terminate(first, DESKTOP_STOP_GRACE, "desktop-stop-grace");
  await sleep(restartDelay);
  let successor;
  try {
    successor = await serve(port);
  } catch (e) {
    return { mode, valid: false, error: e.message, stop, markerHeld: fs.existsSync(marker) };
  }
  return { mode, valid: true, markerAt: written.at, stop, successor: { pid: successor.pid, envStatus: successor.envStatus,
    readyAt: successor.readyAt }, marker: release(written) };
}

async function update(ctx) {
  const clients = attach(ctx.env, { feeds: N, tuis: N, thread: ctx.threadId, deadThread: fault === "no-first-chunk" ? 1 : 0 });
  await clientPids(clients);
  const initial = await observed(clients, TITLES[0], 30000);
  await sleep(1000);
  const written = writeMarker();
  const stop = await terminate(ctx.server, DESKTOP_STOP_GRACE, "desktop-stop-grace");
  let downtimeConnects = 0;
  const sentinel = net.createServer((s) => { downtimeConnects++; s.destroy(); }).listen(ctx.port, "127.0.0.1");
  await sleep(restartDelay);
  await new Promise((r) => sentinel.close(r));
  const second = await serve(ctx.port);
  await sleep(releaseDelay);
  const rel = release(written);
  if (!rel.released) throw new Error("our marker was replaced; not released");
  await ctx.rename(TITLES[1]);
  const recovery = await observed(clients, TITLES[1], observe, rel.at);
  await stopClients(clients);
  await sleep(2000);
  const spans = traceSpans();
  await terminate(second, DESKTOP_STOP_GRACE, "desktop-stop-grace");
  const inWindow = spans.filter((s) => isHttp(s) && s.at >= written.at && s.at < rel.at);
  const client = inWindow.filter((s) => s.agent !== HARNESS_UA && CLIENT_PATHS.includes(s.path));
  const spawns = fs.existsSync(spawnLog) ? fs.readFileSync(spawnLog, "utf8").trim().split("\n").map((l) => Number(l.split(" ")[0])) : [];
  return {
    mode, valid: true, serverVersion: second.runtime.serverVersion, clients: { feeds: N, tuis: N },
    timings: { markerAt: written.at, termAt: stop.termAt, exitMs: stop.exitMs, killed: stop.killed, deadline: stop.deadline,
      successorReadyAt: second.readyAt, releaseAt: rel.at, markerWindowMs: rel.at - written.at, restartDelayMs: restartDelay, releaseDelayMs: releaseDelay },
    successor: { pid: second.pid, envStatus: second.envStatus },
    markerWindow: {
      clientRequests: client.length,
      ticketPosts: client.filter((s) => s.path === CLIENT_PATHS[0]).length,
      wsUpgrades: client.filter((s) => s.path === "/ws").length,
      downtimeConnectAttempts: downtimeConnects,
      otherRequests: inWindow.filter((s) => s.agent !== HARNESS_UA && !CLIENT_PATHS.includes(s.path)).map((s) => `${s.name} ${s.path}`),
    },
    // Per client: ms from marker release to showing the post-release title.
    recovery: { perClient: recovery, maxMs: Math.max(...recovery.map((r) => r.ms)), minMs: Math.min(...recovery.map((r) => r.ms)) },
    initialObservations: initial.length,
    cliSpawns: { markerWindow: spawns.filter((s) => s >= written.at && s < rel.at).length, total: spawns.length },
  };
}

// Marker, then at exactly `lead` ms freeze the server and every client so the
// count is the state at that instant; thaw the clients (unless frozen) and
// SIGTERM the server.
async function markerLead(ctx, runs) {
  const clients = attach(ctx.env, { feeds: N, tuis: N, thread: ctx.threadId });
  const pids = await clientPids(clients);
  await observed(clients, TITLES[0], 30000);
  let server = ctx.server;
  const results = [];
  const cases = [[0, false], [50, false], [200, false], [200, true]];
  for (const [lead, frozen] of cases) for (let i = 0; i < runs; i++) {
    await connectedAll(ctx.port, pids);
    await sleep(1000);
    const before = established(ctx.port, pids);
    const written = writeMarker();
    await sleep(lead);
    signal([server.child.pid], "SIGSTOP");
    const freezeAt = Date.now();
    signal(pids, "SIGSTOP");
    const sampleStart = Date.now();
    const perClient = sockets(ctx.port, pids);
    const sampleMs = Date.now() - sampleStart;
    const frozenClients = stopped(pids);
    if (!frozen) signal(pids, "SIGCONT");
    const deadline = frozen ? [OBSERVATION_DEADLINE, "frozen-observation"] : [DESKTOP_STOP_GRACE, "desktop-stop-grace"];
    const termPromise = terminate(server, ...deadline);
    signal([server.child.pid], "SIGCONT");
    const stop = await termPromise;
    const counts = Object.values(perClient);
    results.push({ leadMs: lead, frozen, actualLeadMs: freezeAt - written.at, sampleMs, before,
      establishedAtTerm: counts.reduce((a, b) => a + b, 0), clientsHoldingSockets: counts.filter((n) => n > 0).length,
      clientsFrozenAtSample: frozenClients, clientsAlive: pids.filter(alive).length, ...stop });
    if (frozenClients !== pids.length || pids.some((p) => !alive(p))) throw new Error("a client was missing or not frozen at the sample");
    signal(pids, "SIGCONT");
    release(written);
    server = await serve(ctx.port);
  }
  await stopClients(clients);
  const summary = cases.map(([lead, frozen]) => {
    const rs = results.filter((r) => r.leadMs === lead && r.frozen === frozen);
    return { leadMs: lead, frozen, medianActualLeadMs: median(rs.map((r) => r.actualLeadMs)), medianExitMs: median(rs.map((r) => r.exitMs)),
      killed: rs.filter((r) => r.killed).length, established: rs.map((r) => `${r.establishedAtTerm}/${r.before}`), deadline: rs[0].deadline };
  });
  return { mode, valid: true, clients: { feeds: N, tuis: N }, summary, runs: results };
}

async function e1(ctx, runs) {
  const freeze = arg("--freeze", "all");
  const tuis = Number(arg("--tuis", 6));
  const results = [];
  let server = ctx.server;
  for (let i = 0; i < runs; i++) {
    const clients = attach(ctx.env, { feeds: 1, tuis, thread: ctx.threadId });
    const pids = await clientPids(clients);
    await observed(clients, TITLES[0], 30000);
    await sleep(1000);
    if (freeze === "all") signal(pids, "SIGSTOP");
    log("phase frozen");
    const frozenCount = stopped(pids);
    const deadline = freeze === "all" ? [OBSERVATION_DEADLINE, "frozen-observation"] : [DESKTOP_STOP_GRACE, "desktop-stop-grace"];
    results.push({ clients: pids.length, frozen: frozenCount, ...(await terminate(server, ...deadline)) });
    signal(pids, "SIGKILL");
    await stopClients(clients);
    if (i < runs - 1) server = await serve(ctx.port);
  }
  return { mode, valid: true, freeze, tuis, runs: results, medianExitMs: median(results.map((r) => r.exitMs)),
    killed: results.filter((r) => r.killed).length };
}

// Amendment 4: old clients spinning on a missing thread, SIGTERM at a random
// phase; gate against a same-session unfrozen control (6 TUIs + 1 feed).
async function e2(ctx, runs) {
  const controlRuns = Number(arg("--control-runs", 5));
  let server = ctx.server;
  const control = [];
  const steady = attach(ctx.env, { feeds: 1, tuis: 6, thread: ctx.threadId });
  const steadyPids = await clientPids(steady);
  await observed(steady, TITLES[0], 30000);
  for (let i = 0; i < controlRuns; i++) {
    await connectedAll(ctx.port, steadyPids);
    await sleep(1000);
    control.push(await terminate(server, DESKTOP_STOP_GRACE, "desktop-stop-grace"));
    server = await serve(ctx.port);
  }
  await stopClients(steady);
  const spinners = attach(ctx.env, { feeds: 0, tuis: 3, thread: ctx.threadId, deadThread: 3 });
  const spinPids = await clientPids(spinners);
  await sleep(2000);
  const results = [];
  for (let i = 0; i < runs; i++) {
    const phase = Math.round(Math.random() * 1000);
    await sleep(1500 + phase);
    const spinnersAlive = spinPids.filter(alive).length;
    const stop = await terminate(server, DESKTOP_STOP_GRACE, "desktop-stop-grace");
    results.push({ phaseMs: phase, spinnersAlive, serverReadyAt: server.readyAt, ...stop });
    if (i < runs - 1) server = await serve(ctx.port);
  }
  await stopClients(spinners);
  await sleep(1000);
  const ups = traceSpans().filter((s) => s.name === "GET" && s.path === "/ws" && s.agent !== HARNESS_UA);
  for (const r of results) r.wsUpgradesDuringRun = ups.filter((s) => s.at >= r.serverReadyAt && s.at < r.termAt).length;
  const controlMedianMs = median(control.map((r) => r.exitMs));
  const exits = results.map((r) => r.exitMs);
  const gate = { killed: results.filter((r) => r.killed).length, maxExitMs: Math.max(...exits), medianExitMs: median(exits),
    controlMedianMs, limitMs: Math.round(controlMedianMs * 1.1),
    spinningEvery: results.every((r) => r.spinnersAlive === 3 && r.wsUpgradesDuringRun >= 3) };
  gate.pass = gate.killed === 0 && gate.maxExitMs <= 2000 && gate.medianExitMs <= controlMedianMs * 1.1 && gate.spinningEvery;
  return { mode, valid: true, control: control.map((r) => ({ exitMs: r.exitMs, killed: r.killed })), runs: results, gate };
}

try {
  let report;
  if (mode === "lifecycle") report = await lifecycle();
  else {
    const modes = { update, "marker-lead": markerLead, e1, e2 };
    if (!modes[mode]) throw new Error(`unknown --mode ${mode}`);
    const ctx = await setup();
    log("phase setup-done");
    report = await modes[mode](ctx, Number(arg("--runs", { e2: 20, "marker-lead": 3 }[mode] ?? 5)));
  }
  process.stdout.write(`${JSON.stringify({ label: arg("--label", path.basename(root)), ...report }, null, 2)}\n`);
  if (!report.valid) process.exitCode = 1;
} catch (e) {
  process.stdout.write(`${JSON.stringify({ label: arg("--label", path.basename(root)), mode, valid: false, error: e.message })}\n`);
  process.exitCode = 1;
} finally {
  await cleanup();
}
