// T3 desktop update / server restart resilience (HOTFIX T3UPD lane A).
// Every server here is a local synthetic fake on 127.0.0.1; every T3 home,
// session file and CLI is a throwaway under the OS temp directory.
import test from "node:test";
import assert from "node:assert/strict";
import { startFakeT3 } from "./support/fake-t3.mjs";

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
