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

test("F11: a dangling alias, and a directory read, moved in-process and replaced by an alias, are denied", (t) => {
  const r = child(t, `
const fs = (await import("node:fs")).default;
const path = (await import("node:path")).default;
const { spawnSync } = await import("node:child_process");
const outside = process.env.ALIAS_DIR;
const attempt = async (name, op) => { try { await op(); out[name] = "read"; } catch (e) { out[name] = /isolation guard/.test(e.message) ? "blocked" : e.message; } };
// Read through ordinary directories first, so the guard has resolved (cached) them.
out.before = [fs.readFileSync(path.join(outside, "swap", "sentinel"), "utf8"), fs.readFileSync(path.join(outside, "anc", "sub", "sentinel"), "utf8")];
// The code under test moves both directories away (an in-process tree change
// drops the guard's cache); aliases into the protected data then take their
// place (made by a helper process, since this one may not name the target).
fs.renameSync(path.join(outside, "swap"), path.join(outside, "swap-old"));
fs.renameSync(path.join(outside, "anc"), path.join(outside, "anc-old"));
const sh = (cmd) => spawnSync("/bin/sh", ["-c", cmd, "sh", outside, path.dirname(sentinel)]).status;
out.swapped = sh('ln -s "$2" "$1/swap" && ln -s "$2" "$1/anc"');
await attempt("swappedDir", () => fs.readFileSync(path.join(outside, "swap", "sentinel")));
await attempt("swappedAncestor", () => fs.readFileSync(path.join(outside, "anc", "sub", "sentinel")));
await attempt("danglingWrite", () => fs.writeFileSync(path.join(outside, "dangling"), "x"));
out.sibling = fs.readFileSync(path.join(outside, "swap-old", "sentinel"), "utf8");`, (dummy) => {
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-alias-"));
    t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
    for (const d of [path.join(outside, "swap"), path.join(outside, "anc", "sub"), path.join(dummy, ".t3", "sub")]) {
      fs.mkdirSync(d, { recursive: true });
      fs.writeFileSync(path.join(d, "sentinel"), "ok");
    }
    // A dangling alias: its target does not exist yet, inside the protected data.
    fs.symlinkSync(path.join(dummy, ".t3", "not-yet"), path.join(outside, "dangling"));
    return { ALIAS_DIR: outside };
  });
  assert.deepEqual(r.out, { before: ["ok", "ok"], swapped: 0, swappedDir: "blocked", swappedAncestor: "blocked",
    danglingWrite: "blocked", sibling: "ok" }, r.stderr);
  assert.equal(r.status, 1);
});

test("F11: a symlink followed by .. is checked as the OS traverses it (round 4)", (t) => {
  const r = child(t, `
const fs = (await import("node:fs")).default;
const outside = process.env.ALIAS_DIR;
const attempt = async (name, op) => { try { await op(); out[name] = "read"; } catch (e) { out[name] = /isolation guard/.test(e.message) ? "blocked" : e.message; } };
// outside/sub -> <protected>/sub, so outside/sub/../sentinel is <protected>/sentinel to the OS.
await attempt("read", () => fs.readFileSync(outside + "/sub/../sentinel"));
await attempt("relative", () => { process.chdir(outside); return fs.readFileSync("sub/../sentinel"); });
await attempt("promises", () => fs.promises.readFile(outside + "/sub/../sentinel"));
await attempt("missingWrite", () => fs.writeFileSync(outside + "/sub/../not-yet", "x"));
await attempt("renameInto", () => fs.renameSync(outside + "/ordinary", outside + "/sub/../moved"));
out.sibling = fs.readFileSync(outside + "/ordinary", "utf8");
out.lexicalSibling = fs.readFileSync(outside + "/plain/../ordinary", "utf8");`, (dummy) => {
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-dotdot-"));
    t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
    fs.mkdirSync(path.join(dummy, ".t3", "sub"));
    fs.mkdirSync(path.join(outside, "plain"));
    fs.symlinkSync(path.join(dummy, ".t3", "sub"), path.join(outside, "sub"));
    fs.writeFileSync(path.join(outside, "ordinary"), "ok");
    return { ALIAS_DIR: outside };
  });
  assert.deepEqual(r.out, { read: "blocked", relative: "blocked", promises: "blocked", missingWrite: "blocked",
    renameInto: "blocked", sibling: "ok", lexicalSibling: "ok" }, r.stderr);
  assert.equal(r.status, 1, "a caught denial still fails the run");
});

test("F11: a dangling link's stored target is walked as the OS does (round 5)", (t) => {
  let prot;
  const r = child(t, `
const fs = (await import("node:fs")).default;
const outside = process.env.ALIAS_DIR;
const attempt = async (name, op) => { try { await op(); out[name] = "written"; } catch (e) { out[name] = /isolation guard/.test(e.message) ? "blocked" : e.message; } };
await attempt("relativeTarget", () => fs.writeFileSync(outside + "/dangling", "x"));
await attempt("absoluteTarget", () => fs.writeFileSync(outside + "/dangling-abs", "x"));
await attempt("promises", () => fs.promises.writeFile(outside + "/dangling", "x"));
await attempt("ordinaryTarget", () => fs.writeFileSync(outside + "/plain-dangling", "x"));
out.made = fs.readFileSync(outside + "/made", "utf8");`, (dummy) => {
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-dangling-"));
    t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
    fs.mkdirSync(path.join(dummy, ".t3", "sub"));
    fs.mkdirSync(path.join(outside, "plain"));
    fs.symlinkSync(path.join(dummy, ".t3", "sub"), path.join(outside, "link"));
    // Stored, unnormalized targets: link/.. is the protected root to the OS.
    fs.symlinkSync("link/../new-file", path.join(outside, "dangling"));
    fs.symlinkSync(`${outside}/link/../new-abs`, path.join(outside, "dangling-abs"));
    fs.symlinkSync("plain/../made", path.join(outside, "plain-dangling"));
    prot = path.join(dummy, ".t3");
    return { ALIAS_DIR: outside };
  });
  assert.deepEqual(r.out, { relativeTarget: "blocked", absoluteTarget: "blocked", promises: "blocked",
    ordinaryTarget: "written", made: "x" }, r.stderr);
  assert.deepEqual(fs.readdirSync(prot).sort(), ["sentinel", "sub"], "nothing was created in the protected data");
  assert.equal(r.status, 1, "a caught denial still fails the run");
});

