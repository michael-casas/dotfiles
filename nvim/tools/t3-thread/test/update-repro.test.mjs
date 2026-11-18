// Opt-in: runs scripts/update-repro.mjs against an ISOLATED real `t3 serve`
// (never the live server). Skipped unless T3UPD_REAL=1. Set T3UPD_OLD_ROOT to
// an extracted pre-fix t3-thread directory to also prove the old behaviour.
//   T3UPD_REAL=1 [T3UPD_OLD_ROOT=/tmp/old/nvim/tools/t3-thread] node --test test/update-repro.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const run = promisify(execFile);
const script = fileURLToPath(new URL("../scripts/update-repro.mjs", import.meta.url));
const skip = !process.env.T3UPD_REAL && "set T3UPD_REAL=1 to run against an isolated t3 serve";
const repro = async (...args) =>
  JSON.parse((await run(process.execPath, [script, ...args], { timeout: 900_000, maxBuffer: 1 << 24 })).stdout);

test("update: no client load, no CLI during the marker window; prompt recovery", { skip, timeout: 900_000 }, async () => {
  const r = await repro("--label", "head");
  assert.equal(r.markerWindow.clientRequests, 0);
  assert.equal(r.markerWindow.downtimeConnectAttempts, 0);
  assert.equal(r.cliSpawns.markerWindow, 0);
  for (const ms of Object.values(r.recovery)) assert.ok(ms !== null && ms < 2000, JSON.stringify(r.recovery));
  if (process.env.T3UPD_OLD_ROOT) {
    const old = await repro("--client-root", process.env.T3UPD_OLD_ROOT, "--label", "old");
    assert.ok(old.markerWindow.clientRequests + old.markerWindow.downtimeConnectAttempts > 0, "old clients load the server");
  }
});

test("marker-lead: sockets are released before SIGTERM, so frozen clients cannot hold shutdown", { skip, timeout: 900_000 }, async () => {
  const r = await repro("--mode", "marker-lead", "--runs", "1", "--label", "head");
  const frozen = r.summary.find((c) => c.frozen);
  assert.equal(frozen.killed, 0, JSON.stringify(frozen));
  assert.deepEqual(r.summary.filter((c) => c.sampled && c.leadMs === 200).flatMap((c) => c.established.map((e) => e.split("/")[0])), ["0", "0"]);
});
