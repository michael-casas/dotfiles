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
 * contract: absent or expired = no update; valid = until expiresAt; malformed
 * or unreadable = until 60 s after its mtime. Valid means the desktop's schema:
 * numeric startedAt and expiresAt.
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
    const { startedAt, expiresAt } = JSON.parse(fs.readFileSync(markerPath(), "utf8"));
    if (Number.isFinite(startedAt) && Number.isFinite(expiresAt)) until = expiresAt;
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
 * Call `onEvent` on changes in runtime/: fs.watch for speed, plus a check each
 * second that re-arms the watch after an error or a replaced directory and
 * covers a missing one. Only local files are touched, never the server.
 */
function watchRuntime(onEvent, keepAlive) {
  let watcher, ino;
  const arm = () => {
    watcher?.close();
    watcher = undefined;
    try {
      ino = fs.statSync(runtimeDir()).ino;
      watcher = fs.watch(runtimeDir(), { persistent: false }, onEvent);
      watcher.on("error", () => {
        watcher?.close();
        watcher = undefined;
      });
    } catch {}
  };
  const timer = setInterval(() => {
    let now;
    try {
      now = fs.statSync(runtimeDir()).ino;
    } catch {}
    if (!watcher || now !== ino) arm();
    onEvent();
  }, 1000);
  if (!keepAlive) timer.unref?.();
  arm();
  return () => {
    watcher?.close();
    clearInterval(timer);
  };
}

/**
 * Call `cb` while an update is in progress, on every runtime/ change, so live
 * clients close their sockets before the server stops: a stopping server waits
 * on every open client socket. Callbacks must be idempotent.
 */
export const onUpdateStart = (cb) => watchRuntime(() => updatingUntil() && cb(), false);

/**
 * Call `resume` once the update marker is gone or expired (within about 1 s of
 * expiry, within milliseconds of removal). Keeps the process alive meanwhile.
 * The first check is asynchronous, so the caller's handle is set before any
 * resume. Returns a cancel function.
 */
export function holdWhileUpdating(resume) {
  let done = false;
  const check = () => {
    if (done || updatingUntil()) return;
    stop();
    resume();
  };
  const unwatch = watchRuntime(check, true);
  const stop = () => {
    done = true;
    unwatch();
  };
  queueMicrotask(check);
  return stop;
}
