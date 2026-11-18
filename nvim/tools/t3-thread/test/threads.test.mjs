import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  feedStatus, feedSnapshot, applyShellValue, parseArgs, startFeed,
} from "../threads.mjs";

const at = "2026-11-15T20:00:00.000Z";
const before = "2026-11-15T19:00:00.000Z";
const row = (overrides = {}) => ({
  id: "t", projectId: "p", title: "Example", status: "completed",
  latestRunId: "r", latestRunCompletedAt: at, lastVisitedAt: before,
  updatedAt: at, pendingRuntimeRequest: null, ...overrides,
});
const shell = (threads = [row()]) => ({
  snapshotSequence: 1, projects: [{ id: "p", title: "Example", workspaceRoot: "/projects/example" }],
  threads, archivedThreads: [],
});

for (const [name, change, expected] of [
  ["no run", { latestRunId: null, status: "idle" }, "idle"],
  ...["queued", "preparing", "starting", "running", "waiting"].map(status => [status, { status }, "working"]),
  ["activity overrides latest terminal", { activityRunStatus: "running" }, "working"],
  ["approval", { status: "running", pendingRuntimeRequest: { kind: "command_approval" } }, "attention"],
  ["async input", { status: "running", pendingRuntimeRequest: { kind: "user_input", blocking: false } }, "attention"],
  ["auth refresh invisible", { status: "running", pendingRuntimeRequest: { kind: "auth_refresh" } }, "working"],
  ["guest", { pendingGuestMessageCount: 1 }, "attention"],
  ["usage limit", { status: "failed", lastErrorClass: "usage_limit" }, "attention"],
  ["unseen completion", {}, "done"],
  ["legacy idle completed run", { status: "idle" }, "done"],
  ["seen completion", { lastVisitedAt: at }, "idle"],
  ["missing visit follows desktop", { lastVisitedAt: null }, "idle"],
  ["invalid visit follows desktop", { lastVisitedAt: "invalid" }, "done"],
  ["invalid completion", { latestRunCompletedAt: "invalid" }, "idle"],
  ["settled", { settledOverride: "settled" }, "idle"],
  ["active override", { settledOverride: "active" }, "done"],
  ["failed", { status: "failed" }, "error"],
  ["seen failure remains explicit error", { status: "failed", lastVisitedAt: at }, "error"],
  ["error interrupt", { status: "interrupted", lastError: "Provider error" }, "error"],
  ["user interrupt", { status: "interrupted", lastError: null }, "idle"],
  ["cancelled", { status: "cancelled" }, "idle"],
  ["rollback", { status: "rolled_back" }, "idle"],
  ["waiting on thread", { status: "running", blockedOnThreadWait: true }, "idle"],
  ["awaited child", { pendingBackgroundTasks: [{ kind: "subagent" }] }, "idle"],
  ["awaited command", { pendingBackgroundTasks: [{ kind: "command", awaited: true }] }, "idle"],
  ["unawaited server", { pendingBackgroundTasks: [{ kind: "command" }] }, "done"],
  ["plan ready", { interactionMode: "plan", hasActionableProposedPlan: true }, "attention"],
]) test(`feed status: ${name}`, () => assert.equal(feedStatus(row(change)), expected));

test("snapshot matches exact fixture contract and covers all statuses", () => {
  const fixture = JSON.parse(fs.readFileSync(new URL("fixtures/threads-snapshot.json", import.meta.url)));
  assert.deepEqual(new Set(fixture.threads.map(t => t.status)), new Set(["working", "attention", "done", "idle", "error"]));
  assert.ok(fixture.threads.some(t => t.pinned));
  assert.ok(fixture.threads.some(t => t.unread));
  assert.ok(fixture.threads.some(t => t.parentId && t.listed === false && t.relationship === "subagent"));
  const snapshot = feedSnapshot(shell(), {}, at);
  assert.deepEqual(Object.keys(snapshot), Object.keys(fixture));
  assert.deepEqual(Object.keys(snapshot.projects[0]), Object.keys(fixture.projects[0]));
  assert.deepEqual(Object.keys(snapshot.threads[0]), Object.keys(fixture.threads[0]));
  assert.deepEqual(snapshot.threads[0], {
    id: "t", projectId: "p", title: "Example", status: "done", updatedAt: at,
    pinned: false, unread: true, archived: false, settled: false,
    parentId: null, listed: true, relationship: null, model: null, harness: null, branch: null, worktreePath: null,
  });
});

