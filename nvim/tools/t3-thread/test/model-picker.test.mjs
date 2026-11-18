import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as t3 from "../t3.mjs";
import * as C from "../commands.mjs";
import * as L from "../layout.mjs";
const P = await import("../model-picker.mjs").catch((e) => {
  if (e.code !== "ERR_MODULE_NOT_FOUND") throw e;
  return {};
});
const config = JSON.parse(
  fs.readFileSync(new URL("./fixtures/model-config.json", import.meta.url)),
);
const providers = config.providers;
const selection = {
  instanceId: "codex",
  model: "gpt-6.1-sol",
  options: [
    { id: "reasoningEffort", value: "high" },
    { id: "serviceTier", value: "priority" },
  ],
};
const state = () =>
  t3.applyValue(null, {
    kind: "snapshot",
    snapshotSequence: 1,
    projection: {
      thread: {
        id: "throwaway",
        title: "(throwaway)",
        modelSelection: selection,
        providerInstanceId: "codex",
        activeProviderThreadId: null,
      },
    },
  });
const text = (l) => l.map((s) => s.text).join("");
const open = (s = state(), ps = providers) => P.open(ps, s);
const move = (p, ch, key = {}, s = state(), ps = providers) =>
  P.input(p, ch, key, ps, s).picker;

