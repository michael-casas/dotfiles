// Opt-in: runs scripts/update-repro.mjs against an ISOLATED real `t3 serve`
// (never the live server). Runs only when T3UPD_REAL is exactly "1", and then
// requires T3UPD_OLD_ROOT (an extracted pre-fix t3-thread directory) for the
// paired old/new proof, and T3_REAL_BIN or the real ~/.t3/bin/t3.
//   T3UPD_REAL=1 T3UPD_OLD_ROOT=/tmp/old/nvim/tools/t3-thread node --test test/update-repro.test.mjs
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../scripts/update-repro.mjs", import.meta.url));
const skip = process.env.T3UPD_REAL !== "1" && "set T3UPD_REAL=1 to run against an isolated t3 serve";
// The guard replaced HOME; the real CLI path comes from the real home.
const bin = process.env.T3_REAL_BIN || path.join(process.env.T3UPD_GUARD_REAL_HOME || "", ".t3/bin/t3");
const repro = (...args) => new Promise((resolve) => {
  execFile(process.execPath, [script, ...args], { timeout: 900_000, maxBuffer: 1 << 24, env: { ...process.env, T3_REAL_BIN: bin } },
    (error, stdout) => resolve({ code: error?.code ?? 0, report: JSON.parse(stdout) }));
});
const oldRoot = () => {
  assert.ok(process.env.T3UPD_OLD_ROOT, "T3UPD_OLD_ROOT is required for the paired old/new proof");
  return process.env.T3UPD_OLD_ROOT;
};

test("update: every client recovers; head makes no marker-window load or CLI spawn; old does", { skip, timeout: 900_000 }, async () => {
  const [head, old] = await Promise.all([repro("--label", "head"), repro("--client-root", oldRoot(), "--label", "old")]);
  for (const r of [head, old]) {
    assert.equal(r.report.valid, true, JSON.stringify(r.report));
    assert.equal(r.report.recovery.perClient.length, 6, "every client observed");
    assert.ok(r.report.recovery.minMs >= 0, "recovery measured from the release");
  }
  assert.equal(head.report.markerWindow.clientRequests, 0);
  assert.equal(head.report.markerWindow.downtimeConnectAttempts, 0);
  assert.equal(head.report.cliSpawns.markerWindow, 0);
  assert.ok(head.report.recovery.maxMs < 2000, `head recovery ${head.report.recovery.maxMs} ms`);
  assert.ok(old.report.markerWindow.clientRequests + old.report.markerWindow.downtimeConnectAttempts > 0, "old clients load the server");
});

test("marker-lead: head holds no socket 200 ms after the marker, and frozen clients cannot hold shutdown", { skip, timeout: 900_000 }, async () => {
  const { report } = await repro("--mode", "marker-lead", "--runs", "1", "--label", "head");
  assert.equal(report.valid, true, JSON.stringify(report));
  for (const r of report.runs) {
    assert.equal(r.clientsFrozenAtSample, 6);
    // At 0/50 ms the release may still be in flight (reported, not gated).
    if (r.leadMs === 200) assert.equal(r.establishedAtTerm, 0, JSON.stringify(r));
  }
  const frozen = report.runs.find((r) => r.frozen);
  assert.equal(frozen.killed, false, JSON.stringify(frozen));
});

for (const fault of ["no-first-chunk", "sampler"])
test(`invalid evidence fails: ${fault}`, { skip, timeout: 900_000 }, async () => {
  const { code, report } = await repro("--mode", fault === "sampler" ? "marker-lead" : "update", "--runs", "1", "--fault", fault);
  assert.equal(code, 1);
  assert.equal(report.valid, false);
  assert.match(report.error, fault === "sampler" ? /sampler failed/ : /no "t3upd-a" observation/);
});
