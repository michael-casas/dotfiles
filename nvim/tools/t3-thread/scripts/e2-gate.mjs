// E2 (stress) statistics, kept pure for unit tests.
// Conventional median: the mean of the two middle values for an even count.
export function median(xs) {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
// Amendment 6 safety gate: in every run, every old TUI pid made at least one
// websocket upgrade before TERM; no SIGKILL; every exit within 2 s. The median
// against the same-session control is reported as a diagnostic only.
export function e2Gate(runs, pids, controlExits = []) {
  const everyPid = runs.every((r) => pids.every((p) => (r.upgradesByPid?.[p] ?? 0) > 0));
  const killed = runs.filter((r) => r.killed).length;
  const maxExitMs = Math.max(...runs.map((r) => r.exitMs));
  return {
    pass: runs.length > 0 && everyPid && killed === 0 && maxExitMs <= 2000,
    everyPidUpgradedEveryRun: everyPid, killed, maxExitMs,
    diagnostic: { medianExitMs: median(runs.map((r) => r.exitMs)), controlMedianMs: controlExits.length ? median(controlExits) : null },
  };
}