test("recorded server.getConfig produces desktop harness/model/effort labels and opens on selection", () => {
  const p = open(),
    cols = P.columns(p, providers, state());
  assert.deepEqual(
    cols[0].items.map((i) => i.label),
    ["Codex", "Claude", "OpenCode", "Pi"],
  );
  assert.equal(cols[0].items[cols[0].selected].id, "codex");
  assert.equal(cols[1].items[cols[1].selected].label, "GPT 6.1 Sol");
  assert.equal(cols[2].items[cols[2].selected].label, "High");
  assert.equal(P.selection(p, providers, state()).options[1].value, "priority");
});
test("motions cascade live; old model options never leak into a new model or harness", () => {
  let p = open();
  p = move(p, "l");
  p = move(p, "j");
  assert.equal(p.model, "gpt-6-astra");
  assert.deepEqual(P.selection(p, providers, state()).options, [
    { id: "reasoningEffort", value: "medium" },
  ]);
  p = move(p, "h");
  p = move(p, "j");
  assert.equal(p.instanceId, "claudeAgent");
  assert.equal(p.model, "claude-opus-5-5");
  assert.ok(
    !P.columns(p, providers, state())[2].items.some(
      (i) => i.id === "ultrathink",
    ),
  );
  assert.deepEqual(P.selection(p, providers, state()).options, [
    { id: "effort", value: "medium" },
  ]);
  p = move(p, "l");
  p = move(p, "G");
  assert.equal(p.model, "claude-sonnet-5-5");
  p = move(move(p, "g"), "g");
  assert.equal(p.model, "claude-opus-5-5");
  p = move(move(p, "l"), "G");
  assert.equal(P.selection(p, providers, state()).options[0].value, "max");
  p = move(p, "", { upArrow: true });
  assert.equal(P.selection(p, providers, state()).options[0].value, "xhigh");
  p = move(p, "p", { ctrl: true });
  assert.equal(P.selection(p, providers, state()).options[0].value, "high");
  p = move(p, "n", { ctrl: true });
  assert.equal(P.selection(p, providers, state()).options[0].value, "xhigh");
  p = move(p, "", { leftArrow: true });
  assert.equal(p.column, 1);
  p = move(p, "", { rightArrow: true });
  assert.equal(p.column, 2);
  assert.equal(P.input(p, "q", {}, providers, state()).action, "close");
  assert.equal(
    P.input(p, "", { escape: true }, providers, state()).action,
    "close",
  );
  assert.equal(
    P.input(p, "", { return: true }, providers, state()).action,
    "apply",
  );
});
test("handoff capability governs started-thread harness locks; disabled/unavailable instances cannot be picked", () => {
  const s = state();
  s.runs.set("r", { id: "r", status: "completed" });
  s.thread.activeProviderThreadId = "pt";
  s.providerThreads.set("pt", {
    id: "pt",
    appThreadId: "throwaway",
    providerInstanceId: "codex",
    providerSessionId: "ps",
  });
  s.providerSessions.set("ps", {
    id: "ps",
    status: "ready",
    capabilities: { sessions: { supportsProviderSwitchingViaHandoff: false } },
  });
  const p = open(s);
  const c = P.columns(p, providers, s);
  assert.match(c[0].items[1].reason, /new chat/i);
  assert.equal(move(p, "G", {}, s).instanceId, "codex");
  s.providerSessions.get(
    "ps",
  ).capabilities.sessions.supportsProviderSwitchingViaHandoff = true;
  assert.equal(move(p, "G", {}, s).instanceId, "pi");
  s.providerSessions.clear();
  assert.equal(
    move(p, "G", {}, s).instanceId,
    "pi",
    "saved app history allows handoff",
  );
  const ps = providers.map((p) =>
    p.instanceId === "pi"
      ? { ...p, availability: "unavailable", unavailableReason: "Install Pi" }
      : p,
  );
  assert.equal(move(open(), "G", {}, state(), ps).instanceId, "opencode");
});
test("missing catalog, retained unknown model, empty models and no effort are safe", () => {
  const s = state();
  s.thread.modelSelection = { instanceId: "pi", model: "default" };
  let p = open(s);
  assert.deepEqual(P.selection(p, providers, s), {
    instanceId: "pi",
    model: "default",
    options: [],
  });
  assert.equal(
    P.columns(p, providers, s)[2].items[0].label,
    "No effort levels",
  );
  p = open(s, []);
  assert.equal(P.selection(p, [], s), null);
  s.thread.modelSelection = { instanceId: "pi", model: "removed" };
  p = open(s);
  assert.equal(p.model, "removed");
  assert.equal(P.selection(p, providers, s), null);
  const ps = [{ ...providers[0], models: [] }];
  p = open(state(), ps);
  assert.equal(P.selection(p, ps, state()), null);
});
test("/model is a built-in action, not provider text, even before the catalog loads", () => {
  for (const cat of [
    null,
    {
      slashCommands: [{ name: "model", description: "provider override" }],
      skills: [],
    },
  ]) {
    const m = C.menu("/model", 6, cat);
    assert.equal(m.items.length, 1);
    assert.equal(m.items[0].action, "model");
    assert.equal(m.items[0].insert, undefined);
  }
  assert.ok(
    !C.menu("/model extra", 6, { slashCommands: [], skills: [] }).items.some(
      (i) => i.action === "model",
    ),
  );
});
test("frame puts one three-column picker above composer, keeps dimensions, and themes focused row", () => {
  for (const [cols, rows] of [
    [80, 24],
    [155, 40],
  ]) {
    const s = state(),
      p = open(s),
      tokens = {
        surface: "surface",
        user_bubble: "selected",
        fg: "fg",
        muted: "muted",
        faint: "faint",
        accent: "accent",
      };
    const f = L.frame({
      state: s,
      cols,
      rows,
      tokens,
      ui: {
        modelPicker: P.columns(p, providers, s),
        editor: { value: "", cursor: 0 },
      },
    });
    const lines = f.lines.map(text);
    const at = lines.findIndex(
      (l) =>
        l.includes("Harness") && l.includes("Model") && l.includes("Effort"),
    );
    assert.ok(at > 0);
    assert.ok(lines.findIndex((l) => l.includes("✳")) > at);
    assert.ok(lines.length < rows);
    assert.ok(f.lines.every((l) => L.displayWidth(text(l)) === cols));
    assert.ok(
      f.lines.some((l) =>
        l.some((s) => s.bg === "selected" && s.text.includes("Codex")),
      ),
    );
    assert.match(text(f.status), /gg\/G/);
    const ansi = L.frame({
      state: s,
      cols,
      rows,
      ui: { modelPicker: P.columns(p, providers, s) },
    });
    assert.ok(
      ansi.lines.some((l) =>
        l.some((s) => s.inverse && s.text.includes("Codex")),
      ),
    );
  }
});
test("selection command uses exact orchestration-v2 payload and event alone updates model label", () => {
  assert.equal(typeof t3.modelSelectionCommand, "function");
  const command = t3.modelSelectionCommand("throwaway", selection);
  assert.match(command.commandId, /^[\da-f-]{36}$/);
  assert.deepEqual(command, {
    type: "thread.model-selection.set",
    commandId: command.commandId,
    threadId: "throwaway",
    modelSelection: selection,
  });
  const s = state();
  const updated = {
    ...selection,
    model: "gpt-6-astra",
    options: [{ id: "reasoningEffort", value: "max" }],
  };
  t3.modelSelectionCommand("throwaway", updated);
  assert.equal(s.thread.modelSelection.model, "gpt-6.1-sol");
  const next = t3.applyValue(s, {
    kind: "event",
    sequence: 2,
    event: {
      type: "thread.model-selection-updated",
      payload: { ...s.thread, modelSelection: updated },
    },
  });
  assert.deepEqual(t3.modelLabel(next.thread), {
    name: "gpt-6-astra",
    effort: "Max",
  });
});