test("listed follows desktop lineage eligibility and relationship preserves the wire value", () => {
  for (const [lineage, listed, relationship] of [
    [undefined, true, null],
    [{ parentThreadId: null, relationshipToParent: null }, true, null],
    [{ parentThreadId: "parent", relationshipToParent: "subagent" }, false, "subagent"],
    [{ parentThreadId: "parent", relationshipToParent: "fork" }, true, "fork"],
    [{ parentThreadId: "parent", relationshipToParent: "fork", sideChat: true }, false, "fork"],
    [{ parentThreadId: "parent", relationshipToParent: null, sideChat: true }, false, null],
    [{ parentThreadId: "parent", relationshipToParent: "fork", sideChat: false }, true, "fork"],
  ]) {
    const s = feedSnapshot(shell([row({ lineage })]), {}, at);
    assert.equal(s.threads.length, 1); // unlisted rows remain available for nesting
    assert.equal(s.threads[0].listed, listed);
    assert.equal(s.threads[0].relationship, relationship);
    assert.equal(s.threads[0].parentId, lineage?.parentThreadId ?? null);
  }
});

test("pinned means desktop pinned-section membership, not inherited child pin metadata", () => {
  const cases = [
    [{}, true],
    [{ pinnedAt: null }, false],
    [{ lineage: { parentThreadId: "parent", relationshipToParent: "subagent" } }, false],
    [{ lineage: { parentThreadId: "parent", sideChat: true } }, false],
    [{ lineage: { parentThreadId: "parent", relationshipToParent: "fork" } }, true],
    [{ settledOverride: "settled" }, false],
    [{ settledOverride: "active" }, true],
    [{ archivedAt: at }, false],
    [{ snoozedUntil: "2026-11-16T20:00:00.000Z", snoozedAt: before }, false],
    [{ snoozedUntil: before }, true],
    [{ snoozedUntil: "invalid" }, true],
    [{ snoozedUntil: "2026-11-16T20:00:00.000Z", pendingRuntimeRequest: { kind: "approval" } }, true],
    [{ snoozedUntil: "2026-11-16T20:00:00.000Z", snoozedAt: before, pendingRuntimeRequest: { kind: "user_input", createdAt: before } }, false],
    [{ snoozedUntil: "2026-11-16T20:00:00.000Z", snoozedAt: before, pendingRuntimeRequest: { kind: "user_input", createdAt: at } }, true],
    [{ snoozedUntil: "2026-11-16T20:00:00.000Z", snoozedAt: before, status: "failed" }, true],
    [{ snoozedUntil: "2026-11-16T20:00:00.000Z", snoozedAt: at, status: "failed" }, false],
    // A delegated task without a locally known parent is not blanket-excluded:
    // desktop lists it independently if its linked parent is unavailable.
    [{ delegatedFrom: { environmentId: "remote", threadId: "missing" } }, true],
  ];
  for (const [change, expected] of cases) {
    const source = shell([row({ pinnedAt: at, ...change })]);
    const snapshot = feedSnapshot(source, { archived: true }, at);
    assert.equal(snapshot.threads.length, 1); // children remain usable in the feed
    assert.equal(snapshot.threads[0].pinned, expected, JSON.stringify(change));
  }
});

test("inherited pins on eighty completed subagents do not crowd out eight pinned parents", () => {
  const parents = Array.from({ length: 8 }, (_, i) => row({ id: `parent-${i}`, pinnedAt: at }));
  const children = Array.from({ length: 80 }, (_, i) => row({
    id: `child-${i}`, pinnedAt: at,
    lineage: { parentThreadId: `parent-${i % 8}`, relationshipToParent: "subagent" },
  }));
  const source = shell([...parents, ...children, row({ id: "not-pinned" })]);
  source.projects[0].pinnedAt = at; // project pin never pins its threads
  const snapshot = feedSnapshot(source, {}, at);
  assert.equal(snapshot.threads.length, 89);
  assert.equal(snapshot.threads.filter(t => t.pinned).length, 8);
  assert.ok(snapshot.threads.filter(t => t.parentId).every(t => !t.pinned));
});

