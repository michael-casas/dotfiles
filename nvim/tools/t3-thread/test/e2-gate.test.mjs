// E2 gate (Amendment 6) and its median, as pure functions (F10).
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import { median, e2Gate } from "../scripts/e2-gate.mjs";

test("F10: the median is conventional (mean of the two middle values for an even count)", () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  // The critic's 20 independent E2 exits: 947.5 ms (not the lower middle, 943).
  assert.equal(median([942, 996, 952, 1024, 1140, 864, 895, 836, 957, 809, 1035, 1108, 798, 952, 943, 602, 1046, 1273, 837, 692]), 947.5);
});

const run = (upgradesByPid, exitMs = 800, killed = false) => ({ upgradesByPid, exitMs, killed });
const pids = [101, 102, 103];

test("F10: every old TUI pid must upgrade before every TERM; one active spinner is rejected", () => {
  const all = run({ 101: 2, 102: 1, 103: 4 });
  assert.equal(e2Gate([all, all], pids).pass, true);
  const oneSpinner = run({ 101: 9, 102: 0, 103: 0 }); // a busy aggregate from a single pid
  const gate = e2Gate([all, oneSpinner], pids);
  assert.equal(gate.pass, false);
  assert.equal(gate.everyPidUpgradedEveryRun, false);
  assert.equal(e2Gate([run({ 101: 1, 102: 1 })], pids).pass, false, "a pid missing from the record fails");
});

test("F10: any SIGKILL or exit over 2 s fails; the median is a diagnostic only", () => {
  const ok = { 101: 1, 102: 1, 103: 1 };
  assert.equal(e2Gate([run(ok), run(ok, 900, true)], pids).pass, false);
  assert.equal(e2Gate([run(ok), run(ok, 2001)], pids).pass, false);
  const slowMedian = e2Gate([run(ok, 1900), run(ok, 1950)], pids, [500, 600]);
  assert.equal(slowMedian.pass, true, "median above 1.1x control does not gate");
  assert.deepEqual(slowMedian.diagnostic, { medianExitMs: 1925, controlMedianMs: 550 });
  assert.equal(e2Gate([], pids).pass, false);
});
