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
  const f = startFeed(options, { openSocket: (signal) => t3.openShellSocket(signal), write: (l) => output.push(JSON.parse(l)) });
  t.after(() => f.close());
  return output;
}
const holdFirstTicket = (held) => (req, res, n) => {
  if (n !== 1) return false;
  held.push(res);
  return true;
};

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
