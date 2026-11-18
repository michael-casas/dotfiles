#!/usr/bin/env node
// Read-only orchestration-v2 shell → envi sidebar NDJSON. No prompt bodies,
// tokens, RPC error causes, or arbitrary transport errors are written to stdout.
import path from "node:path";
import { pathToFileURL } from "node:url";
import { openShellSocket } from "./t3.mjs";
import { UPDATING, holdWhileUpdating, onUpdateStart, updatingUntil } from "./update.mjs";

const active = new Set(["queued", "preparing", "starting", "running", "waiting"]);
const terminal = new Set(["completed", "failed", "interrupted", "cancelled", "rolled_back"]);
const holdsCompletion = (t) => (t.pendingBackgroundTasks || []).some(
  task => task.awaited === true || ["subagent", "background_task"].includes(task.kind),
);
const completedAt = (t) => t.latestRunCompletedAt === undefined
  ? (terminal.has(t.status) || t.status === "idle" ? t.updatedAt : null)
  : t.latestRunCompletedAt;

// Desktop hasUnseenCompletion: no visit watermark means no unread badge;
// malformed visit with a valid completion is unread. Ignore metadata updatedAt
// unless an older server omits latestRunCompletedAt (presentThreadShell fallback).
export function feedUnread(t) {
  const end = Date.parse(completedAt(t));
  return !!t.latestRunId && Number.isFinite(end) && !!t.lastVisitedAt &&
    (!Number.isFinite(Date.parse(t.lastVisitedAt)) || end > Date.parse(t.lastVisitedAt));
}

/**
 * Source: contracts/orchestrationV2.ts ThreadShell; client-runtime/state/models.ts
 * shellRuntime; web/components/Sidebar.logic.ts resolveSidebarRowStatus +
 * hasUnseenCompletion. Collapses the desktop's richer markers into five states:
 * - attention: approval/input (including async), guest request, usage limit, plan ready;
 * - working: preparing/queued/starting/running/waiting, using activityRunStatus;
 * - idle: thread-wait/background-held completion, seen/settled/no completion;
 * - done: completed (legacy idle) latest run with an unseen completion, not settled;
 * - error: failed latest run or an interruption with lastError/Class/Code.
 * Intentional contract differences: failed stays error even when visited (desktop
 * clears it); clean interrupts/cancel/rollback aren't successful done completions.
 * Ordinary subagent questions belong to their coordinator; approvals and user-only
 * cards roll up to ancestors. Linked-environment delegations are not in this shell.
 */
export function feedStatus(t, inheritedAttention = false) {
  if ((t.pendingRuntimeRequest && t.pendingRuntimeRequest.kind !== "auth_refresh") ||
      inheritedAttention || (t.pendingGuestMessageCount || 0) > 0) return "attention";
  const runtime = holdsCompletion(t) && t.status !== "failed"
    ? "idle" : t.activityRunStatus ?? t.status;
  if (runtime === "failed" && t.lastErrorClass === "usage_limit") return "attention";
  if (runtime === "running" && t.blockedOnThreadWait) return "idle";
  if (active.has(runtime)) return "working";
  if (t.status === "failed" || (t.status === "interrupted" &&
      (t.lastError || t.lastErrorClass || t.lastErrorCode))) return "error";
  if (holdsCompletion(t)) return "idle";
  if (t.interactionMode === "plan" && t.hasActionableProposedPlan &&
      t.latestRunId && (terminal.has(t.status) || t.status === "idle")) return "attention";
  if (t.settledOverride !== "settled" && ["completed", "idle"].includes(t.status) && feedUnread(t)) return "done";
  return "idle";
}

