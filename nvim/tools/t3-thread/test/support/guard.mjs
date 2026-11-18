// Test-wide isolation guard (imported first by every test file, and preloaded
// into every Node child through NODE_OPTIONS). Fails closed:
// - HOME and T3CODE_HOME point at a throwaway directory, so production
//   defaults (~/.t3, the envi session file, the t3 CLI path) resolve there;
// - T3_URL defaults to a refused loopback port, never the live server;
// - any socket dial to port 3773 throws;
// - any filesystem access under the real ~/.t3 or envi state throws.
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const self = fileURLToPath(import.meta.url);
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

const deny = (what) => {
  const message = `test isolation guard: ${what}`;
  try { fs.appendFileSync(path.join(os.tmpdir(), "t3-test-guard.log"), `${process.pid} ${message}\n`); } catch {}
  throw new Error(message);
};
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const target = Array.isArray(args[0]) ? args[0][0] : args[0];
  if (Number(target?.port ?? target) === 3773) deny("dial to the live T3 port 3773");
  return connect.apply(this, args);
};
const live = (p) => {
  if (typeof p !== "string" && !(p instanceof URL)) return false;
  const abs = path.resolve(p instanceof URL ? fileURLToPath(p) : p);
  return forbidden.some((f) => abs === f || abs.startsWith(`${f}/`));
};
for (const name of ["readFileSync", "writeFileSync", "appendFileSync", "statSync", "existsSync", "watch",
  "renameSync", "mkdirSync", "rmSync", "readdirSync", "openSync", "chmodSync", "utimesSync"]) {
  const original = fs[name];
  fs[name] = function (p, ...rest) {
    if (live(p) || (name === "renameSync" && live(rest[0]))) deny(`${name} on live T3 data`);
    return original.call(this, p, ...rest);
  };
}