test("harness uses provider instance wire fields, never the model name", () => {
  for (const harness of ["claudeAgent", "pi", "codex", "opencode"]) {
    const snapshot = feedSnapshot(shell([row({
      providerInstanceId: harness, modelSelection: { instanceId: harness, model: "same-gpt-model" },
    })]), {}, at);
    assert.equal(snapshot.threads[0].harness, harness);
    assert.equal(snapshot.threads[0].model, "same-gpt-model");
  }
  for (const [change, expected] of [
    [{ modelSelection: { instanceId: "pi", model: "gpt-model" } }, "pi"],
    [{ providerInstanceId: "codex" }, "codex"],
    [{ providerInstanceId: "pi", modelSelection: { instanceId: "opencode" } }, "opencode"],
    [{ modelSelection: { model: "claude-haiku-5-5" } }, null],
    [{}, null],
  ]) assert.equal(feedSnapshot(shell([row(change)]), {}, at).threads[0].harness, expected);
});

test("project path/archive/deleted filtering, metadata and immutable projection", () => {
  const source = shell([row({ pinnedAt: at, lineage: { parentThreadId: "parent" }, modelSelection: { model: "model" }, branch: "feature/x", worktreePath: "/worktrees/x" }), row({ id: "deleted", deletedAt: at }), row({ id: "other", projectId: "p2" })]);
  source.projects.push({ id: "p2", title: "Other", workspaceRoot: "/other" });
  source.archivedThreads.push(row({ id: "archived", archivedAt: at }));
  const unchanged = JSON.stringify(source);
  assert.deepEqual(feedSnapshot(source, { project: "/projects/example/" }, at).threads.map(t => t.id), ["t"]);
  assert.deepEqual(feedSnapshot(source, { project: "/projects/example", archived: true }, at).threads.map(t => t.id), ["t", "archived"]);
  assert.deepEqual(feedSnapshot(source, { project: "/missing" }, at).projects, []);
  const t = feedSnapshot(source, {}, at).threads[0];
  assert.deepEqual([t.pinned, t.parentId, t.model, t.branch, t.worktreePath], [true, "parent", "model", "feature/x", "/worktrees/x"]);
  assert.equal(JSON.stringify(source), unchanged);
});

test("shell reducer snapshots, sequence, upserts, removals and archive moves", () => {
  let s = applyShellValue(null, { kind: "snapshot", snapshot: shell() });
  assert.equal(applyShellValue(s, { kind: "synchronized" }), s);
  s = applyShellValue(s, { kind: "thread.updated", sequence: 2, location: "archive", thread: row({ archivedAt: at }) });
  assert.equal(s.threads.length, 0);
  assert.equal(s.archivedThreads.length, 1);
  assert.equal(applyShellValue(s, { kind: "thread.removed", sequence: 1, threadId: "t" }), s);
  s = applyShellValue(s, { kind: "thread.updated", sequence: 3, location: "active", thread: row() });
  assert.equal(s.archivedThreads.length, 0);
  s = applyShellValue(s, { kind: "project.updated", sequence: 4, project: { id: "p", title: "Renamed", workspaceRoot: "/projects/example" } });
  assert.equal(s.projects[0].title, "Renamed");
  s = applyShellValue(s, { kind: "thread.removed", location: "archive", sequence: 5, threadId: "t" });
  assert.equal(s.threads.length, 1); // archive removal can follow the active upsert
  s = applyShellValue(s, { kind: "thread.removed", location: "active", sequence: 6, threadId: "t" });
  assert.equal(s.threads.length, 0);
  s = applyShellValue(s, { kind: "project.removed", sequence: 7, projectId: "p" });
  assert.equal(s.projects.length, 0);
});

test("child approvals and user-only cards roll up; ordinary questions, native and stopped children do not", () => {
  const parent = row({ status: "running" });
  const child = row({ id: "child", status: "running", activityRunStatus: "running", lineage: { parentThreadId: "t", relationshipToParent: "subagent" }, pendingRuntimeRequest: { kind: "approval" } });
  const status = changes => feedSnapshot(shell([parent, { ...child, ...changes }]), {}, at).threads[0].status;
  assert.equal(status({}), "attention");
  assert.equal(status({ pendingRuntimeRequest: { kind: "user_input" } }), "working");
  assert.equal(status({ pendingRuntimeRequest: { kind: "user_input", userOnly: true } }), "attention");
  assert.equal(status({ creationSource: "provider" }), "working");
  assert.equal(status({ activityRunStatus: null }), "working");
  assert.equal(status({ activityRunStatus: undefined, status: "completed" }), "working");
  assert.equal(status({ activityRunStatus: null, lineage: { parentThreadId: "t", sideChat: true }, pendingRuntimeRequest: { kind: "user_input" } }), "attention");
});