function attentionAncestors(threads) {
  const byId = new Map(threads.map(t => [t.id, t]));
  const flagged = new Set();
  for (const child of threads) {
    const request = child.pendingRuntimeRequest;
    if (!request || request.kind === "auth_refresh") continue;
    const lineage = child.lineage;
    if (lineage?.relationshipToParent !== "subagent" && !lineage?.sideChat) continue;
    if (!lineage.sideChat) {
      const live = child.activityRunStatus !== undefined
        ? child.activityRunStatus !== null
        : ["preparing", "starting", "running", "waiting"].includes(child.status);
      if (child.creationSource === "provider" || !live) continue;
    }
    if (request.kind === "user_input" && !request.userOnly && !lineage.sideChat) continue;
    const seen = new Set([child.id]);
    let id = lineage.parentThreadId;
    while (id && !seen.has(id)) {
      seen.add(id); flagged.add(id);
      const parent = byId.get(id);
      id = parent?.lineage?.relationshipToParent === "subagent" || parent?.lineage?.sideChat
        ? parent.lineage.parentThreadId : null;
    }
  }
  return flagged;
}

// Exact isListedThreadLineage rule, contracts/orchestrationV2.ts:175-177.
// A parentId alone does not hide forks; sideChat hides any relationship.
const listedLineage = t =>
  t.lineage?.relationshipToParent !== "subagent" && t.lineage?.sideChat !== true;

// Desktop filters lineage before partitioning, then snoozed > settled > pinned:
// contracts/orchestrationV2.ts:175-177; web/Sidebar.logic.ts:195-203,613-632;
// web/Sidebar.tsx:627,665-669. This flag is pinned-shelf membership, not the
// raw pin inherited by subagent shells. Forks stay independently listed.
// Local-only feed cannot reproduce delegatedUnderParent across linked servers
// (client-runtime/state/threadShell.ts:678-700); never hide an orphan task just
// because delegatedFrom exists.
function sidebarPinned(t, inheritedAttention, now) {
  if (!t.pinnedAt || t.archivedAt || t.settledOverride === "settled" || !listedLineage(t)) return false;
  if (!(Date.parse(t.snoozedUntil) > Date.parse(now))) return true;

  // effectiveSnoozed/threadRaisedHandWhileSnoozed, threadSettled.ts:94-132,156-165.
  // New questions, approvals, guest/child requests and fresh failures wake early;
  // completing normally never wakes a snooze.
  const request = t.pendingRuntimeRequest;
  if (request && request.kind !== "user_input") return true;
  if (request?.kind === "user_input" && (!t.snoozedAt || !request.createdAt ||
      !(Date.parse(request.createdAt) <= Date.parse(t.snoozedAt)))) return true;
  if (inheritedAttention || (t.pendingGuestMessageCount || 0) > 0) return true;
  const runtime = holdsCompletion(t) && t.status !== "failed"
    ? "idle" : t.activityRunStatus ?? t.status;
  if (runtime === "failed") {
    const failedAt = t.latestRunId && t.status === "failed"
      ? completedAt(t) : t.updatedAt;
    if (!t.snoozedAt || (failedAt && Date.parse(failedAt) > Date.parse(t.snoozedAt))) return true;
  }
  return false;
}

export function feedSnapshot(shell, options = {}, at = new Date().toISOString()) {
  const projects = (shell.projects || [])
    .filter(p => !options.project || path.resolve(p.workspaceRoot) === path.resolve(options.project))
    .map(p => ({ id: p.id, name: p.title, cwd: p.workspaceRoot }));
  const projectIds = new Set(projects.map(p => p.id));
  const rows = [...(shell.threads || []), ...(shell.archivedThreads || [])].filter(t => !t.deletedAt);
  const attention = attentionAncestors(rows.filter(t => !t.archivedAt));
  const threads = rows
    .filter(t => (options.archived || !t.archivedAt) && (!options.project || projectIds.has(t.projectId)))
    .map(t => ({
      id: t.id, projectId: t.projectId, title: t.title,
      status: feedStatus(t, attention.has(t.id)), updatedAt: t.updatedAt,
      pinned: sidebarPinned(t, attention.has(t.id), at), unread: feedUnread(t), archived: !!t.archivedAt,
      settled: t.settledOverride === "settled", parentId: t.lineage?.parentThreadId ?? null,
      listed: listedLineage(t), relationship: t.lineage?.relationshipToParent ?? null,
      model: t.modelSelection?.model ?? null,
      // contracts/modelSelection.ts:9-12; orchestrationV2.ts:2198-2199.
      // Instance identity is independent of the model (e.g. GPT on pi/codex).
      harness: t.modelSelection?.instanceId ?? t.providerInstanceId ?? null,
      branch: t.branch ?? null,
      worktreePath: t.worktreePath ?? null,
    }));
  return { type: "snapshot", at, projects, threads };
}

