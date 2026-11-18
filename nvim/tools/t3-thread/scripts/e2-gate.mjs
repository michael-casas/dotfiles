// E2 (stress) statistics, kept pure for unit tests.
// Conventional median: the mean of the two middle values for an even count.
export function median(xs) {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
// Amendment 6 safety gate: a complete packet (20 runs, 3 distinct old TUI
// pids) in which, in every run, every pid made at least one websocket upgrade
// before TERM; no SIGKILL; every exit within 2 s. Anything less never passes
// (diagnostics are still reported). The median vs the same-session control is
// a diagnostic only.
export const E2_RUNS = 20, E2_PIDS = 3;
export function e2Gate(runs, pids, controlExits = []) {
  const complete = runs.length === E2_RUNS && pids.length === E2_PIDS && new Set(pids).size === E2_PIDS;
  const everyPid = runs.every((r) => pids.every((p) => (r.upgradesByPid?.[p] ?? 0) > 0));
  const killed = runs.filter((r) => r.killed).length;
  const maxExitMs = Math.max(...runs.map((r) => r.exitMs));
  return {
    pass: complete && everyPid && killed === 0 && maxExitMs <= 2000,
    complete, everyPidUpgradedEveryRun: everyPid, killed, maxExitMs,
    diagnostic: { medianExitMs: median(runs.map((r) => r.exitMs)), controlMedianMs: controlExits.length ? median(controlExits) : null },
  };
}
