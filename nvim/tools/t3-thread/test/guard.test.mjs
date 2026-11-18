// The isolation guard itself (F11): run in child processes whose "real home"
// is a dummy directory, so no real T3 data or port is ever involved.
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const guard = fileURLToPath(new URL("./support/guard.mjs", import.meta.url));
function child(t, body) {
  const dummy = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-guard-"));
  t.after(() => fs.rmSync(dummy, { recursive: true, force: true }));
  fs.mkdirSync(path.join(dummy, ".t3"));
  fs.writeFileSync(path.join(dummy, ".t3", "sentinel"), "dummy");
  const env = { ...process.env, HOME: dummy };
  for (const k of ["NODE_OPTIONS", "T3UPD_GUARD_HOME", "T3UPD_GUARD_REAL_HOME", "T3CODE_HOME"]) delete env[k];
  // The network primitive is replaced before the guard loads: nothing can dial.
  const script = `import net from "node:net";
net.Socket.prototype.connect = () => { throw new Error("fixture transport reached"); };
await import(${JSON.stringify(guard)});
const sentinel = ${JSON.stringify(path.join(dummy, ".t3", "sentinel"))};
const out = {};
${body}
console.log(JSON.stringify(out));`;
  const r = spawnSync(process.execPath, ["--input-type=module", "-e", script], { env, encoding: "utf8", timeout: 15000 });
  return { status: r.status, stderr: r.stderr, out: JSON.parse(r.stdout.trim().split("\n").at(-1) || "{}") };
}

test("F11: the guard blocks sync, callback, promise and stream access to protected data", (t) => {
  const r = child(t, `
import("node:fs").then(() => {});
const fs = (await import("node:fs")).default;
const fsp = await import("node:fs/promises");
const { readFile } = await import("node:fs");
const attempt = async (name, op) => { try { await op(); out[name] = "read"; } catch (e) { out[name] = /isolation guard/.test(e.message) ? "blocked" : e.message; } };
await attempt("sync", () => fs.readFileSync(sentinel));
await attempt("callback", () => new Promise((ok, no) => fs.readFile(sentinel, (e, v) => (e ? no(e) : ok(v)))));
await attempt("namedImport", () => new Promise((ok, no) => readFile(sentinel, (e, v) => (e ? no(e) : ok(v)))));
await attempt("promises", () => fs.promises.readFile(sentinel));
await attempt("fsPromisesModule", () => fsp.readFile(sentinel));
await attempt("stream", () => new Promise((ok, no) => fs.createReadStream(sentinel).on("data", ok).on("error", no)));
await attempt("renameInto", () => fs.renameSync(sentinel + ".x", sentinel));`);
  assert.deepEqual(r.out, { sync: "blocked", callback: "blocked", namedImport: "blocked", promises: "blocked",
    fsPromisesModule: "blocked", stream: "blocked", renameInto: "blocked" });
  assert.equal(r.status, 1, "a denied run exits nonzero");
});

test("F11: a denied connect to 3773 and a caught denial still fail the process", (t) => {
  const r = child(t, `
try { new net.Socket().connect({ port: 3773, host: "127.0.0.1" }); out.port = "connected"; } catch (e) { out.port = /isolation guard/.test(e.message) ? "blocked" : e.message; }
try { (await import("node:fs")).default.statSync(sentinel); } catch {} // swallowed by "application code"
out.exitCode = process.exitCode;`);
  assert.deepEqual(r.out, { port: "blocked", exitCode: 1 }, r.stderr);
  assert.equal(r.status, 1);
});

test("F11: a clean run under the guard exits 0", (t) => {
  const r = child(t, `out.home = process.env.HOME !== undefined;`);
  assert.equal(r.status, 0);
});