function upsert(rows, row) {
  return rows.some(previous => previous.id === row.id)
    ? rows.map(previous => previous.id === row.id ? row : previous)
    : [...rows, row];
}

function validateThread(t) {
  if (!t || ![t.id, t.projectId, t.title, t.updatedAt].every(v => typeof v === "string"))
    throw new Error("Invalid shell thread");
}
function validateProject(p) {
  if (!p || ![p.id, p.title, p.workspaceRoot].every(v => typeof v === "string"))
    throw new Error("Invalid shell project");
}

export function applyShellValue(state, value) {
  if (value.kind === "snapshot") {
    const s = value.snapshot;
    if (!s || !Number.isFinite(s.snapshotSequence) ||
        ![s.projects, s.threads, s.archivedThreads].every(Array.isArray))
      throw new Error("Invalid shell snapshot");
    s.projects.forEach(validateProject);
    s.threads.forEach(validateThread); s.archivedThreads.forEach(validateThread);
    // Enrichment snapshots contain only identity-refreshed projects and empty
    // thread arrays, not an authoritative replacement (ShellStream.ts:693).
    if (state && value.resolvedRepositoryIdentityRoots !== undefined) {
      const projects = new Map(value.snapshot.projects.map(p => [p.id, p]));
      return { ...state, projects: state.projects.map(p => projects.has(p.id)
        ? { ...p, repositoryIdentity: projects.get(p.id).repositoryIdentity } : p) };
    }
    return value.snapshot;
  }
  if (!state || !Number.isFinite(value.sequence) || value.sequence <= state.snapshotSequence) return state;
  const next = { ...state, snapshotSequence: value.sequence };
  if (value.kind === "project.updated") {
    validateProject(value.project);
    next.projects = upsert(state.projects, value.project);
  }
  else if (value.kind === "project.removed")
    next.projects = state.projects.filter(p => p.id !== value.projectId);
  else if (value.kind === "thread.updated") {
    validateThread(value.thread);
    next.threads = state.threads.filter(t => t.id !== value.thread.id);
    next.archivedThreads = state.archivedThreads.filter(t => t.id !== value.thread.id);
    const key = value.location === "archive" ? "archivedThreads" : "threads";
    next[key] = upsert(state[key], value.thread);
  } else if (value.kind === "thread.removed") {
    // Only remove from its named collection: archive/unarchive can send the
    // destination upsert before the source removal.
    const key = value.location === "archive" ? "archivedThreads" : "threads";
    next[key] = state[key].filter(t => t.id !== value.threadId);
  }
  return next;
}

export function parseArgs(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--once") options.once = true;
    else if (args[i] === "--archived") options.archived = true;
    else if (args[i] === "--project" && args[i + 1] && !args[i + 1].startsWith("--")) options.project = args[++i];
    else throw new Error("Usage: threads.mjs [--project <cwd>] [--once] [--archived]");
  }
  return options;
}

