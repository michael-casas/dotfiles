import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import * as t3 from "../t3.mjs";
const item = (id, ordinal, type = "command_execution", more = {}) => ({
  id,
  threadId: "t",
  runId: "r",
  nodeId: "root",
  ordinal,
  type,
  status: "completed",
  input: "echo hi",
  ...more,
});
const snapshot = (items = [], more = {}) =>
  t3.applyValue(null, {
    kind: "snapshot",
    snapshotSequence: 1,
    projection: {
      thread: { id: "t" },
      runs: [
        {
          id: "r",
          ordinal: 1,
          status: "completed",
          startedAt: "2026-01-01T00:00:00Z",
          completedAt: "2026-01-01T00:00:06.600Z",
        },
      ],
      turnItems: items,
      visibleTurnItems: items.map((it, position) => ({
        position,
        visibility: "local",
        sourceThreadId: "t",
        sourceItemId: it.id,
        item: it,
      })),
      ...more,
    },
  });
const event = (s, type, payload, sequence = 2) =>
  t3.applyValue(s, { kind: "event", sequence, event: { type, payload } });
test("projection respects visible position, inserts/reorders local rows, keeps inherited order", () => {
  let s = snapshot([item("b", 20), item("a", 10)]);
  assert.deepEqual(
    t3.timeline(s).map((x) => x.id),
    ["b", "a"],
  );
  s = event(s, "turn-item.updated", item("c", 15));
  assert.deepEqual(
    t3.timeline(s).map((x) => x.id),
    ["c", "b", "a"],
  );
  s = event(s, "turn-item.updated", item("b", 5), 3);
  assert.deepEqual(
    t3.timeline(s).map((x) => x.id),
    ["b", "c", "a"],
  );
  assert.deepEqual(
    s.visibleTurnItems.map((x) => x.position),
    [0, 1, 2],
  );
});
test("hidden rows and queued restoration follow run and attempt updates", () => {
  let s = snapshot(
    [
      item("q", 1, "user_message", { inputIntent: "queued_turn" }),
      item("cp", 2, "checkpoint"),
      item("prep", 3, "command_execution", { input: "Preparing workspace" }),
      item("stop", 4, "run_interrupt_request"),
      item("tool", 5),
    ],
    { runs: [{ id: "r", status: "queued" }] },
  );
  assert.deepEqual(
    t3.timeline(s).map((x) => x.id),
    ["tool"],
  );
  s = event(s, "run.updated", { id: "r", status: "running" });
  assert.deepEqual(
    t3.timeline(s).map((x) => x.id),
    ["q", "tool"],
  );
  s = event(s, "run.updated", { id: "r", status: "rolled_back" }, 3);
  assert.equal(t3.timeline(s).length, 0);
});
test("complete protocol fold advances unknown events and rejects duplicate events", () => {
  let s = snapshot();
  s = event(s, "run-attempt.updated", {
    id: "a",
    runId: "r",
    status: "superseded",
  });
  assert.equal(s.attempts.get("a").status, "superseded");
  s = event(s, "checkpoint.captured", { id: "cp" }, 3);
  assert.ok(s.checkpoints.has("cp"));
  s = t3.applyValue(s, { kind: "unknown-event", sequence: 4 });
  assert.equal(s.seq, 4);
  s = event(s, "run.updated", { id: "r", status: "failed" }, 3);
  assert.equal(s.runs.get("r").status, "completed");
  s = t3.applyValue(s, { kind: "synchronized" });
  assert.equal(s.synchronized, true);
});
test("expired and internal requests do not block; preparing and waiting runs work", () => {
  let s = snapshot([], {
    runtimeRequests: [
      { id: "x", status: "expired" },
      { id: "auth", status: "pending", kind: "auth_refresh" },
    ],
  });
  assert.equal(t3.status(s), "done");
  s = event(s, "run.updated", { id: "r", status: "preparing" });
  assert.equal(t3.status(s), "working");
  s = event(
    s,
    "runtime-request.updated",
    { id: "approve", status: "pending", kind: "command" },
    3,
  );
  assert.equal(t3.status(s), "blocked");
});
test("dispatch defaults to steer, queue omits delivery intent; interrupt gates capabilities", () => {
  assert.equal(typeof t3.messageCommand, "function");
  const c = t3.messageCommand("t", "hi");
  assert.equal(c.deliveryIntent, "steer");
  assert.equal(c.dispatchMode.type, "start_immediately");
  const q = t3.messageCommand("t", "hi", { queue: true });
  assert.equal(q.dispatchMode.type, "queue_after_active");
  assert.ok(!("deliveryIntent" in q));
  assert.equal(
    t3.stopCommand("t", "r", { threadStop: true }).type,
    "thread.stop",
  );
  assert.equal(t3.stopCommand("t", "r", {}).holdQueue, true);
});
test("tool summaries exclude reasoning and select priority actions", async () => {
  const ui = await import("../view.mjs");
  assert.equal(
    ui.summarize([
      item("a", 1),
      item("b", 2),
      item("c", 3, "dynamic_tool", { toolName: "Read" }),
      item("d", 4, "reasoning"),
    ]),
    "Ran 2 commands and read 1 file",
  );
  assert.equal(
    ui.summarize([item("d", 4, "reasoning"), item("e", 5, "reasoning")]),
    "Thought (×2)",
  );
});
test("three-level fold preserves final reply, notifications; live row only shows latest tool", async () => {
  const ui = await import("../view.mjs");
  const s = snapshot([
    item("u", 1, "user_message", { text: "hello" }),
    item("a", 2),
    item("b", 3),
    item("final", 4, "assistant_message", { text: "answer" }),
    item("note", 5, "notification", { summary: "done" }),
  ]);
  let rows = ui.rows(s, new Set());
  assert.ok(rows.some((x) => x.text === "Worked for 6.6s"));
  assert.ok(rows.some((x) => x.text === "answer"));
  assert.ok(rows.some((x) => x.text === "done"));
  assert.ok(!rows.some((x) => x.id === "a"));
  rows = ui.rows(s, new Set(["turn:r"]));
  const g = rows.find((x) => x.kind === "group");
  assert.equal(g.text, "Ran 2 commands");
  rows = ui.rows(s, new Set(["turn:r", g.id]));
  assert.ok(rows.some((x) => x.id === "a"));
  const live = event(s, "run.updated", { id: "r", status: "running" });
  live.turnItems.get("b").status = "running";
  rows = ui.rows(live, new Set(), Date.parse("2026-01-01T00:00:05Z"));
  assert.ok(rows.some((x) => x.text === "Working for 5s"));
  assert.ok(rows.some((x) => x.text === "Running echo"));
  assert.ok(!rows.some((x) => x.id === "a"));
});
test("composer filters control keys without inserting literal letters", async () => {
  const ui = await import("../view.mjs");
  assert.equal(ui.editInput("hello", 5, "u", { ctrl: true }).value, "");
  assert.equal(ui.editInput("hello", 5, "d", { ctrl: true }).value, "hello");
  assert.equal(ui.editInput("hello", 5, "!", {}).value, "hello!");
});
test("rendering preserves interleaved run order and pending steer position", async () => {
  const ui = await import("../view.mjs");
  const s = snapshot(
    [
      item("u1", 1, "user_message", { text: "first" }),
      item("a", 2, "assistant_message", {
        text: "earlier commentary",
        phase: "commentary",
      }),
      item("u2", 3, "user_message", { runId: "other", text: "steer" }),
      item("reply", 4, "assistant_message", { text: "later response" }),
    ],
    {
      runs: [
        { id: "r", status: "running" },
        { id: "other", status: "running" },
      ],
    },
  );
  const ids = ui
    .rows(s)
    .filter((r) => ["u1", "a", "u2", "reply"].includes(r.id))
    .map((r) => r.id);
  assert.deepEqual(ids, ["u1", "a", "u2", "reply"]);
});
test("stale superseded interrupt is hidden, paired explicit stop stays visible", () => {
  let s = snapshot([item("stop", 1, "run_interrupt_result")], {
    attempts: [
      { id: "att", runId: "r", rootNodeId: "root", status: "superseded" },
    ],
  });
  assert.equal(t3.timeline(s).length, 0);
  s = event(s, "turn-item.updated", item("req", 2, "run_interrupt_request"));
  assert.deepEqual(
    t3.timeline(s).map((i) => i.id),
    ["stop"],
  );
});
test("question answers support numbered values, custom multi answers and strict rejection", async () => {
  const ui = await import("../view.mjs");
  assert.equal(typeof ui.answerInput, "function");
  const q = {
    id: "colour",
    options: [{ label: "Blue", value: "blue" }, { label: "Green" }],
  };
  assert.deepEqual(ui.answerInput(q, "1"), { answer: "blue" });
  assert.deepEqual(ui.answerInput({ ...q, multiSelect: true }, "1,2"), {
    answer: ["blue", "Green"],
  });
  assert.deepEqual(
    ui.answerInput({ ...q, multiSelect: true }, "custom choice"),
    { answer: "custom choice" },
  );
  assert.ok(
    ui.answerInput({ ...q, allowCustomAnswer: false }, "custom choice").error,
  );
  assert.ok(ui.answerInput(q, "1,2").error);
});
test("bounded snapshot does not resurrect old unloaded work but admits unfinished queued run", () => {
  let s = t3.applyValue(null, {
    kind: "snapshot",
    snapshotSequence: 1,
    hasMoreHistory: true,
    latestLocalTurnOrdinal: 20,
    projection: {
      thread: { id: "t" },
      runs: [
        { id: "old", status: "completed" },
        { id: "queued", status: "queued" },
      ],
      turnItems: [item("current", 20)],
      visibleTurnItems: [
        {
          position: 0,
          visibility: "local",
          sourceThreadId: "t",
          sourceItemId: "current",
          item: item("current", 20),
        },
      ],
    },
  });
  s = event(
    s,
    "turn-item.updated",
    item("old", 5, "command_execution", { runId: "old" }),
  );
  assert.deepEqual(
    t3.timeline(s).map((i) => i.id),
    ["current"],
  );
  s = event(
    s,
    "turn-item.updated",
    item("new-queued", 4, "user_message", {
      runId: "queued",
      inputIntent: "queued_turn",
    }),
    3,
  );
  s = event(s, "run.updated", { id: "queued", status: "running" }, 4);
  assert.deepEqual(
    t3.timeline(s).map((i) => i.id),
    ["new-queued", "current"],
  );
});
test("inherited rows keep position through local update and insertion", () => {
  const inherited = item("ancestor", 100, "assistant_message", {
      threadId: "parent",
    }),
    local = item("local", 20);
  let s = snapshot([inherited, local]);
  s.visibleTurnItems[0].visibility = "inherited";
  s.visibleTurnItems[0].sourceThreadId = "parent";
  s = event(s, "turn-item.updated", item("new", 10));
  assert.deepEqual(
    t3.timeline(s).map((i) => i.id),
    ["ancestor", "new", "local"],
  );
  s = event(
    s,
    "turn-item.updated",
    item("local", 20, "command_execution", { status: "failed" }),
    3,
  );
  assert.equal(t3.timeline(s)[2].status, "failed");
  assert.equal(s.visibleTurnItems[0].visibility, "inherited");
});
