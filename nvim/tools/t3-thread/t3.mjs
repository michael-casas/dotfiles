// Adapter for the local T3 Code server. Everything protocol-specific lives here,
// so a T3 protocol change touches one file.
//
// Wire format (verified against T3 v0.1.10-nightly, orchestration protocol 2):
//   POST /api/auth/websocket-ticket/rpc  (Authorization: Bearer <session token>) -> {ticket}
//   ws://HOST/ws?orchestrationProtocol=2&wsTicket=<ticket>
//   Effect RPC JSON frames: client {_tag:"Request",id,tag,payload,headers:[]}, {_tag:"Ack",requestId}
//   server {_tag:"Chunk",requestId,values:[...]}, {_tag:"Exit",...}
//   orchestration.subscribeThread {threadId} -> values: {kind:"snapshot",snapshotSequence,projection}
//                                              then  {kind:"event",sequence,event:{type:"<entity>.updated",payload}}
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import {
  RESTARTED, UPDATING, UpdatingError, assertNotUpdating, holdWhileUpdating, serverIdentity, updatingUntil,
} from "./update.mjs";

const run = promisify(execFile);
export const BASE = process.env.T3_URL || "http://127.0.0.1:3773";
export const T3 = process.env.T3_BIN || path.join(os.homedir(), ".t3/bin/t3");
const SESSION = path.join(os.homedir(), ".local/state/envi/t3-session.json");
const DEBUG = process.env.T3_THREAD_DEBUG; // file path: log unknown events there

export function debug(...a) {
  if (DEBUG)
    fs.appendFileSync(
      DEBUG,
      a.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(" ") +
        "\n",
    );
}

