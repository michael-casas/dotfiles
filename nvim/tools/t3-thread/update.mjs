// The T3 desktop's update protocol, as seen by a client. While the desktop
// installs an update it writes <T3CODE_HOME>/runtime/desktop-update-in-progress
// (JSON {startedAt, expiresAt} in epoch ms, tmp + rename, TTL 60 s), stops the
// server and removes the marker once the new server has published
// userdata/server-runtime.json. Clients must not connect, and must not run the
// t3 CLI (its app bundle is being swapped), until the marker is gone or expired.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const UPDATING = "T3 updating…";
export const RESTARTED = "T3 server restarted";
const TTL_MS = 60_000; // DESKTOP_UPDATE_IN_PROGRESS_TTL_MS

// Read at call time so tests and the repro harness can point at a temp home.
export const t3Home = () => process.env.T3CODE_HOME || path.join(os.homedir(), ".t3");
const runtimeDir = () => path.join(t3Home(), "runtime");
const markerPath = () => path.join(runtimeDir(), "desktop-update-in-progress");

/**
 * Epoch ms until which an update is in progress, or 0 when none is. Shared
 * contract: absent or expired = no update; valid JSON = until expiresAt;
 * malformed or unreadable = until 60 s after its mtime.
 */
export function updatingUntil(now = Date.now()) {
  let mtime, until;
  try {
    mtime = fs.statSync(markerPath()).mtimeMs;
  } catch {
    return 0;
  }
  until = mtime + TTL_MS; // malformed: present until 60 s after its mtime
  try {
    const { expiresAt } = JSON.parse(fs.readFileSync(markerPath(), "utf8"));
    if (Number.isFinite(expiresAt)) until = expiresAt;
  } catch {}
  return until > now ? until : 0;
}

/**
 * Identity of the server listening on `port`, from userdata/server-runtime.json.
 * Only the non-secret pid, startedAt and serverVersion fields are used.
 */
export function serverIdentity(port) {
  try {
    const file = path.join(t3Home(), "userdata", "server-runtime.json");
    const { pid, startedAt, serverVersion, port: owner } = JSON.parse(fs.readFileSync(file, "utf8"));
    if (Number(owner) !== Number(port)) return null; // another server's record
    return { key: `${pid}@${startedAt}`, serverVersion: String(serverVersion || "unknown") };
  } catch {
    return null;
  }
}

export class UpdatingError extends Error {
  constructor() {
    super("T3 is updating; try again when it is back");
  }
}
export function assertNotUpdating() {
  if (updatingUntil()) throw new UpdatingError();
}

/**
 * Call `cb` whenever the runtime directory changes while an update is in
 * progress, so live clients can close their sockets before the server stops:
 * a shutting-down server waits on every open client socket. Callbacks must be
 * idempotent. Without a watchable directory, a local stat each second.
 */
export function onUpdateStart(cb) {
  const check = () => updatingUntil() && cb();
  let watcher, timer;
  try {
    watcher = fs.watch(runtimeDir(), { persistent: false }, check);
    watcher.on("error", () => {});
  } catch {
    timer = setInterval(check, 1000);
    timer.unref?.();
  }
  return () => {
    watcher?.close();
    clearInterval(timer);
  };
}

/**
 * Call `resume` once the update marker is gone or expired. A watcher on the
 * runtime directory reacts within milliseconds; a timer at the marker's expiry
 * (at most every 10 s, or 1 s if the directory cannot be watched) is the
 * fallback. Both only stat a local file: the server is never contacted.
 * Returns a cancel function.
 */
export function holdWhileUpdating(resume, clock = { setTimeout, clearTimeout }) {
  let watcher, timer, done = false;
  const stop = () => {
    done = true;
    watcher?.close();
    clock.clearTimeout(timer);
  };
  const check = () => {
    if (done) return;
    const until = updatingUntil();
    if (!until) {
      stop();
      return resume();
    }
    clock.clearTimeout(timer);
    timer = clock.setTimeout(check, Math.min(until - Date.now() + 25, watcher ? 10_000 : 1_000));
  };
  try {
    watcher = fs.watch(runtimeDir(), { persistent: false }, check);
    watcher.on("error", () => {
      watcher?.close();
      watcher = undefined;
    });
  } catch {}
  check();
  return stop;
}
