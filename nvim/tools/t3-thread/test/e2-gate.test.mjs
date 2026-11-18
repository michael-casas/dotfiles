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
const good = run({ 101: 2, 102: 1, 103: 4 });
const twenty = (r = good) => Array.from({ length: 20 }, () => r);

test("F10: only a complete 20-run x 3-pid packet can pass", () => {
  assert.equal(e2Gate(twenty(), pids).pass, true, "complete 20 x 3");
  assert.equal(e2Gate([good], pids).pass, false, "1 run");
  assert.equal(e2Gate(twenty().slice(1), pids).pass, false, "19 runs");
  assert.equal(e2Gate(twenty(), []).pass, false, "no expected pids");
  assert.equal(e2Gate(twenty(run({ 101: 1 })), [101, 101, 101]).pass, false, "duplicate pids");
  assert.equal(e2Gate(twenty(), [101, 102]).pass, false, "two pids");
  const gate = e2Gate([...twenty().slice(1), run({ 101: 9, 102: 0, 103: 0 })], pids);
  assert.equal(gate.pass, false, "one-spinner run");
  assert.equal(gate.everyPidUpgradedEveryRun, false);
});

test("F10: any SIGKILL or exit over 2 s fails; the median is a diagnostic only", () => {
  assert.equal(e2Gate([...twenty().slice(1), run(good.upgradesByPid, 900, true)], pids).pass, false);
  assert.equal(e2Gate([...twenty().slice(1), run(good.upgradesByPid, 2001)], pids).pass, false);
  const slow = e2Gate(twenty(run(good.upgradesByPid, 1950)), pids, [500, 600]);
  assert.equal(slow.pass, true, "median above 1.1x control does not gate");
  assert.deepEqual(slow.diagnostic, { medianExitMs: 1950, controlMedianMs: 550 });
});