// Injectable transport/clock keep outage, throttling and lifecycle tests pure.
export function startFeed(options = {}, {
  openSocket = openShellSocket,
  write = line => process.stdout.write(line),
  clock = { now: Date.now, setTimeout, clearTimeout },
} = {}) {
  let state = null, socket, stopped = false, generation = 0, retry = 500, shellReady = false;
  let retryTimer, deadline, emitTimer, lastEmission = -Infinity, signature = null;
  let archiveTimer, archiveDeadline, archiveRequest, archiveValues = [], archiveRows = [];
  let archiveReady = !options.archived, archiveDirty = false, nextRequest = 1;
  let finish, hold, attempt; // attempt: AbortController of the connection in flight
  const done = new Promise(resolve => { finish = resolve; });
  const emit = value => write(`${JSON.stringify(value)}\n`);
  const clear = id => { if (id !== undefined) clock.clearTimeout(id); };
  const close = (code = 0) => {
    if (stopped) return;
    stopped = true; generation++;
    clear(retryTimer); clear(deadline); clear(emitTimer);
    clear(archiveTimer); clear(archiveDeadline); hold?.(); unwatch();
    attempt?.abort(); socket?.close(); finish(code);
  };
  function publish() {
    emitTimer = undefined;
    if (stopped || !state || !shellReady || !archiveReady) return;
    const snapshot = feedSnapshot(state, options, new Date(clock.now()).toISOString());
    // `at` is emitted time, not data; sequence-only or hidden-field changes do
    // not repaint Lua. Sort only for equality, preserving server order in output.
    const key = JSON.stringify({
      projects: [...snapshot.projects].sort((a, b) => a.id.localeCompare(b.id)),
      threads: [...snapshot.threads].sort((a, b) => a.id.localeCompare(b.id)),
    });
    if (signature === key) return;
    signature = key; lastEmission = clock.now(); emit(snapshot);
    if (options.once) close();
  }
  function changed() {
    if (options.once) return publish();
    if (emitTimer !== undefined) return;
    emitTimer = clock.setTimeout(publish, Math.max(0, 250 - (clock.now() - lastEmission)));
  }
  function loadArchive(ws, gen) {
    archiveTimer = undefined;
    if (stopped || gen !== generation) return;
    if (archiveRequest) { archiveDirty = true; return; }
    archiveReady = false; archiveDirty = false; archiveValues = [];
    archiveRequest = String(++nextRequest);
    ws.send(JSON.stringify({ _tag: "Request", id: archiveRequest,
      tag: "orchestration.getArchivedShellSnapshot", payload: {}, headers: [] }));
    archiveDeadline = clock.setTimeout(() => fail(gen, "T3 archive timed out; reconnecting"), 10000);
  }
  function refreshArchive(ws, gen) {
    archiveReady = false;
    if (archiveRequest) { archiveDirty = true; return; }
    if (archiveTimer === undefined) archiveTimer = clock.setTimeout(() => loadArchive(ws, gen), 250);
  }
  function fail(gen, message) {
    if (stopped || gen !== generation) return;
    generation++;
    clear(deadline); clear(emitTimer); emitTimer = undefined;
    clear(archiveTimer); clear(archiveDeadline); archiveTimer = undefined;
    archiveRequest = undefined; archiveReady = !options.archived; shellReady = false;
    signature = null; // recovery gets a snapshot even if the rows are unchanged
    attempt?.abort(); attempt = undefined; // cancel a ticket or handshake in flight
    socket?.close(); socket = undefined; // released at once, whatever the peer does
    if (updatingUntil()) return void connect(); // hold, no retry
    emit({ type: "error", message });
    if (options.once) return close(1);
    retryTimer = clock.setTimeout(connect, retry);
    retry = Math.min(10000, retry * 2);
  }
  async function connect() {
    if (stopped) return;
    if (updatingUntil()) {
      // Desktop update: hold without load; resume as soon as the marker goes.
      emit({ type: "error", message: UPDATING });
      if (options.once) return close(1);
      hold ??= holdWhileUpdating(() => { hold = undefined; retry = 500; connect(); });
      return;
    }
    const gen = ++generation;
    const lost = () => fail(gen, "T3 shell connection lost; reconnecting");
    clear(deadline);
    deadline = clock.setTimeout(() => fail(gen, "T3 shell connection timed out; reconnecting"), 10000);
    let ws;
    const controller = (attempt = new AbortController());
    try { ws = await openSocket(controller.signal); }
    catch { return fail(gen, "T3 shell unavailable; reconnecting"); }
    if (stopped || gen !== generation) { ws.close(); return; }
    socket = ws;
    ws.onopen = () => {
      if (stopped || gen !== generation) return ws.close();
      if (updatingUntil()) return fail(gen, UPDATING); // marker published mid-handshake: hold, no RPC
      ws.send(JSON.stringify({
        _tag: "Request", id: "1", tag: "orchestration.subscribeShell",
        payload: { requestCompletionMarker: true, ...(state ? { afterSequence: state.snapshotSequence } : {}) },
        headers: [],
      }));
      if (options.archived) loadArchive(ws, gen);
    };
    ws.onmessage = event => {
      if (stopped || gen !== generation) return;
      try {
        const frame = JSON.parse(String(event.data));
        if (frame._tag === "Ping") { ws.send(JSON.stringify({ _tag: "Pong" })); return; }
        if (frame._tag === "Defect" || (frame._tag === "Exit" && String(frame.requestId) === "1")) return lost();
        if (archiveRequest && String(frame.requestId) === archiveRequest) {
          if (frame._tag === "Chunk") {
            ws.send(JSON.stringify({ _tag: "Ack", requestId: frame.requestId }));
            archiveValues.push(...(frame.values || []));
          } else if (frame._tag === "Exit") {
            if (frame.exit?._tag !== "Success") return fail(gen, "T3 archive unavailable; reconnecting");
            const result = frame.exit.value ?? archiveValues[0];
            if (!Array.isArray(result?.threads)) return fail(gen, "T3 archive invalid response; reconnecting");
            result.threads.forEach(validateThread);
            archiveRows = result.threads;
            clear(archiveDeadline); archiveRequest = undefined; archiveReady = true;
            if (state) state = { ...state, archivedThreads: archiveRows };
            if (archiveDirty) refreshArchive(ws, gen);
            else if (state) changed();
          }
          return;
        }
        if (frame._tag !== "Chunk" || String(frame.requestId) !== "1") return;
        ws.send(JSON.stringify({ _tag: "Ack", requestId: frame.requestId }));
        for (const value of frame.values || []) {
          if (value.kind === "snapshot-required") {
            state = null;
            return fail(gen, "T3 shell snapshot required; reconnecting");
          }
          state = applyShellValue(state, value);
          if (options.archived && state) {
            if (value.kind === "snapshot") state = { ...state, archivedThreads: archiveRows };
            // Current shell emits only removals for archive-side changes; its
            // archivedThreads is always empty. Invalidate the separate query,
            // just like desktop's archivedShellSnapshot refreshTrigger.
            if (value.kind === "thread.removed" || value.kind === "project.removed" ||
                (value.kind === "thread.updated" && (value.location === "archive" || archiveRows.some(t => t.id === value.thread.id))))
              refreshArchive(ws, gen);
          }
          if (state) {
            shellReady = true;
            clear(deadline); retry = 500;
            changed();
            if (stopped) return;
          }
        }
      } catch { fail(gen, "T3 shell invalid response; reconnecting"); }
    };
    ws.onerror = lost;
    ws.onclose = lost;
  }
  // A6: on an update, close the socket at once (a stopping server waits on it).
  const unwatch = onUpdateStart(() => {
    if (stopped || hold) return;
    clear(retryTimer); fail(generation, UPDATING);
  });
  void connect();
  return { close, done };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  let feed;
  try {
    feed = startFeed(parseArgs(process.argv.slice(2)));
    const stop = () => feed.close();
    process.once("SIGINT", stop); process.once("SIGTERM", stop);
    // A piped reader (e.g. head) can finish first. It is not a server failure.
    process.stdout.on("error", error => {
      if (error.code === "EPIPE") stop();
      else feed.close(1);
    });
    process.exitCode = await feed.done;
    process.removeListener("SIGINT", stop); process.removeListener("SIGTERM", stop);
  } catch {
    process.stdout.write(`${JSON.stringify({ type: "error", message: "Usage: threads.mjs [--project <cwd>] [--once] [--archived]" })}\n`);
    process.exitCode = 1;
  }
}