test("upserts keep server row order stable and preserve source state", () => {
  const s = shell([row(), row({ id: "second" })]);
  const next = applyShellValue(s, { kind: "thread.updated", sequence: 2, location: "active", thread: row({ title: "Changed" }) });
  assert.deepEqual(next.threads.map(t => t.id), ["t", "second"]);
  assert.equal(s.threads[0].title, "Example");
});

test("metadata enrichment snapshots never wipe threads or rewind the sequence", () => {
  const s = shell(Array.from({ length: 468 }, (_, i) => row({ id: `t${i}` })));
  s.projects = Array.from({ length: 15 }, (_, i) => ({ id: i ? `p${i}` : "p", title: "Example", workspaceRoot: i ? `/projects/example${i}` : "/projects/example" }));
  let next = applyShellValue(s, { kind: "snapshot", resolvedRepositoryIdentityRoots: ["/projects/example"], snapshot: { snapshotSequence: 0, projects: [{ id: "p", title: "Example", workspaceRoot: "/projects/example", repositoryIdentity: { key: "example" } }], threads: [], archivedThreads: [] } });
  assert.equal(next.threads.length, 468);
  assert.equal(next.projects.length, 15);
  assert.equal(next.snapshotSequence, 1);
  assert.equal(next.projects[0].repositoryIdentity.key, "example");
  // The reported failure became a four-row roster after four active-thread
  // deltas repopulated the mistakenly emptied metadata snapshot.
  for (let i = 0; i < 4; i++) next = applyShellValue(next, {
    kind: "thread.updated", sequence: 2 + i, location: "active", thread: row({ id: `t${i}`, status: "running" }),
  });
  assert.equal(next.threads.length, 468);
  assert.equal(next.projects.length, 15);
});

test("malformed typed snapshots and deltas are rejected before an asynchronous publish", () => {
  assert.throws(() => applyShellValue(null, { kind: "snapshot", snapshot: {} }));
  assert.throws(() => applyShellValue(shell(), { kind: "thread.updated", sequence: 2, location: "active", thread: {} }));
});

test("CLI accepts only the documented switches", () => {
  assert.deepEqual(parseArgs(["--once", "--project", "/projects/example", "--archived"]), { once: true, project: "/projects/example", archived: true });
  assert.throws(() => parseArgs(["--project"]));
  assert.throws(() => parseArgs(["--project", "--once"]));
  assert.throws(() => parseArgs(["--unknown"]));
});

test("CLI --once transport failure and usage error exit 1 with one safe NDJSON line", () => {
  for (const args of [["--once"], ["--unknown"]]) {
    const result = spawnSync(process.execPath, [fileURLToPath(new URL("../threads.mjs", import.meta.url)), ...args], {
      encoding: "utf8", timeout: 3000,
      env: { ...process.env, T3_URL: "http://127.0.0.1:1", T3_SESSION_TOKEN: "fixture-only", T3_THREAD_DEBUG: "" },
    });
    assert.equal(result.status, 1);
    assert.equal(result.stderr, "");
    const lines = result.stdout.trim().split("\n");
    assert.equal(lines.length, 1);
    assert.equal(JSON.parse(lines[0]).type, "error");
    assert.ok(!result.stdout.includes("fixture-only"));
  }
});

function harness(options = {}) {
  let now = 0, id = 0;
  const timers = new Map(), sockets = [], output = [];
  const clock = {
    now: () => now,
    setTimeout(fn, ms) { const key = ++id; timers.set(key, { at: now + ms, fn }); return key; },
    clearTimeout(key) { timers.delete(key); },
    tick(ms) {
      const target = now + ms;
      for (;;) {
        const entry = [...timers].filter(([, t]) => t.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!entry) break;
        timers.delete(entry[0]); now = entry[1].at; entry[1].fn();
      }
      now = target;
    },
  };
  const feed = startFeed(options, {
    clock, write: line => output.push(JSON.parse(line)),
    async openSocket() {
      const ws = { sent: [], close() { this.closed = true; this.onclose?.(); }, send(text) { this.sent.push(JSON.parse(text)); } };
      sockets.push(ws); return ws;
    },
  });
  const flush = async () => { await Promise.resolve(); await Promise.resolve(); };
  const value = (v, ws = sockets.at(-1)) => ws.onmessage({ data: JSON.stringify({ _tag: "Chunk", requestId: "1", values: [v] }) });
  return { feed, clock, sockets, output, flush, value };
}

