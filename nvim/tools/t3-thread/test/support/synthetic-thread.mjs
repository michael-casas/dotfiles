// Synthetic T3 thread projections for terminal-rendering tests. No real thread
// data: every id, title, prompt and answer here is invented.
export const THREAD_ID = "synthetic-strike";
export const HISTORY_RUNS = 8;
export const historyMarker = (i) => `HISTORY_${i}`;
const at = (s) => new Date(Date.UTC(2026, 0, 1, 0, 0, s)).toISOString();

function finishedRun(i) {
  const runId = `run-${i}`;
  return {
    run: { id: runId, ordinal: i + 1, status: "completed", startedAt: at(i * 4), completedAt: at(i * 4 + 2) },
    items: [
      { id: `u-${i}`, threadId: THREAD_ID, runId, ordinal: 1, type: "user_message", status: "completed", text: `Synthetic prompt ${i}` },
      {
        id: `a-${i}`,
        threadId: THREAD_ID,
        runId,
        ordinal: 2,
        type: "assistant_message",
        status: "completed",
        text: `${historyMarker(i)} plain row\n\n\`\`\`js\nlet x = ${i};\n\`\`\`\n\nlast row ${i}`,
      },
    ],
  };
}

/**
 * A snapshot with HISTORY_RUNS finished runs (plus `extra` newer finished runs)
 * and optionally one running run whose assistant message is still streaming.
 */
export function snapshot({ seq = 1, stream = null, extra = 0, startedAt = new Date().toISOString() } = {}) {
  const runs = [];
  const items = [];
  for (let i = 0; i < HISTORY_RUNS + extra; i++) {
    const r = finishedRun(i);
    runs.push(r.run);
    items.push(...r.items);
  }
  if (stream !== null) {
    const runId = "run-live";
    runs.push({ id: runId, ordinal: runs.length + 1, status: "running", startedAt, completedAt: null });
    items.push(
      { id: "u-live", threadId: THREAD_ID, runId, ordinal: 1, type: "user_message", status: "completed", text: "Synthetic live prompt" },
      { id: "a-live", threadId: THREAD_ID, runId, ordinal: 2, type: "assistant_message", status: "running", streaming: true, text: stream },
    );
  }
  return {
    kind: "snapshot",
    snapshotSequence: seq,
    projection: {
      thread: { id: THREAD_ID, title: "Synthetic strike thread", model: "test-model" },
      runs,
      turnItems: items,
      visibleTurnItems: items.map((item, position) => ({ item, position })),
    },
  };
}

/** A long stream: more rows than any test terminal, so the live region is capped. */
export const longStream = (i) => "STREAM line\n".repeat(80) + `chunk ${i}`;