// ── auth ────────────────────────────────────────────────────────────────────
// The t3 CLI runs only after a live server rejected our token (HTTP 401), and
// never during a desktop update: it execs the app bundle the update swaps.
async function issueToken() {
  assertNotUpdating();
  const { stdout } = await run(T3, [
    "auth",
    "session",
    "issue",
    "--scope",
    "orchestration:read",
    "--scope",
    "orchestration:operate",
    "--ttl",
    "24h",
    "--label",
    "envi-t3-thread",
    "--json",
  ]);
  const session = JSON.parse(stdout);
  // Atomic: clients share this file and must never read a torn write.
  fs.mkdirSync(path.dirname(SESSION), { recursive: true });
  const tmp = `${SESSION}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, stdout, { mode: 0o600 });
  fs.chmodSync(tmp, 0o600); // mode only applies when the file is created
  fs.renameSync(tmp, SESSION);
  return session;
}
let issuing; // one CLI run per process, however many requests saw the 401
const reissue = () => (issuing ??= issueToken().finally(() => (issuing = undefined)));

// The single choke point for the t3 CLI: a missing, stale or near-expiry token
// is sent as is and replaced only after a live server's 401 (never when the
// server is unreachable, and never during an update).
function token() {
  if (process.env.T3_SESSION_TOKEN !== undefined)
    return process.env.T3_SESSION_TOKEN;
  try {
    const s = JSON.parse(fs.readFileSync(SESSION, "utf8"));
    if (s.token && Date.parse(s.expiresAt) - Date.now() > 5 * 60_000)
      return s.token;
  } catch {}
  return "";
}

async function authFetch(url, init = {}) {
  assertNotUpdating();
  const go = (tok) =>
    fetch(url, { ...init, headers: { ...init.headers, authorization: `Bearer ${tok}` } });
  const r = await go(token());
  // An explicit T3_SESSION_TOKEN is never replaced (tests, isolated servers).
  if (r.status !== 401 || process.env.T3_SESSION_TOKEN !== undefined) return r;
  return go((await reissue()).token);
}

async function ticket() {
  const r = await authFetch(`${BASE}/api/auth/websocket-ticket/rpc`, { method: "POST" });
  if (!r.ok) throw new Error(`websocket ticket: HTTP ${r.status}`);
  return (await r.json()).ticket;
}

// Additive transport factory for the sidebar shell feed. Reuse the same auth
// path without changing the thread client's subscription or token lifecycle.
export async function openShellSocket() {
  const authTicket = await ticket();
  return new WebSocket(
    `${BASE.replace(/^http/, "ws")}/ws?orchestrationProtocol=2&wsTicket=${encodeURIComponent(authTicket)}`,
  );
}

// ── project metadata ────────────────────────────────────────────────────────
let projectCache;
export async function projects() {
  projectCache ??= (async () => {
    try {
      const response = await authFetch(`${BASE}/api/orchestration/shell`, {
        headers: { "x-t3-orchestration-protocol": "2" },
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) {
        debug("projects unavailable", `HTTP ${response.status}`);
        return new Map();
      }
      const body = await response.json();
      return new Map(
        (body.projects || []).map(({ id, title, workspaceRoot }) => [
          id,
          { title, workspaceRoot },
        ]),
      );
    } catch (e) {
      // Error bodies/messages can contain credentials; log only the failure class.
      try {
        debug("projects unavailable", e?.name || "Error");
      } catch {}
      return new Map();
    }
  })();
  return projectCache;
}

const basename = (value) =>
  String(value || "").split(/[\\/]/).findLast(Boolean) || "";

export function threadMeta(state, projectMap) {
  const thread = state?.thread;
  const project = projectMap?.get(thread?.projectId);
  const workspaceRoot = project?.workspaceRoot ?? null;
  const projectTitle = project?.title || basename(workspaceRoot);
  const letters = projectTitle.replace(/[^\p{L}\p{N}]/gu, "");
  const worktreeParts = String(thread?.worktreePath || "").split(/[\\/]/).filter(Boolean);
  const worktreeBase = worktreeParts.at(-1);
  const worktreeName = worktreeBase &&
    (worktreeBase === basename(workspaceRoot) || worktreeBase === projectTitle)
    ? worktreeParts.slice(-2).join("/")
    : worktreeBase || null;
  return {
    title: thread?.title || "",
    projectId: thread?.projectId ?? null,
    projectTitle,
    projectInitials:
      projectTitle === ".dotfiles"
        ? "DS"
        : Array.from(letters).slice(0, 2).join("").toUpperCase(),
    workspaceRoot,
    branch: thread?.branch ?? null,
    worktreePath: thread?.worktreePath ?? null,
    worktreeName,
  };
}

export function modelLabel(thread) {
  const selection = thread?.modelSelection;
  const id = String(selection?.model || "").split("/").at(-1);
  const claude = /^claude-(haiku|sonnet|opus)-(\d+)-(\d+)$/.exec(id);
  const value = ["effort", "thinking", "reasoningEffort", "variant"]
    .map((id) => selection?.options?.find((o) => o.id === id))
    .find(Boolean)?.value;
  const effort = typeof value === "boolean"
    ? (value ? "On" : "Off")
    : value == null ? "" : String(value);
  return {
    name: claude
      ? `${claude[1][0].toUpperCase()}${claude[1].slice(1)} ${claude[2]}.${claude[3]}`
      : id,
    effort: effort ? effort[0].toUpperCase() + effort.slice(1) : "",
  };
}

// ── thread state ────────────────────────────────────────────────────────────
// Event type prefix -> projection collection (records are upserted by id).
const COLLECTION = {
  "turn-item": "turnItems",
  node: "nodes",
  run: "runs",
  "run-attempt": "attempts",
  message: "messages",
  "provider-turn": "providerTurns",
  "provider-thread": "providerThreads",
  "provider-session": "providerSessions",
  "runtime-request": "runtimeRequests",
  subagent: "subagents",
  plan: "plans",
  checkpoint: "checkpoints",
  "checkpoint-scope": "checkpointScopes",
  "context-handoff": "contextHandoffs",
  "context-transfer": "contextTransfers",
};

export function applyValue(state, v) {
  if (v.kind === "snapshot") {
    const p = v.projection;
    const s = {
      thread: p.thread,
      seq: v.snapshotSequence,
      visibleTurnItems: [...(p.visibleTurnItems || [])].sort(
        (a, b) => a.position - b.position,
      ),
      hasMoreHistory: v.hasMoreHistory,
      historyCursor: v.historyCursor,
      latestLocalTurnOrdinal: v.latestLocalTurnOrdinal,
    };
    for (const c of Object.values(COLLECTION))
      s[c] = new Map((p[c] || []).map((x) => [x.id, x]));
    return s;
  }
  if (!state) return state;
  if (v.kind === "synchronized") return { ...state, synchronized: true };
  if (!["event", "unknown-event"].includes(v.kind) || v.sequence <= state.seq)
    return state;
  const next = { ...state, seq: v.sequence };
  if (v.kind === "unknown-event") return next;
  const { type, payload } = v.event || {};
  const [entity, verb] = String(type).split(/\.(?=[^.]+$)/);
  if (entity === "thread") {
    next.thread = verb === "deleted" ? null : { ...state.thread, ...payload };
    return next;
  }
  const c = COLLECTION[entity];
  if (!c || !payload?.id) {
    debug("unhandled", type);
    return next;
  }
  const m = new Map(state[c]);
  if (type === "provider-session.detached") m.delete(payload.id);
  else m.set(payload.id, { ...(m.get(payload.id) || {}), ...payload });
  next[c] = m;
  if (entity === "turn-item")
    next.visibleTurnItems = upsertVisible(next, m.get(payload.id));
  return next;
}

function upsertVisible(state, item) {
  const rows = state.visibleTurnItems;
  const index = rows.findLastIndex((r) => r.sourceItemId === item.id);
  const prev = rows[index];
  const row = {
    position: 0,
    visibility: "local",
    sourceThreadId: item.threadId,
    sourceItemId: item.id,
    item,
  };
  if (
    prev?.visibility === "local" &&
    prev.sourceThreadId === item.threadId &&
    prev.item.ordinal === item.ordinal
  ) {
    return rows.map((r, i) =>
      i === index ? { ...row, position: r.position } : r,
    );
  }
  if (
    index < 0 &&
    state.hasMoreHistory &&
    !isActive(state.runs.get(item.runId)) &&
    !rows.some(
      (r) =>
        r.visibility === "local" &&
        r.item.runId === item.runId &&
        r.item.ordinal <= item.ordinal,
    ) &&
    item.ordinal <=
      (state.latestLocalTurnOrdinal ??
        Math.min(
          ...rows
            .filter((r) => r.visibility === "local")
            .map((r) => r.item.ordinal),
        ) - 1)
  )
    return rows;
  const updated = rows.filter((_, i) => i !== index);
  const insertion = updated.findIndex(
    (r) =>
      r.visibility === "local" &&
      (r.item.ordinal > item.ordinal ||
        (r.item.ordinal === item.ordinal &&
          String(r.item.id).localeCompare(String(item.id)) > 0)),
  );
  updated.splice(insertion < 0 ? updated.length : insertion, 0, row);
  return updated.map((r, position) => ({ ...r, position }));
}

export const isActive = (run) =>
  ["preparing", "queued", "starting", "running", "waiting"].includes(
    run?.status,
  );
export const pendingRequests = (state) =>
  [...(state?.runtimeRequests?.values() || [])].filter(
    (r) =>
      r.status === "pending" &&
      !["auth_refresh", "dynamic_tool_call"].includes(r.kind),
  );
export const activeRun = (state) =>
  [...(state?.runs?.values() || [])]
    .filter(isActive)
    .sort((a, b) => b.ordinal - a.ordinal)[0];

/** Visible projection positions are authoritative, including inherited rows. */
export function timeline(state) {
  if (!state) return [];
  const all = [...state.turnItems.values()];
  return state.visibleTurnItems
    .filter(({ item }) => {
      if (["checkpoint", "run_interrupt_request"].includes(item.type))
        return false;
      if (
        item.type === "command_execution" &&
        item.input === "Preparing workspace"
      )
        return false;
      const run = state.runs.get(item.runId);
      if (run?.status === "rolled_back") return false;
      if (
        item.type === "user_message" &&
        item.inputIntent === "queued_turn" &&
        ["queued", "cancelled"].includes(run?.status)
      )
        return false;
      if (
        item.type === "run_interrupt_result" &&
        [...state.attempts.values()].some(
          (a) =>
            a.runId === item.runId &&
            a.rootNodeId === item.nodeId &&
            a.status === "superseded",
        ) &&
        !all.some(
          (i) => i.type === "run_interrupt_request" && i.runId === item.runId,
        )
      )
        return false;
      return true;
    })
    .map((r) => r.item);
}

/** working | blocked | done | idle | error (OSC 7501). */
export function status(state) {
  if (!state?.thread) return "idle";
  if (pendingRequests(state).length) return "blocked";
  if (activeRun(state)) return "working";
  const last = [...state.runs.values()].sort(
    (a, b) => b.ordinal - a.ordinal,
  )[0];
  return !last ? "idle" : last.status === "failed" ? "error" : "done";
}

export function statusLabel(state, conn = "live") {
  const pending = pendingRequests(state);
  if (pending.some((r) => r.kind !== "user_input"))
    return ["Pending Approval", "warning"];
  if (pending.length) return ["Awaiting Input", "attention"];
  // A new thread has no server state until its first prompt starts it.
  if (conn === "new") return ["Not started", "muted"];
  if (conn === UPDATING) return [UPDATING, "warning"];
  if (conn.startsWith(RESTARTED)) return [conn, "info"];
  if (conn !== "live") return ["Connecting", "info"];
  return {
    working: ["Working", "info"],
    done: ["Completed", "success"],
    error: ["Failed", "error"],
    idle: ["Waiting", "muted"],
  }[status(state)];
}

export function contextUsage(state) {
  const turns = [...(state?.providerTurns?.values() || [])].sort((a, b) =>
    String(b.startedAt).localeCompare(String(a.startedAt)),
  );
  const usage = turns.find((t) => t.tokenUsage?.maxTokens > 0)?.tokenUsage;
  return usage
    ? Math.min(100, Math.round((usage.usedTokens / usage.maxTokens) * 100))
    : null;
}

export function attemptId(state, item) {
  const turn = state.providerTurns.get(item.providerTurnId);
  if (turn?.runAttemptId) return turn.runAttemptId;
  let node = state.nodes.get(item.nodeId);
  const visited = new Set();
  for (const attempt of state.attempts.values()) {
    if (attempt.runId === item.runId && attempt.rootNodeId === item.nodeId)
      return attempt.id;
  }
  while (node && !visited.has(node.id)) {
    visited.add(node.id);
    const attempt = [...state.attempts.values()].find(
      (a) => a.runId === item.runId && a.rootNodeId === node.rootNodeId,
    );
    if (attempt) return attempt.id;
    node = state.nodes.get(node.parentNodeId);
  }
  return item.runId;
}

export function effort(thread) {
  return thread?.modelSelection?.options?.find((o) => o.id === "effort")?.value;
}

// ── connection ──────────────────────────────────────────────────────────────
// One Effect-RPC socket multiplexes the thread stream, detail reads and commands.
export function subscribe(
  threadId,
  { onState, onConn, onValue, onCapabilities, onConfig } = {},
) {
  let state = null,
    ws,
    closed = false,
    retry = 500,
    timer,
    hold,
    server, // last seen server process identity
    notice,
    nextId = 1;
  let capabilities = {};
  const calls = new Map();
  function rejectCalls(message) {
    for (const call of calls.values()) {
      clearTimeout(call.timer);
      call.reject(new Error(message));
    }
    calls.clear();
  }
  function request(tag, payload, onChunk) {
    if (updatingUntil()) return Promise.reject(new UpdatingError());
    if (closed || ws?.readyState !== WebSocket.OPEN)
      return Promise.reject(
        new Error("T3 is not connected; retry after reconnect"),
      );
    const id = String(++nextId);
    return new Promise((resolve, reject) => {
      const call = { resolve, reject, values: [], onChunk };
      if (!onChunk)
        call.timer = setTimeout(() => {
          calls.delete(id);
          reject(new Error(`${tag}: timed out (outcome may be unknown)`));
        }, 30_000);
      calls.set(id, call);
      ws.send(
        JSON.stringify({ _tag: "Request", id, tag, payload, headers: [] }),
      );
    });
  }
  async function connect() {
    if (closed) return;
    if (updatingUntil()) {
      // Desktop update: no tickets, no upgrades, no CLI until the marker goes.
      onConn?.(UPDATING);
      hold ??= holdWhileUpdating(() => {
        hold = undefined;
        retry = 500;
        connect();
      });
      return;
    }
    try {
      onConn?.("connecting");
      const authTicket = await ticket();
      if (closed) return;
      ws = new WebSocket(
        `${BASE.replace(/^http/, "ws")}/ws?orchestrationProtocol=2&wsTicket=${encodeURIComponent(authTicket)}`,
      );
    } catch (e) {
      onConn?.(`offline: ${e.message}`);
      return later();
    }
    let healthy = false;
    ws.onopen = () => {
      if (closed) return ws.close();
      ws.send(
        JSON.stringify({
          _tag: "Request",
          id: "1",
          tag: "orchestration.subscribeThread",
          payload: {
            threadId,
            requestCompletionMarker: true,
            ...(state ? { afterSequence: state.seq } : {}),
          },
          headers: [],
        }),
      );
      request("server.getConfig", {})
        .then((config) => {
          capabilities = config?.environment?.capabilities || {};
          onCapabilities?.(capabilities);
          onConfig?.(config);
        })
        .catch((e) => debug("config unavailable", e.message));
    };
    ws.onmessage = (e) => {
      let m;
      try {
        m = JSON.parse(String(e.data));
      } catch {
        return;
      }
      if (m._tag === "Ping") return ws.send(JSON.stringify({ _tag: "Pong" }));
      if (m._tag === "Chunk") {
        ws.send(JSON.stringify({ _tag: "Ack", requestId: m.requestId }));
        if (String(m.requestId) === "1") {
          // Only a delivered stream proves the server healthy. An open socket
          // whose subscription exits at once must keep backing off.
          if (!healthy) {
            healthy = true;
            retry = 500;
            announce();
          }
          for (const v of m.values || []) {
            onValue?.(v);
            state = applyValue(state, v);
          }
          onState?.(state);
        } else {
          const call = calls.get(String(m.requestId));
          if (call)
            for (const v of m.values || []) {
              if (call.onChunk) call.onChunk(v);
              else call.values.push(v);
            }
        }
      } else if (m._tag === "Exit") {
        if (String(m.requestId) === "1") {
          onConn?.("stream ended; reconnecting");
          ws.close();
        } else {
          const call = calls.get(String(m.requestId));
          if (!call) return;
          clearTimeout(call.timer);
          calls.delete(String(m.requestId));
          if (m.exit?._tag === "Failure")
            call.reject(new Error(JSON.stringify(m.exit.cause).slice(0, 400)));
          else
            call.resolve(
              m.exit?.value ??
                (call.values.length === 1 ? call.values[0] : call.values),
            );
        }
      } else if (m._tag === "Defect") {
        rejectCalls("T3 RPC defect");
        ws.close();
      }
    };
    ws.onclose = () => {
      clearTimeout(notice);
      rejectCalls(
        "Connection lost; command outcome may be unknown (not retried)",
      );
      if (!closed) {
        onConn?.("reconnecting");
        later();
      }
    };
    ws.onerror = () => {};
  }
  // Live again: say once if a different server process now answers (update,
  // crash, manual restart), then settle on "live".
  function announce() {
    const id = serverIdentity(new URL(BASE).port || 80);
    const restarted = id && server && id.key !== server.key;
    if (id) server = id;
    if (!restarted) return onConn?.("live");
    onConn?.(`${RESTARTED} (${id.serverVersion})`);
    notice = setTimeout(() => onConn?.("live"), 5000);
  }
  function later() {
    if (closed) return;
    clearTimeout(timer);
    // Equal jitter: wait between half and all of the current step, so clients
    // dropped together do not reconnect in lockstep. Steps cap at 10 s.
    timer = setTimeout(connect, retry / 2 + Math.random() * (retry / 2));
    retry = Math.min(retry * 2, 10_000);
  }
  const close = () => {
    closed = true;
    clearTimeout(timer);
    clearTimeout(notice);
    hold?.();
    rejectCalls("Closed");
    ws?.close();
  };
  close.rpc = request;
  close.send = (text, options) =>
    request(
      "orchestration.dispatchCommand",
      messageCommand(threadId, text, options),
    );
  close.setModel = (selection) =>
    request(
      "orchestration.dispatchCommand",
      modelSelectionCommand(threadId, selection),
    );
  close.stop = () =>
    request(
      "orchestration.dispatchCommand",
      stopCommand(threadId, activeRun(state)?.id, capabilities),
    );
  close.respond = (requestId, response) =>
    request("orchestration.dispatchCommand", {
      type: "runtime-request.respond",
      commandId: crypto.randomUUID(),
      threadId,
      requestId,
      ...response,
    });
  // One provider's commands and skills as seen from `cwd` (scans the folder when stale).
  close.providerCatalog = (instanceId, cwd) =>
    request("server.refreshProviders", {
      instanceId,
      cwd,
      workspaceSnapshotsOnDemand: true,
    });
  close.getItem = (item) =>
    request("orchestration.getTurnItem", {
      threadId: item.threadId || threadId,
      itemId: item.id,
      revision: item.status === "running" ? "live" : item.updatedAt,
    });
  close.watchOutput = (itemId, onChunk, sourceThreadId = threadId) => {
    if (!capabilities.commandOutputStreaming) return () => {};
    const id = String(nextId + 1);
    request(
      "orchestration.subscribeCommandOutput",
      { threadId: sourceThreadId, itemId },
      onChunk,
    ).catch((e) => debug("output", e.message));
    return () => {
      if (ws?.readyState === WebSocket.OPEN)
        ws.send(JSON.stringify({ _tag: "Interrupt", requestId: id }));
      calls.delete(id);
    };
  };
  connect();
  return close;
}

export function messageCommand(threadId, text, { queue = false } = {}) {
  return {
    type: "message.dispatch",
    commandId: crypto.randomUUID(),
    threadId,
    messageId: crypto.randomUUID(),
    text,
    attachments: [],
    createdBy: "user",
    creationSource: "web",
    ...(queue ? {} : { deliveryIntent: "steer" }),
    dispatchMode: { type: queue ? "queue_after_active" : "start_immediately" },
  };
}
export function modelSelectionCommand(threadId, modelSelection) {
  return {
    type: "thread.model-selection.set",
    commandId: crypto.randomUUID(),
    threadId,
    modelSelection,
  };
}
export function stopCommand(threadId, runId, capabilities) {
  if (capabilities.threadStop)
    return { type: "thread.stop", commandId: crypto.randomUUID(), threadId };
  if (!runId) throw new Error("No active run to interrupt");
  return {
    type: "run.interrupt",
    commandId: crypto.randomUUID(),
    threadId,
    runId,
    holdQueue: true,
  };
}

// ── commands (CLI for now; verified) ────────────────────────────────────────
function cli(args, input) {
  return new Promise((resolve, reject) => {
    assertNotUpdating(); // the t3 CLI runs the app bundle the update is swapping
    const p = spawn(T3, args, { stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    let err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("close", (code) =>
      code === 0
        ? resolve(out)
        : reject(new Error(err.trim() || `t3 exited ${code}`)),
    );
    if (input != null) p.stdin.end(input);
    else p.stdin.end();
  });
}

export async function start(project, text, o = {}) {
  const args = ["thread", "start", project, "-", "--json"];
  if (o.provider) args.push("--provider", o.provider);
  if (o.model) args.push("--model", o.model);
  if (o.title) args.push("--title", o.title);
  return JSON.parse(await cli(args, text)).threadId;
}

export async function list(project) {
  return JSON.parse(
    await cli(["thread", "list", "--project", project, "--json"]),
  );
}