test("one subscription, ping/ack, debounce at 250ms, no unchanged snapshots", async () => {
  const h = harness(); await h.flush();
  const ws = h.sockets[0]; ws.onopen();
  assert.deepEqual(ws.sent[0], { _tag: "Request", id: "1", tag: "orchestration.subscribeShell", payload: { requestCompletionMarker: true }, headers: [] });
  ws.onmessage({ data: JSON.stringify({ _tag: "Ping" }) });
  assert.equal(ws.sent.at(-1)._tag, "Pong");
  h.value({ kind: "snapshot", snapshot: shell() });
  h.clock.tick(0); assert.equal(h.output.length, 1);
  for (let i = 2; i <= 10; i++) h.value({ kind: "thread.updated", sequence: i, location: "active", thread: row({ title: `Example ${i}` }) });
  h.clock.tick(249); assert.equal(h.output.length, 1);
  h.clock.tick(1); assert.equal(h.output.length, 2);
  assert.equal(h.output[1].threads[0].title, "Example 10");
  h.value({ kind: "thread.updated", sequence: 11, location: "active", thread: row({ title: "Example 10" }) });
  h.clock.tick(250); assert.equal(h.output.length, 2);
  h.feed.close(); assert.equal(await h.feed.done, 0);
});

test("reconnect emits safe error lines, exponential backoff, resets only on data", async () => {
  const h = harness(); await h.flush(); h.sockets[0].onopen();
  h.sockets[0].onerror(new Error("DO NOT PRINT private ticket"));
  assert.deepEqual(h.output, [{ type: "error", message: "T3 shell connection lost; reconnecting" }]);
  h.clock.tick(499); await h.flush(); assert.equal(h.sockets.length, 1);
  h.clock.tick(1); await h.flush(); assert.equal(h.sockets.length, 2);
  h.sockets[1].onopen(); h.sockets[1].onclose();
  h.clock.tick(999); await h.flush(); assert.equal(h.sockets.length, 2);
  h.clock.tick(1); await h.flush(); assert.equal(h.sockets.length, 3);
  h.sockets[2].onopen(); h.value({ kind: "snapshot", snapshot: shell() }); h.clock.tick(0);
  h.sockets[2].onclose(); h.clock.tick(500); await h.flush();
  assert.equal(h.sockets.length, 4);
  h.sockets[3].onopen();
  assert.equal(h.sockets[3].sent[0].payload.afterSequence, 1);
  h.value({ kind: "synchronized" }); h.clock.tick(250);
  assert.equal(h.output.at(-1).type, "snapshot"); // same data re-emitted after an outage
  h.feed.close();
});

test("once writes exactly one snapshot and closes; once errors exit nonzero without retry", async () => {
  const h = harness({ once: true }); await h.flush(); h.sockets[0].onopen();
  h.value({ kind: "snapshot", snapshot: shell() });
  assert.equal(await h.feed.done, 0);
  assert.equal(h.output.length, 1); assert.equal(h.output[0].type, "snapshot");
  assert.equal(h.sockets[0].closed, true);
  const bad = harness({ once: true }); await bad.flush(); bad.sockets[0].onerror();
  assert.equal(await bad.feed.done, 1);
  bad.clock.tick(100000); await bad.flush(); assert.equal(bad.sockets.length, 1);
});

test("--archived loads its real RPC on the same socket and once waits for both responses", async () => {
  const h = harness({ once: true, archived: true }); await h.flush();
  const ws = h.sockets[0]; ws.onopen();
  const rpc = ws.sent.find(m => m.tag === "orchestration.getArchivedShellSnapshot");
  assert.ok(rpc);
  h.value({ kind: "snapshot", snapshot: shell() });
  assert.equal(h.output.length, 0);
  ws.onmessage({ data: JSON.stringify({ _tag: "Exit", requestId: rpc.id, exit: { _tag: "Success", value: { threads: [row({ id: "archived", archivedAt: at })] } } }) });
  assert.equal(await h.feed.done, 0);
  assert.deepEqual(h.output[0].threads.map(t => t.id), ["t", "archived"]);
});

