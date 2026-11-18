// T3 desktop update / server restart resilience (HOTFIX T3UPD lane A).
// Every server here is a local synthetic fake on 127.0.0.1; every T3 home,
// session file and CLI is a throwaway under the OS temp directory.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { startFakeT3 } from "./support/fake-t3.mjs";
import { startFeed } from "../threads.mjs";
import { statusLabel } from "../t3.mjs";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const snapshot = [{ kind: "snapshot", snapshotSequence: 1, projection: { thread: { id: "t", title: "T" } } }];

// t3.mjs reads T3_URL at import time, so each test gets a fresh module instance.
async function adapter(t, url, env = {}) {
  const vars = { T3_URL: url, T3_SESSION_TOKEN: "fixture-token", ...env };
  const old = Object.fromEntries(Object.keys(vars).map((k) => [k, process.env[k]]));
  t.after(() => {
    for (const [k, v] of Object.entries(old)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  });
  Object.assign(process.env, vars);
  return import(`../t3.mjs?resilience=${crypto.randomUUID()}`);
}

async function until(predicate, ms = 3000) {
  const end = Date.now() + ms;
  while (!predicate()) {
    if (Date.now() > end) return false;
    await sleep(10);
  }
  return true;
}

test("A1: a thread stream that exits at once backs off instead of hot-looping", async (t) => {
  const fake = await startFakeT3({ initial: snapshot, exitThread: true });
  t.after(() => fake.close());
  const t3 = await adapter(t, fake.url);
  const conns = [];
  const close = t3.subscribe("missing-thread", { onConn: (c) => conns.push(c) });
  t.after(close);
  await sleep(5000);
  close();
  // Jittered delays are at least half of 500, 1000, 2000, 4000 ms, so a 5 s
  // window holds at most 5 attempts (0, .25, .75, 1.75, 3.75 s). The old
  // client reset its backoff on every open and made about 2 attempts a second.
  assert.ok(fake.counts.upgrades >= 2, `attempts: ${fake.counts.upgrades}`);
  assert.ok(fake.counts.upgrades <= 5, `hot reconnect loop: ${fake.counts.upgrades} attempts in 5 s`);
  assert.ok(!conns.includes("live"), "an exiting stream never proved healthy");
});

test("A1: a healthy stream resets the backoff, so a later drop reconnects fast", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const t3 = await adapter(t, fake.url);
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  await fake.connected;
  assert.ok(await until(() => conns.at(-1) === "live"));
  const dropped = Date.now();
  fake.dropAll();
  assert.ok(await until(() => fake.counts.upgrades === 2, 1500), "reconnected");
  assert.ok(Date.now() - dropped < 1000, `first retry took ${Date.now() - dropped} ms`);
});

// A throwaway T3CODE_HOME with a runtime/ directory, like the desktop's.
function t3home(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "t3upd-home-"));
  fs.mkdirSync(path.join(home, "runtime"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const marker = path.join(home, "runtime", "desktop-update-in-progress");
  return {
    home,
    marker,
    // Atomic, like desktop writeUpdateInProgressMarker (tmp + rename).
    write(body = { startedAt: Date.now(), expiresAt: Date.now() + 60_000 }) {
      fs.writeFileSync(`${marker}.tmp`, typeof body === "string" ? body : JSON.stringify(body));
      fs.renameSync(`${marker}.tmp`, marker);
    },
    remove: () => fs.rmSync(marker, { force: true }),
  };
}

test("A2: during a desktop update the thread client makes no requests and says so", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const home = t3home(t);
  home.write();
  const t3 = await adapter(t, fake.url, { T3CODE_HOME: home.home });
  const conns = [];
  const close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  await sleep(1200);
  assert.equal(fake.counts.http + fake.counts.upgrades, 0, "no load on the updating server");
  assert.equal(conns.at(-1), "T3 updating…");
  const started = Date.now();
  await assert.rejects(close.send("hello"), /T3 is updating/);
  assert.ok(Date.now() - started < 100, "commands fail fast");
  const removed = Date.now();
  home.remove();
  assert.ok(await until(() => conns.at(-1) === "live", 2000), `resumed: ${conns.at(-1)}`);
  assert.ok(Date.now() - removed < 1000, `resume took ${Date.now() - removed} ms`);
});

test("A2: an expired marker is ignored; a malformed one holds until 60 s after its mtime", async (t) => {
  const fake = await startFakeT3({ initial: snapshot });
  t.after(() => fake.close());
  const home = t3home(t);
  home.write({ startedAt: Date.now() - 70_000, expiresAt: Date.now() - 10_000 });
  const t3 = await adapter(t, fake.url, { T3CODE_HOME: home.home });
  let conns = [];
  let close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  assert.ok(await until(() => conns.at(-1) === "live"), "expired marker does not block");
  close();

  home.write("{not json");
  conns = [];
  const before = fake.counts.upgrades;
  close = t3.subscribe("t", { onConn: (c) => conns.push(c) });
  t.after(close);
  await sleep(600);
  assert.equal(fake.counts.upgrades, before, "fresh malformed marker counts as present");
  assert.equal(conns.at(-1), "T3 updating…");
  // The same malformed marker, now 61 s old, renamed into place.
  const old = (Date.now() - 61_000) / 1000;
  fs.writeFileSync(`${home.marker}.tmp`, "{not json");
  fs.utimesSync(`${home.marker}.tmp`, old, old);
  fs.renameSync(`${home.marker}.tmp`, home.marker);
  assert.ok(await until(() => conns.at(-1) === "live", 1500), `stale malformed marker: ${conns.at(-1)}`);
});

test("A2: the status line shows T3 updating instead of Connecting", () => {
  assert.deepEqual(statusLabel(null, "T3 updating…"), ["T3 updating…", "warning"]);
});

function feedHarness(options = {}) {
  const sockets = [], output = [];
  // A clock whose timers never fire: only the marker watcher can resume.
  const clock = { now: Date.now, setTimeout: () => 0, clearTimeout() {} };
  const feed = startFeed(options, {
    clock, write: (line) => output.push(JSON.parse(line)),
    async openSocket() {
      const ws = { sent: [], close() { this.closed = true; }, send(text) { this.sent.push(JSON.parse(text)); } };
      sockets.push(ws);
      return ws;
    },
  });
  return { feed, sockets, output };
}

test("A2: the sidebar feed holds while the marker is present and resumes on removal", async (t) => {
  const home = t3home(t);
  home.write();
  const old = process.env.T3CODE_HOME;
  t.after(() => (old === undefined ? delete process.env.T3CODE_HOME : (process.env.T3CODE_HOME = old)));
  process.env.T3CODE_HOME = home.home;
  const h = feedHarness();
  t.after(() => h.feed.close());
  await sleep(300);
  assert.equal(h.sockets.length, 0, "no connection attempt during the update");
  assert.deepEqual(h.output, [{ type: "error", message: "T3 updating…" }]);
  home.remove();
  assert.ok(await until(() => h.sockets.length === 1, 1000), "resumed by the marker watcher");

  home.write();
  const once = feedHarness({ once: true });
  assert.equal(await once.feed.done, 1);
  assert.equal(once.sockets.length, 0);
  assert.deepEqual(once.output, [{ type: "error", message: "T3 updating…" }]);
});
