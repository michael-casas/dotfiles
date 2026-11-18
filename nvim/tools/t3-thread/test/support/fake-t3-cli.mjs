#!/usr/bin/env node
// A stand-in for `~/.t3/bin/t3` that scripts/update-repro.mjs can drive in
// hermetic tests (T3_REAL_BIN). FAKE_T3 holds comma-separated faults:
//   serve: term-resistant, stale-pid (successor), env-down (successor),
//          replace-marker (successor), exit-at-once
//   auth-hang, project-hang (write their pid to FAKE_T3_PIDS, then hang)
// The successor is the second `serve` for a base dir. Never binds port 3773.
import fs from "node:fs";
import path from "node:path";
import { startFakeT3 } from "./fake-t3.mjs";

const args = process.argv.slice(2);
const flag = (name) => args[args.indexOf(name) + 1];
const faults = new Set((process.env.FAKE_T3 || "").split(",").filter(Boolean));
const base = flag("--base-dir");
const note = (what) => process.env.FAKE_T3_PIDS && fs.appendFileSync(process.env.FAKE_T3_PIDS, `${what} ${process.pid}\n`);
const hang = () => setInterval(() => {}, 1000);
if (process.env.FAKE_T3_ARGS) fs.appendFileSync(process.env.FAKE_T3_ARGS, `${JSON.stringify({ args, env: {
  T3CODE_HOME: process.env.T3CODE_HOME, NODE_OPTIONS: process.env.NODE_OPTIONS, T3_URL: process.env.T3_URL,
  T3_SESSION_TOKEN: process.env.T3_SESSION_TOKEN } })}\n`);
const title = "t3upd-a";

if (args[0] === "serve") {
  const count = path.join(base, "fake-serve-count");
  const n = (fs.existsSync(count) ? Number(fs.readFileSync(count, "utf8")) : 0) + 1;
  fs.writeFileSync(count, String(n));
  const successor = n > 1;
  note(`serve${n}`);
  if (faults.has("exit-at-once")) process.exit(3);
  const has = (f) => faults.has(f) && (f === "term-resistant" || successor);
  const port = Number(flag("--port"));
  await startFakeT3({
    port,
    initial: [{ kind: "snapshot", snapshotSequence: 1, projection: { thread: { id: "t", title } } }],
    shell: { snapshotSequence: 1, projects: [], archivedThreads: [],
      threads: [{ id: "t", projectId: "p", title, updatedAt: new Date().toISOString() }] },
    routes: { "/.well-known/t3/environment": (req, res) => {
      res.writeHead(has("env-down") ? 503 : 200);
      res.end("{}");
    } },
  });
  if (has("replace-marker")) {
    const marker = path.join(base, "runtime", "desktop-update-in-progress");
    fs.writeFileSync(marker, JSON.stringify({ startedAt: Date.now(), expiresAt: Date.now() + 60_000, replaced: true }));
  }
  fs.mkdirSync(path.join(base, "userdata"), { recursive: true });
  fs.writeFileSync(path.join(base, "userdata", "server-runtime.json"), JSON.stringify({
    pid: has("stale-pid") ? 1 : process.pid, port, serverVersion: "fixture", startedAt: new Date().toISOString() }));
  process.on("SIGTERM", () => (has("term-resistant") ? note("ignored-SIGTERM") : process.exit(0)));
} else if (args[0] === "auth") {
  note("auth");
  if (faults.has("auth-hang")) hang();
  else process.stdout.write("fixture-token\n");
} else if (args[0] === "project") {
  note("project");
  if (faults.has("project-hang")) hang();
  else process.stdout.write(`Added project p (fixture) at ${args.at(-1)}.\n`);
} else process.exit(2);