test("--archived refreshes after removals instead of dropping archived rows", async () => {
  const h = harness({ archived: true }); await h.flush();
  const ws = h.sockets[0]; ws.onopen();
  const answer = threads => {
    const rpc = ws.sent.findLast(m => m.tag === "orchestration.getArchivedShellSnapshot");
    ws.onmessage({ data: JSON.stringify({ _tag: "Exit", requestId: rpc.id, exit: { _tag: "Success", value: { threads } } }) });
  };
  answer([]); h.value({ kind: "snapshot", snapshot: shell() }); h.clock.tick(0);
  h.value({ kind: "thread.removed", sequence: 2, location: "active", threadId: "t" });
  h.clock.tick(250);
  answer([row({ archivedAt: at })]); h.clock.tick(250);
  assert.equal(h.output.at(-1).threads[0].archived, true);
  h.feed.close();
});

test("archive resume cannot publish stale active rows before shell catches up", async () => {
  const h = harness({ archived: true }); await h.flush();
  const answer = () => {
    const ws = h.sockets.at(-1), rpc = ws.sent.findLast(m => m.tag === "orchestration.getArchivedShellSnapshot");
    ws.onmessage({ data: JSON.stringify({ _tag: "Exit", requestId: rpc.id, exit: { _tag: "Success", value: { threads: [] } } }) });
  };
  h.sockets[0].onopen(); answer(); h.value({ kind: "snapshot", snapshot: shell() }); h.clock.tick(0);
  h.sockets[0].onclose(); h.clock.tick(500); await h.flush(); h.sockets[1].onopen(); answer();
  h.clock.tick(250); assert.equal(h.output.at(-1).type, "error");
  h.value({ kind: "synchronized" }); h.clock.tick(0); assert.equal(h.output.at(-1).type, "snapshot");
  h.feed.close();
});

test("archive failures and deadlines emit only safe errors and terminate --once", async () => {
  for (const mode of ["failure", "invalid", "timeout"]) {
    const h = harness({ once: true, archived: true }); await h.flush();
    const ws = h.sockets[0]; ws.onopen(); h.value({ kind: "snapshot", snapshot: shell() });
    const rpc = ws.sent.find(m => m.tag === "orchestration.getArchivedShellSnapshot");
    if (mode === "timeout") h.clock.tick(10000);
    else ws.onmessage({ data: JSON.stringify({ _tag: "Exit", requestId: rpc.id, exit: mode === "failure" ? { _tag: "Failure", cause: "private" } : { _tag: "Success", value: {} } }) });
    assert.equal(await h.feed.done, 1);
    assert.equal(h.output.length, 1); assert.equal(h.output[0].type, "error");
    assert.ok(!JSON.stringify(h.output).includes("private"));
  }
});

test("auth errors are safe and --once resolves nonzero", async () => {
  const lines = [];
  const feed = startFeed({ once: true }, {
    openSocket: async () => { throw new Error("private bearer token"); },
    write: line => lines.push(JSON.parse(line)),
  });
  assert.equal(await feed.done, 1);
  assert.deepEqual(lines, [{ type: "error", message: "T3 shell unavailable; reconnecting" }]);
});

test("timeout, malformed stream and RPC exit recover without leaking server error bodies", async () => {
  for (const kind of ["timeout", "invalid", "exit", "defect"]) {
    const h = harness(); await h.flush(); h.sockets[0].onopen();
    if (kind === "timeout") h.clock.tick(10000);
    else h.sockets[0].onmessage({ data: kind === "invalid" ? "private broken JSON" : JSON.stringify({ _tag: kind === "exit" ? "Exit" : "Defect", requestId: "1", exit: { cause: "private" } }) });
    assert.equal(h.output[0].type, "error");
    assert.ok(!JSON.stringify(h.output).includes("private"));
    h.clock.tick(500); await h.flush(); assert.equal(h.sockets.length, 2);
    h.feed.close();
  }
});

test("snapshot-required reloads, late values from old sockets are ignored, close cancels debounce", async () => {
  const h = harness(); await h.flush(); h.sockets[0].onopen();
  const old = h.sockets[0];
  h.value({ kind: "snapshot", snapshot: shell() }); h.clock.tick(0);
  h.value({ kind: "snapshot-required" }); h.clock.tick(500); await h.flush();
  h.sockets[1].onopen(); assert.equal(h.sockets[1].sent[0].payload.afterSequence, undefined);
  h.value({ kind: "thread.updated", sequence: 20, location: "active", thread: row({ title: "Stale" }) }, old);
  h.value({ kind: "snapshot", snapshot: shell([row({ title: "Fresh" })]) });
  h.feed.close(); h.clock.tick(1000);
  assert.equal(h.output.filter(x => x.type === "snapshot").length, 1);
});
