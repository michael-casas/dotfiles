// Hermetic checks of scripts/update-repro.mjs itself (F07, F08): a fake `t3`
// (test/support/fake-t3-cli.mjs) stands in for the real CLI and server.
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../scripts/update-repro.mjs", import.meta.url));
const fakeCli = fileURLToPath(new URL("./support/fake-t3-cli.mjs", import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

// Run the harness; `interrupt(pidLogText)` returning true sends SIGINT.
function harness(t, args, { faults = "", interrupt, argsLog } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-harness-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const pidLog = path.join(dir, "pids.log");
  const fakePids = path.join(dir, "fake-pids.log");
  const read = (f) => (fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "");
  const child = spawn(process.execPath, [script, ...args, "--pid-log", pidLog], {
    env: { ...process.env, T3_REAL_BIN: fakeCli, FAKE_T3: faults, FAKE_T3_PIDS: fakePids, ...(argsLog ? { FAKE_T3_ARGS: argsLog } : {}) },
    stdio: ["ignore", "pipe", "ignore"],
  });
  let stdout = "";
  child.stdout.on("data", (d) => (stdout += d));
  const timer = interrupt && setInterval(() => {
    if (interrupt(read(pidLog) + read(fakePids))) { clearInterval(timer); child.kill("SIGINT"); }
  }, 50);
  return new Promise((resolve) => child.on("exit", async (code) => {
    clearInterval(timer);
    const lines = (read(pidLog) + read(fakePids)).split("\n");
    const pids = lines.map((l) => Number(l.split(" ").at(-1))).filter((n) => n > 1);
    const base = lines.find((l) => l.startsWith("base "))?.slice(5);
    await sleep(300);
    let report = null;
    try { report = JSON.parse(stdout); } catch {}
    resolve({ code, report, pids, alivePids: pids.filter(alive), baseLeft: !!base && fs.existsSync(base) });
  }));
}
const clean = (r) => {
  assert.deepEqual(r.alivePids, [], "no owned process survives");
  assert.equal(r.baseLeft, false, "temp dir (token included) removed");
};

test("F08: update-mode escalation is the desktop's 5 s SIGTERM grace", async (t) => {
  const r = await harness(t, ["--mode", "lifecycle", "--restart-delay", "0"], { faults: "term-resistant" });
  assert.equal(r.report.valid, true, JSON.stringify(r.report));
  assert.equal(r.report.stop.killed, true);
  assert.deepEqual(r.report.stop.deadline, { kind: "desktop-stop-grace", ms: 5000 });
  assert.ok(r.report.stop.exitMs >= 5000 && r.report.stop.exitMs < 6500, `exit after ${r.report.stop.exitMs} ms`);
  assert.equal(r.report.marker.released, true);
  clean(r);
});

for (const fault of ["stale-pid", "env-down"])
test(`F08: a successor with ${fault} never completes the trial; the marker is held`, async (t) => {
  const r = await harness(t, ["--mode", "lifecycle", "--restart-delay", "0", "--ready-timeout", "2000"], { faults: fault });
  assert.equal(r.code, 1);
  assert.equal(r.report.valid, false);
  assert.match(r.report.error, /successor not ready/);
  assert.equal(r.report.markerHeld, true);
  clean(r);
});

test("F08: a marker replaced by someone else is preserved, not released", async (t) => {
  const r = await harness(t, ["--mode", "lifecycle", "--restart-delay", "0"], { faults: "replace-marker" });
  assert.equal(r.report.valid, true, JSON.stringify(r.report));
  assert.deepEqual(r.report.marker, { released: false, preserved: true });
  clean(r);
});

for (const [phase, faults] of [["auth", "auth-hang"], ["project", "project-hang"]])
test(`F07: SIGINT during ${phase} setup stops every owned process and removes the temp dir`, async (t) => {
  const r = await harness(t, ["--mode", "update"], { faults, interrupt: (text) => new RegExp(`^${phase} `, "m").test(text) });
  assert.equal(r.code, 130);
  assert.ok(r.pids.length >= 2, "server and setup child were recorded");
  clean(r);
});

test("F07: a setup failure stops everything and reports invalid evidence", async (t) => {
  const r = await harness(t, ["--mode", "update"], { faults: "exit-at-once" });
  assert.equal(r.code, 1);
  assert.equal(r.report.valid, false);
  assert.match(r.report.error, /exited during startup/);
  clean(r);
});

test("F07: SIGINT during a frozen-client trial stops frozen TUIs and the server", async (t) => {
  const r = await harness(t, ["--mode", "e1", "--runs", "1", "--tuis", "2"], { interrupt: (text) => text.includes("phase frozen") });
  assert.equal(r.code, 130);
  assert.ok(r.pids.length >= 5, `recorded ${r.pids.length} pids (server, feed, PTY runners, TUIs)`);
  clean(r);
});

test("F11: every t3 the harness runs gets only the allocated port and its temp base", async (t) => {
  const argsLog = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-args-")), "args.ndjson");
  t.after(() => fs.rmSync(path.dirname(argsLog), { recursive: true, force: true }));
  const r = await harness(t, ["--mode", "e1", "--runs", "1", "--tuis", "1", "--freeze", "none"], { argsLog });
  assert.equal(r.report.valid, true, JSON.stringify(r.report));
  const calls = fs.readFileSync(argsLog, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  const base = (call) => call.args[call.args.indexOf("--base-dir") + 1];
  assert.deepEqual(calls.map((c) => c.args.slice(0, 2).join(" ")).sort(), ["auth session", "project add", "serve --base-dir"]);
  const home = base(calls[0]);
  assert.match(home, /t3upd-repro-[^/]+\/home$/);
  const servePort = calls.find((c) => c.args[0] === "serve").args;
  const url = `http://127.0.0.1:${servePort[servePort.indexOf("--port") + 1]}`;
  for (const call of calls) {
    assert.equal(base(call), home);
    assert.deepEqual(call.env, { T3CODE_HOME: home, T3_URL: url }, "temp home and isolated URL only; no guard or token");
  }
  const serve = calls.find((c) => c.args[0] === "serve").args;
  const port = serve[serve.indexOf("--port") + 1];
  assert.notEqual(port, "3773");
});

test("F09: marker-lead sends TERM at the requested lead and samples while everything is stopped", async (t) => {
  const r = await harness(t, ["--mode", "marker-lead", "--runs", "1", "--clients", "1"]);
  assert.equal(r.report.valid, true, JSON.stringify(r.report));
  for (const run of r.report.runs) {
    const c = run.clock;
    assert.ok(c.termLeadMs >= run.leadMs && c.termLeadMs - run.leadMs <= 15, `TERM ${c.termLeadMs} ms for lead ${run.leadMs}`);
    assert.ok(c.sampleStartAt >= run.termAt && c.sampleEndAt >= c.sampleStartAt, "sampled after TERM was queued");
    assert.ok(c.thawAt >= c.sampleEndAt, "thawed only after the sample");
    assert.equal(run.clientsFrozenAtTerm, 2);
  }
  clean(r);
});
