// Append-only terminal history. Pure: no I/O, clocks, React, or theme mutation.
import * as t3 from "./t3.mjs";
import * as view from "./view.mjs";

export const ledger = () => ({ ids: new Set(), items: [] });
export function append(book, blocks, render = b => b) {
  const fresh = blocks.filter(b => !book.ids.has(b.id));
  if (!fresh.length) return book;
  return {
    ids: new Set([...book.ids, ...fresh.map(b => b.id)]),
    items: [...book.items, ...fresh.map(render)],
  };
}

export function partition(state, expanded = new Set(), now = 0) {
  const folded = view.rows(state, new Set(), now);
  const detailed = view.rows(state, expanded, now);
  const liveItem = it => it && (it.streaming || (it.type !== "user_message" && t3.isActive(state?.runs.get(it.runId))));
  const liveRun = row => t3.isActive(state?.runs.get(row.runId)) || row.kind === "working" || row.kind === "thinking" || row.kind === "preview" || row.kind === "live";
  const live = detailed.filter(row => liveRun(row) || liveItem(row.item));
  // Expand all finished summaries once, rather than walking the entire history
  // separately for every finished turn on each streaming/timer update.
  const open = view.rows(state, new Set(folded.filter(r => r.kind === "turn").map(r => r.id)), now);
  const summaries = new Map();
  let summary;
  for (const row of open) {
    if (row.kind === "turn") {
      summary = [];
      summaries.set(row.id, summary);
    } else if (["user_message", "working"].includes(row.kind)) summary = null;
    else if (summary && row.kind === "group") summary.push(row.text);
    else if (summary && ["reasoning", "command_execution", "dynamic_tool", "file_change", "file_search", "web_search", "subagent"].includes(row.kind))
      summary.push(view.summarize([row.item]));
  }
  const committed = [];
  const headed = new Set();
  for (const row of folded) {
    if (liveRun(row) || liveItem(row.item)) continue;
    const runId = row.runId || row.item?.runId;
    const run = state?.runs.get(runId);
    if (run && !t3.isActive(run) && row.kind !== "user_message" && !headed.has(runId) && row.kind !== "turn") {
      headed.add(runId);
      const ms = Date.parse(run.completedAt || run.startedAt) - Date.parse(run.startedAt || run.requestedAt);
      committed.push({ id: `turn:${runId}`, rows: [{ id: `turn:${runId}`, kind: "turn", text: `Worked for ${view.duration(Number.isFinite(ms) ? ms : 0)} · No work recorded` }] });
    }
    if (row.kind === "turn") {
      headed.add(runId);
      const work = summaries.get(row.id) || [];
      committed.push({ id: row.id, rows: [{ ...row, expandable: false, text: row.text + (work.length ? ` · ${work.join("; ")}` : "") }] });
    } else committed.push({ id: row.id, rows: [{ ...row, expandable: false }] });
  }
  return { committed, live };
}

// Explicit append, deliberately not deduplicated by the normal item ledger.
// Never replay the prompt or final answer. The caller supplies a unique block id.
export function expandedBlock(state) {
  const timeline = t3.timeline(state);
  const last = timeline.findLast(it => it.runId && !t3.isActive(state?.runs.get(it.runId)) && state?.runs.has(it.runId));
  if (!last) return null;
  const turn = view.rows(state).findLast(r => r.kind === "turn" && r.runId === last.runId);
  if (!turn) return { rows: [{ id: `expanded:${last.runId}`, kind: "system_notice", text: "Expanded work · No work recorded for the latest finished turn" }] };
  let expanded = new Set([turn.id]);
  let rows = view.rows(state, expanded);
  const start = rows.findIndex(r => r.id === turn.id);
  let end = rows.findIndex((r,i) => i > start && ["turn","working","user_message"].includes(r.kind));
  if (end < 0) end = rows.length;
  for (const row of rows.slice(start + 1,end)) if (row.expandable) expanded.add(row.id);
  rows = view.rows(state, expanded);
  const at = rows.findIndex(r => r.id === turn.id);
  const work = [];
  for (const row of rows.slice(at + 1)) {
    if (["turn","working","user_message"].includes(row.kind)) break;
    if (row.kind === "assistant_message") continue;
    work.push({ ...row, expanded: true });
  }
  return { rows: [{ ...turn, text: `Expanded work · ${turn.text}`, expanded: true, expandable: false }, ...work] };
}
