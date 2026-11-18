// Test-wide isolation guard (imported first by every test file, and preloaded
// into every Node child through NODE_OPTIONS). Fails closed:
// - HOME (when it is the real one) and T3CODE_HOME point at a throwaway
//   directory, so production defaults (~/.t3, the envi session file, the t3
//   CLI path) resolve there; T3_URL defaults to a refused loopback port;
// - any socket connect to port 3773 throws (net.Socket, so TLS too);
// - any fs call on a path under the real ~/.t3 or envi state throws: sync,
//   callback, promise (fs.promises is node:fs/promises) and stream APIs;
// - every denial is recorded and makes the process exit 1, even when the code
//   under test catches the error.
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { syncBuiltinESMExports } from "node:module";
import { fileURLToPath } from "node:url";

const self = fileURLToPath(import.meta.url);
const { lstatSync: lstat, readlinkSync: readlink } = fs; // captured before fs is wrapped
const realpath = fs.realpathSync.native;
const realHome = process.env.T3UPD_GUARD_REAL_HOME || os.homedir();
const forbidden = [path.join(realHome, ".t3"), path.join(realHome, ".local/state/envi")];
if (!process.env.T3UPD_GUARD_HOME) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "t3-test-home-"));
  process.on("exit", () => fs.rmSync(home, { recursive: true, force: true }));
  Object.assign(process.env, {
    T3UPD_GUARD_HOME: home,
    T3UPD_GUARD_REAL_HOME: realHome,
    NODE_OPTIONS: `${process.env.NODE_OPTIONS || ""} --import ${self}`.trim(),
  });
}
const home = process.env.T3UPD_GUARD_HOME;
// A test may give a child its own temp HOME; only the real one is replaced.
if (!process.env.HOME || path.resolve(process.env.HOME) === path.resolve(realHome)) process.env.HOME = home;
if (!process.env.T3CODE_HOME || forbidden.some((p) => path.resolve(process.env.T3CODE_HOME).startsWith(p)))
  process.env.T3CODE_HOME = path.join(home, ".t3");
process.env.T3_URL ||= "http://127.0.0.1:9";

const violations = [];
const deny = (what) => {
  const message = `test isolation guard: ${what}`;
  violations.push(message);
  process.exitCode = 1;
  try { fs.appendFileSync(path.join(os.tmpdir(), "t3-test-guard.log"), `${process.pid} ${message}\n`); } catch {}
  throw new Error(message);
};
process.on("exit", () => {
  if (!violations.length) return;
  process.exitCode = 1; // a caught denial still fails the run
  process.stderr.write(`${violations.length} isolation violation(s): ${violations[0]}\n`);
});

const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const target = Array.isArray(args[0]) ? args[0][0] : args[0];
  if (Number(target?.port ?? target) === 3773) deny("dial to the live T3 port 3773");
  return connect.apply(this, args);
};

// The filesystem target, not just the spelling: resolve symlinks, a missing
// path through its nearest existing parent, and a dangling symlink through
// its target.
const stat = (p) => { try { return lstat(p, { throwIfNoEntry: false }); } catch {} }; // ENOTDIR: missing
function resolved(abs, depth = 0) {
  for (let p = abs, rest = []; ; rest.unshift(path.basename(p)), p = path.dirname(p)) {
    const st = stat(p);
    if (!st) { if (p === path.dirname(p)) return abs; continue; }
    try { return path.join(realpath(p), ...rest); } catch {}
    if (!st.isSymbolicLink() || depth > 40) return abs;
    try { return resolved(path.join(path.resolve(path.dirname(p), readlink(p)), ...rest), depth + 1); } catch { return abs; }
  }
}
const protectedRoots = [...new Set([...forbidden, ...forbidden.map(resolved)])];
const under = (abs) => protectedRoots.some((f) => abs === f || abs.startsWith(`${f}/`));
// realpath costs ~20 µs on macOS, and a TUI start alone makes ~3,650 fs calls
// on ~530 paths: checking each call delayed every child's startup enough to
// break the startup-timing-bound layout-focus-core Lua suite. So each path's
// verdict is computed once per process (a directory's resolution is shared by
// its entries), and the first in-process call that can change the tree
// (rename, symlink, link, unlink, rm, cp) turns both caches off.
// Accepted limitation (charter Amendment 8): another process changing the tree
// during the run (moving a resolved directory, swapping one for a symlink) is
// not seen. The guard is for accidental access by the code under test.
let verdicts = new Map(), dirs = new Map();
const live = (p) => {
  if (p instanceof URL) p = p.protocol === "file:" ? fileURLToPath(p) : null;
  else if (Buffer.isBuffer(p)) p = p.toString();
  if (typeof p !== "string") return false; // file descriptors, handles
  // The target check walks the path as the OS does, so it is never normalized
  // first: in link/.. the OS follows the link before the "..".
  const raw = path.isAbsolute(p) ? p : `${process.cwd()}/${p}`;
  let verdict = verdicts?.get(raw);
  if (verdict !== undefined) return verdict;
  verdict = under(path.resolve(raw)) || under(target(raw));
  verdicts?.set(raw, verdict);
  return verdict;
};
function target(raw) {
  const dir = path.dirname(raw);
  if (!dirs || dir === raw || stat(raw)?.isSymbolicLink()) return resolved(raw);
  if (!dirs.has(dir)) dirs.set(dir, resolved(dir));
  return path.join(dirs.get(dir), path.basename(raw));
}
const RESHAPES = /^(rename|symlink|link|unlink|rm|cp)/;
const TWO_PATHS = /^(rename|copyFile|link|symlink|cp)(Sync)?$/;
function wrap(api, label) {
  for (const name of Object.keys(api)) {
    const original = api[name];
    if (typeof original !== "function" || /^[A-Z]/.test(name)) continue; // skip classes
    const reshapes = RESHAPES.test(name), twoPaths = TWO_PATHS.test(name);
    api[name] = function (...args) {
      if (reshapes) verdicts = dirs = null;
      if (live(args[0]) || (twoPaths && live(args[1]))) deny(`${label}.${name} on live T3 data`);
      return original.apply(this, args);
    };
  }
}
wrap(fs, "fs");
wrap(fs.promises, "fs.promises");
syncBuiltinESMExports(); // named imports (import { readFile } from "node:fs") see the wrappers too