test("boolean thinking stays boolean on the wire and displays On/Off rather than True/False", () => {
  const ps = [
    {
      ...providers[0],
      models: [
        {
          slug: "boolean-model",
          name: "Boolean model",
          capabilities: {
            optionDescriptors: [
              { id: "thinking", type: "boolean", currentValue: true },
            ],
          },
        },
      ],
    },
  ];
  const s = state();
  s.thread.modelSelection = {
    instanceId: "codex",
    model: "boolean-model",
    options: [{ id: "thinking", value: true }],
  };
  let p = open(s, ps);
  assert.equal(P.selection(p, ps, s).options[0].value, true);
  p = move(move(p, "l", {}, s, ps), "l", {}, s, ps);
  p = move(p, "j", {}, s, ps);
  assert.equal(P.selection(p, ps, s).options[0].value, false);
  assert.equal(t3.modelLabel(s.thread).effort, "On");
  assert.equal(
    t3.modelLabel({ ...s.thread, modelSelection: P.selection(p, ps, s) })
      .effort,
    "Off",
  );
});

test("setModel dispatches through the adapter socket without projecting an optimistic change", async (t) => {
  const oldToken = process.env.T3_SESSION_TOKEN;
  process.env.T3_SESSION_TOKEN = "fixture-only";
  t.after(() => {
    if (oldToken === undefined) delete process.env.T3_SESSION_TOKEN;
    else process.env.T3_SESSION_TOKEN = oldToken;
  });
  // A local ticket endpoint (never the default live server) and a fresh adapter.
  const http = await import("node:http");
  const server = http.createServer((req, res) => {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ ticket: "fixture-ticket" }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const oldURL = process.env.T3_URL;
  process.env.T3_URL = `http://127.0.0.1:${server.address().port}`;
  t.after(() => (oldURL === undefined ? delete process.env.T3_URL : (process.env.T3_URL = oldURL)));
  const t3 = await import(`../t3.mjs?model-picker=${crypto.randomUUID()}`);
  const sent = [];
  let socket;
  let connected;
  const ready = new Promise((resolve) => (connected = resolve));
  class Socket {
    static OPEN = 1;
    readyState = 1;
    constructor() {
      socket = this;
      queueMicrotask(() => {
        this.onopen();
        connected();
      });
    }
    send(raw) {
      const message = JSON.parse(raw);
      if (message._tag !== "Request") return;
      sent.push(message);
      if (message.tag === "orchestration.subscribeThread") return;
      queueMicrotask(() =>
        this.onmessage({
          data: JSON.stringify({
            _tag: "Exit",
            requestId: message.id,
            exit: { _tag: "Success", value: {} },
          }),
        }),
      );
    }
    close() {
      this.readyState = 3;
      this.onclose?.();
    }
  }
  t.mock.property(globalThis, "WebSocket", Socket);
  const observed = [];
  const close = t3.subscribe("throwaway", { onState: (s) => observed.push(s) });
  t.after(close);
  await ready;
  await close.setModel(selection);
  const message = sent.find((m) => m.tag === "orchestration.dispatchCommand");
  assert.deepEqual(message, {
    _tag: "Request",
    id: message.id,
    tag: "orchestration.dispatchCommand",
    payload: {
      type: "thread.model-selection.set",
      commandId: message.payload.commandId,
      threadId: "throwaway",
      modelSelection: selection,
    },
    headers: [],
  });
  assert.equal(
    observed.length,
    0,
    "RPC success alone cannot update the projection",
  );
  socket.onmessage({
    data: JSON.stringify({
      _tag: "Chunk",
      requestId: "1",
      values: [
        {
          kind: "snapshot",
          snapshotSequence: 3,
          projection: {
            thread: { id: "throwaway", modelSelection: selection },
          },
        },
      ],
    }),
  });
  assert.equal(observed[0].thread.modelSelection.model, selection.model);
});

test("boolean thinking without currentValue defaults Off like the desktop", () => {
  const ps = [
    {
      ...providers[0],
      models: [
        {
          slug: "boolean-model",
          name: "Boolean model",
          capabilities: {
            optionDescriptors: [{ id: "thinking", type: "boolean" }],
          },
        },
      ],
    },
  ];
  const s = state();
  s.thread.modelSelection = { instanceId: "codex", model: "boolean-model" };
  assert.deepEqual(P.selection(open(s, ps), ps, s).options, [
    { id: "thinking", value: false },
  ]);
});