test("F11: recursive copies and listings are checked entry by entry, the way they walk the tree (round 5)", (t) => {
  let outside, prot;
  const r = child(t, `
const fs = (await import("node:fs")).default;
const fsp = await import("node:fs/promises");
const outside = process.env.ALIAS_DIR;
const deref = { recursive: true, dereference: true };
const attempt = async (name, op) => { try { await op(); out[name] = "copied"; } catch (e) { out[name] = /isolation guard/.test(e.message) ? "blocked" : e.message; } };
// tree/alias -> the protected sentinel; tree/dir/inner -> the protected directory.
await attempt("sync", () => fs.cpSync(outside + "/tree", outside + "/c-sync", deref));
await attempt("callback", () => new Promise((ok, no) => fs.cp(outside + "/tree", outside + "/c-cb", deref, (e) => (e ? no(e) : ok()))));
await attempt("promises", () => fs.promises.cp(outside + "/tree", outside + "/c-p", deref));
await attempt("fsPromisesModule", () => fsp.cp(outside + "/tree", outside + "/c-m", deref));
await attempt("nestedDir", () => fs.cpSync(outside + "/tree2", outside + "/c-dir", deref));
await attempt("relative", () => { process.chdir(outside); return fs.cpSync("tree", "c-rel", deref); });
// The destination side: dest/sub is an alias into the protected data.
await attempt("intoAliasedDest", () => fs.cpSync(outside + "/src", outside + "/dest", { recursive: true }));
// A recursive listing descends through directory links: tree2/dir/inner lists the protected directory.
const list = (name, op) => attempt(name, async () => { out[name + "Names"] = (await op()).sort(); });
await list("readdir", () => fs.readdirSync(outside + "/tree2", { recursive: true }));
await list("readdirCallback", () => new Promise((ok, no) => fs.readdir(outside + "/tree2", { recursive: true }, (e, v) => (e ? no(e) : ok(v)))));
await list("readdirPromises", () => fs.promises.readdir(outside + "/tree2", { recursive: true }));
// Controls: an ordinary tree (with an in-tree alias) copies; without dereference a link is copied as a link;
// a listing names a link to a protected file without reading through it.
await attempt("ordinary", () => fs.cpSync(outside + "/plain", outside + "/c-plain", deref));
await attempt("linkAsLink", () => fs.cpSync(outside + "/tree", outside + "/c-link", { recursive: true }));
await list("listsLinkName", () => fs.readdirSync(outside + "/tree", { recursive: true }));
out.plain = fs.readFileSync(outside + "/c-plain/via", "utf8");`, (dummy) => {
    outside = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-copy-"));
    t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
    prot = path.join(dummy, ".t3");
    fs.mkdirSync(path.join(prot, "sub"));
    for (const d of ["tree", "tree2/dir", "src/sub", "dest", "plain"]) fs.mkdirSync(path.join(outside, d), { recursive: true });
    fs.writeFileSync(path.join(outside, "tree", "file"), "ok");
    fs.symlinkSync(path.join(prot, "sentinel"), path.join(outside, "tree", "alias"));
    fs.symlinkSync(prot, path.join(outside, "tree2", "dir", "inner"));
    fs.writeFileSync(path.join(outside, "src", "sub", "planted"), "x");
    fs.symlinkSync(path.join(prot, "sub"), path.join(outside, "dest", "sub"));
    fs.writeFileSync(path.join(outside, "plain", "file"), "ok");
    fs.symlinkSync("file", path.join(outside, "plain", "via"));
    return { ALIAS_DIR: outside };
  });
  assert.deepEqual(r.out, { sync: "blocked", callback: "blocked", promises: "blocked", fsPromisesModule: "blocked",
    nestedDir: "blocked", relative: "blocked", intoAliasedDest: "blocked", readdir: "blocked", readdirCallback: "blocked",
    readdirPromises: "blocked", ordinary: "copied", linkAsLink: "copied", listsLinkName: "copied",
    listsLinkNameNames: ["alias", "file"], plain: "ok" }, r.stderr);
  assert.ok(fs.lstatSync(path.join(outside, "c-link", "alias")).isSymbolicLink(), "copied as a link, not read through");
  // Checked from here, outside the guarded child: no protected byte was copied out, nothing was written in.
  const copies = ["c-sync", "c-cb", "c-p", "c-m", "c-rel", "c-dir"].flatMap((d) => fs.existsSync(path.join(outside, d))
    ? fs.readdirSync(path.join(outside, d), { recursive: true }).map((f) => `${d}/${f}`) : []);
  assert.deepEqual(copies.filter((f) => /alias|inner/.test(f)), [], "no protected entry was copied");
  assert.deepEqual(fs.readdirSync(path.join(prot, "sub")), [], "nothing was written into the protected data");
  assert.equal(r.status, 1, "a caught denial still fails the run");
});
