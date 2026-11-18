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
function child(t, body, setup) {
  const dummy = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-guard-"));
  t.after(() => fs.rmSync(dummy, { recursive: true, force: true }));
  fs.mkdirSync(path.join(dummy, ".t3"));
  fs.writeFileSync(path.join(dummy, ".t3", "sentinel"), "dummy");
  const env = { ...process.env, HOME: dummy, ...setup?.(dummy) };
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

test("F11: a symlink alias into protected data is denied by its resolved target; siblings stay readable", (t) => {
  const r = child(t, `
const fs = (await import("node:fs")).default;
const fsp = await import("node:fs/promises");
const path = (await import("node:path")).default;
const outside = process.env.ALIAS_DIR; // made before the guard loaded
const via = path.join(outside, "alias", "sentinel");
const attempt = async (name, op) => { try { await op(); out[name] = "read"; } catch (e) { out[name] = /isolation guard/.test(e.message) ? "blocked" : e.message; } };
await attempt("sync", () => fs.readFileSync(via));
await attempt("callback", () => new Promise((ok, no) => fs.readFile(via, (e, v) => (e ? no(e) : ok(v)))));
await attempt("promises", () => fs.promises.readFile(via));
await attempt("fsPromisesModule", () => fsp.readFile(via));
await attempt("stream", () => new Promise((ok, no) => fs.createReadStream(via).on("data", ok).on("error", no)));
await attempt("missingUnderAlias", () => fs.writeFileSync(path.join(outside, "alias", "new-file"), "x"));
await attempt("renameIntoAlias", () => fs.renameSync(path.join(outside, "ordinary"), path.join(outside, "alias", "moved")));
out.sibling = fs.readFileSync(path.join(outside, "ordinary"), "utf8");`, (dummy) => {
    // A pre-existing alias outside the protected home, pointing into its .t3.
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-alias-"));
    t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
    fs.symlinkSync(path.join(dummy, ".t3"), path.join(outside, "alias"));
    fs.writeFileSync(path.join(outside, "ordinary"), "ok");
    return { ALIAS_DIR: outside };
  });
  assert.deepEqual(r.out, { sync: "blocked", callback: "blocked", promises: "blocked", fsPromisesModule: "blocked",
    stream: "blocked", missingUnderAlias: "blocked", renameIntoAlias: "blocked", sibling: "ok" });
  assert.equal(r.status, 1, "alias-only access still fails the run");
});
