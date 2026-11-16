import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { once } from "node:events";
import * as t3 from "../t3.mjs";

const state = (thread = {}, projection = {}) =>
  t3.applyValue(null, {
    kind: "snapshot",
    snapshotSequence: 1,
    projection: { thread: { id: "t", ...thread }, ...projection },
  });

const thread = {
  title: "envi t3 spike test",
  projectId: "p",
  branch: "feat/x",
  worktreePath: "/worktrees/dotfiles/envi-main",
};

test("threadMeta resolves project and worktree data without changing the projection", () => {
  assert.equal(typeof t3.threadMeta, "function");
  const s = state(thread);
  const projects = new Map([
    ["p", { title: ".dotfiles", workspaceRoot: "/home/user/.dotfiles" }],
  ]);
  assert.deepEqual(t3.threadMeta(s, projects), {
    title: thread.title,
    projectId: "p",
    projectTitle: ".dotfiles",
    projectInitials: "DS",
    workspaceRoot: "/home/user/.dotfiles",
    branch: "feat/x",
    worktreePath: thread.worktreePath,
    worktreeName: "envi-main",
  });
  assert.deepEqual(s.thread, { id: "t", ...thread });
  assert.equal(projects.get("p").title, ".dotfiles");
});

test("threadMeta tolerates missing project metadata, absent state and no worktree", () => {
  assert.equal(typeof t3.threadMeta, "function");
  const s = state({ ...thread, worktreePath: null, branch: null });
  assert.deepEqual(t3.threadMeta(s), {
    title: thread.title,
    projectId: "p",
    projectTitle: "",
    projectInitials: "",
    workspaceRoot: null,
    branch: null,
    worktreePath: null,
    worktreeName: null,
  });
  assert.deepEqual(t3.threadMeta(null), {
    title: "",
    projectId: null,
    projectTitle: "",
    projectInitials: "",
    workspaceRoot: null,
    branch: null,
    worktreePath: null,
    worktreeName: null,
  });
  assert.equal(t3.threadMeta(s, new Map()).projectTitle, "");
  assert.equal(
    t3.threadMeta(s, new Map([["other", { title: "Wrong project" }]])).projectTitle,
    "",
  );
});

test("threadMeta falls back to workspace basename and derives the required initials", () => {
  assert.equal(typeof t3.threadMeta, "function");
  for (const [title, initials] of [
    [".dotfiles", "DS"],
    ["Workspace", "WO"],
    ["ops-platform", "OP"],
  ]) {
    const s = state(thread);
    assert.equal(
      t3.threadMeta(s, new Map([["p", { title, workspaceRoot: "/wrong" }]])).projectInitials,
      initials,
    );
    assert.equal(
      t3.threadMeta(s, new Map([["p", { workspaceRoot: `/projects/${title}/` }]])).projectTitle,
      title,
    );
  }
  const windows = t3.threadMeta(
    state({ ...thread, worktreePath: "C:\\worktrees\\envi-main\\" }),
    new Map([["p", { title: "", workspaceRoot: "C:\\projects\\Workspace\\" }]]),
  );
  assert.equal(windows.worktreeName, "envi-main");
  assert.equal(windows.projectTitle, "Workspace");
});

test("threadMeta disambiguates worktree folders matching the workspace basename or project title", () => {
  const cases = [
    {
      project: { title: "Dotfiles config", workspaceRoot: "/home/user/.dotfiles" },
      worktreePath: "/home/user/.dotfiles/.treehouse/.dotfiles-0c8f72/2/.dotfiles",
      expected: "2/.dotfiles",
    },
    {
      project: { title: "ops-platform", workspaceRoot: "/projects/renamed-repo" },
      worktreePath: "/worktrees/seat-3/ops-platform/",
      expected: "seat-3/ops-platform",
    },
    {
      project: { title: "ops-platform" },
      worktreePath: "/worktrees/seat-3/ops-platform",
      expected: "seat-3/ops-platform",
    },
    {
      project: { title: ".dotfiles", workspaceRoot: "/home/user/.dotfiles" },
      worktreePath: "/worktrees/dotfiles/envi-main",
      expected: "envi-main",
    },
    {
      project: { title: "Dotfiles config", workspaceRoot: "C:\\projects\\.dotfiles\\" },
      worktreePath: "C:\\treehouse\\2\\.dotfiles\\",
      expected: "2/.dotfiles",
    },
  ];
  for (const { project, worktreePath, expected } of cases) {
    const meta = t3.threadMeta(state({ ...thread, worktreePath }), new Map([["p", project]]));
    assert.equal(meta.worktreeName, expected);
    assert.equal(meta.workspaceRoot, project.workspaceRoot ?? null);
    assert.equal(meta.worktreePath, worktreePath);
  }
});

test("threadMeta keeps the final worktree segment when no project match exists", () => {
  const s = state({ ...thread, worktreePath: "/worktrees/2/.dotfiles" });
  assert.equal(t3.threadMeta(s).worktreeName, ".dotfiles");
  assert.equal(t3.threadMeta(s, new Map()).workspaceRoot, null);
});

test("thread.metadata-updated folds branch/worktree changes and preserves the title", () => {
  let s = state(thread);
  s = t3.applyValue(s, {
    kind: "event",
    sequence: 2,
    event: {
      type: "thread.metadata-updated",
      payload: { branch: "feat/new", worktreePath: "/worktrees/new" },
    },
  });
  assert.equal(s.thread.title, thread.title);
  assert.equal(s.thread.branch, "feat/new");
  assert.equal(s.thread.worktreePath, "/worktrees/new");
  s = t3.applyValue(s, {
    kind: "event",
    sequence: 3,
    event: {
      type: "thread.metadata-updated",
      payload: { branch: null, worktreePath: null },
    },
  });
  assert.equal(s.thread.branch, null);
  assert.equal(s.thread.worktreePath, null);
});

test("modelLabel formats known Claude models and preserves unfamiliar model ids", () => {
  assert.equal(typeof t3.modelLabel, "function");
  for (const [model, name] of [
    ["claude-haiku-5-5", "Haiku 5.5"],
    ["claude-sonnet-5-5", "Sonnet 5.5"],
    ["claude-opus-4-6", "Opus 4.6"],
    ["j5/gpt-6.1-sol", "gpt-6.1-sol"],
    ["gpt-6.1-sol", "gpt-6.1-sol"],
    ["vendor/family/custom-v2", "custom-v2"],
  ]) {
    assert.deepEqual(t3.modelLabel({ modelSelection: { model } }), { name, effort: "" });
  }
  assert.deepEqual(t3.modelLabel(null), { name: "", effort: "" });
  assert.deepEqual(t3.modelLabel({}), { name: "", effort: "" });
});

test("modelLabel selects effort/thinking/reasoningEffort/variant in priority order", () => {
  assert.equal(typeof t3.modelLabel, "function");
  const model = "claude-haiku-5-5";
  for (const id of ["effort", "thinking", "reasoningEffort", "variant"]) {
    assert.deepEqual(
      t3.modelLabel({ modelSelection: { model, options: [{ id, value: "medium" }] } }),
      { name: "Haiku 5.5", effort: "Medium" },
    );
  }
  const options = [
    { id: "variant", value: "low" },
    { id: "reasoningEffort", value: "high" },
    { id: "thinking", value: "medium" },
    { id: "effort", value: "max" },
  ];
  assert.equal(t3.modelLabel({ modelSelection: { model, options } }).effort, "Max");
  assert.equal(t3.modelLabel({ modelSelection: { model, options: options.slice(0, 3) } }).effort, "Medium");
  assert.equal(t3.modelLabel({ modelSelection: { model, options: options.slice(0, 2) } }).effort, "High");
  assert.equal(t3.modelLabel({ modelSelection: { model, options: [{ id: "temperature", value: "high" }] } }).effort, "");
  // The existing effort() API retains its original wire-value behavior.
  assert.equal(t3.effort({ modelSelection: { options } }), "max");
});

test("statusLabel preserves labels and returns semantic theme token names", () => {
  const pending = (kind) => state({}, {
    runtimeRequests: [{ id: "request", kind, status: "pending" }],
  });
  assert.deepEqual(t3.statusLabel(pending("command")), ["Pending Approval", "warning"]);
  assert.deepEqual(t3.statusLabel(pending("user_input")), ["Awaiting Input", "attention"]);
  assert.deepEqual(t3.statusLabel(pending("command"), "offline"), ["Pending Approval", "warning"]);
  assert.deepEqual(t3.statusLabel(state(), "offline"), ["Connecting", "info"]);
  assert.deepEqual(t3.statusLabel(null, "new"), ["Not started", "muted"]);
  for (const [runStatus, label, token] of [
    ["running", "Working", "info"],
    ["completed", "Completed", "success"],
    ["failed", "Failed", "error"],
  ]) {
    assert.deepEqual(
      t3.statusLabel(state({}, { runs: [{ id: "r", status: runStatus }] })),
      [label, token],
    );
  }
  assert.deepEqual(t3.statusLabel(state()), ["Waiting", "muted"]);
  assert.deepEqual(t3.statusLabel(null), ["Waiting", "muted"]);
});

// Each imported adapter has its own process-lifetime cache; every request stays local.
async function withServer(t, handler) {
  const server = http.createServer(handler);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => new Promise((resolve) => {
    server.close(resolve);
    server.closeAllConnections();
  }));
  const oldURL = process.env.T3_URL;
  const oldToken = process.env.T3_SESSION_TOKEN;
  t.after(() => {
    if (oldURL === undefined) delete process.env.T3_URL;
    else process.env.T3_URL = oldURL;
    if (oldToken === undefined) delete process.env.T3_SESSION_TOKEN;
    else process.env.T3_SESSION_TOKEN = oldToken;
  });
  process.env.T3_URL = `http://127.0.0.1:${server.address().port}`;
  process.env.T3_SESSION_TOKEN = "local-test-token";
  return import(`../t3.mjs?projects-test=${crypto.randomUUID()}`);
}

test("projects authenticates protocol-2 GET and shares a process-lifetime cache", async (t) => {
  let calls = 0;
  const requests = [];
  const adapter = await withServer(t, (req, res) => {
    calls++;
    requests.push({ method: req.method, url: req.url, headers: req.headers });
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ projects: [
      { id: "p", title: ".dotfiles", workspaceRoot: "/projects/.dotfiles", extra: "not needed" },
      { id: "w", title: "Workspace", workspaceRoot: "/projects/Workspace" },
    ] }));
  });
  assert.equal(typeof adapter.projects, "function");
  // Read the override at call time, without opening the real session-token file.
  process.env.T3_SESSION_TOKEN = "updated-local-test-token";
  const [a, b] = await Promise.all([adapter.projects(), adapter.projects()]);
  assert.ok(a instanceof Map);
  assert.deepEqual([...a], [
    ["p", { title: ".dotfiles", workspaceRoot: "/projects/.dotfiles" }],
    ["w", { title: "Workspace", workspaceRoot: "/projects/Workspace" }],
  ]);
  assert.equal(a, b);
  assert.equal(await adapter.projects(), a);
  assert.equal(calls, 1);
  assert.equal(requests[0].method, "GET");
  assert.equal(requests[0].url, "/api/orchestration/shell");
  assert.equal(requests[0].headers.authorization, "Bearer updated-local-test-token");
  assert.equal(requests[0].headers["x-t3-orchestration-protocol"], "2");
});

for (const [name, status, body] of [
  ["400", 400, "request rejected"],
  ["resumable response", 200, JSON.stringify({ kind: "resumable", sequence: 42 })],
  ["invalid JSON", 200, "not JSON"],
]) {
  test(`projects returns an empty cached Map on ${name}`, async (t) => {
    let calls = 0;
    const adapter = await withServer(t, (_req, res) => {
      calls++;
      res.writeHead(status);
      res.end(body);
    });
    assert.equal(typeof adapter.projects, "function");
    const result = await adapter.projects();
    assert.ok(result instanceof Map);
    assert.equal(result.size, 0);
    assert.equal(await adapter.projects(), result);
    assert.equal(calls, 1);
  });
}

test("projects aborts a stalled HTTP response after five seconds", async (t) => {
  const adapter = await withServer(t, () => {});
  assert.equal(typeof adapter.projects, "function");
  const timeout = t.mock.method(AbortSignal, "timeout");
  const result = await adapter.projects();
  assert.ok(result instanceof Map);
  assert.equal(result.size, 0);
  assert.equal(timeout.mock.calls[0].arguments[0], 5000);
});
