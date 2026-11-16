import { timeline, isActive, attemptId } from "./t3.mjs";

const WORK = new Set([
  "reasoning",
  "command_execution",
  "dynamic_tool",
  "file_change",
  "file_search",
  "web_search",
  "subagent",
]);
const oneLine = (value) =>
  String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();
export const duration = (ms, live = false) => {
  const seconds = Math.max(0, ms / 1000);
  if (seconds < 60)
    return `${live ? Math.floor(seconds) : Math.round(seconds * 10) / 10}s`;
  const n = Math.floor(seconds);
  return `${Math.floor(n / 60)}m ${n % 60}s`;
};
export function action(item) {
  if (item.type === "command_execution") return "command";
  if (
    item.type === "file_change" ||
    /^(edit|write|apply.?patch)$/i.test(item.toolName || "") ||
    item.toolIcon === "square-pen"
  )
    return "edit";
  if (
    /^(read|read_file|view_image)$/i.test(item.toolName || "") ||
    item.toolIcon === "eye"
  )
    return "read";
  if (item.type === "web_search") return "search";
  if (
    item.type === "file_search" ||
    /grep|glob|search/i.test(item.toolName || "")
  )
    return "code-search";
  return "other";
}
const actionLabel = (a, n) =>
  ({
    command: `Ran ${n} command${n === 1 ? "" : "s"}`,
    read: `Read ${n} file${n === 1 ? "" : "s"}`,
    edit: `Changed ${n} file${n === 1 ? "" : "s"}`,
    search: `Searched the web ${n} time${n === 1 ? "" : "s"}`,
    "code-search": `Searched code ${n} time${n === 1 ? "" : "s"}`,
    other: `Used ${n} tool${n === 1 ? "" : "s"}`,
  })[a];
export function summarize(items) {
  const tools = items.filter((i) => i.type !== "reasoning");
  if (!tools.length)
    return items.length === 1 ? "Thought" : `Thought (×${items.length})`;
  const counts = new Map();
  for (const it of tools) {
    const a = action(it);
    counts.set(a, (counts.get(a) || 0) + 1);
  }
  const groups = [...counts].map(([a, n], index) => ({
    a,
    n,
    index,
    priority: ["command", "edit"].includes(a) ? 0 : a === "other" ? 2 : 1,
  }));
  const selected = groups
    .slice()
    .sort((a, b) => a.priority - b.priority || a.index - b.index)
    .slice(0, 2)
    .sort((a, b) => a.index - b.index);
  const labels = selected.map((g) => actionLabel(g.a, g.n));
  const remaining = tools.length - selected.reduce((n, g) => n + g.n, 0);
  if (remaining)
    labels.push(
      `Performed ${remaining} other action${remaining === 1 ? "" : "s"}`,
    );
  const sentence = labels.map((l, i) =>
    i ? l[0].toLowerCase() + l.slice(1) : l,
  );
  return sentence.length < 3
    ? sentence.join(" and ")
    : `${sentence.slice(0, -1).join(", ")}, and ${sentence.at(-1)}`;
}
export function label(it) {
  switch (it.type) {
    case "reasoning":
      return oneLine(it.text) || "Thinking";
    case "command_execution":
      return oneLine(it.title || it.input) || "Ran command";
    case "dynamic_tool":
      return oneLine(it.title || it.toolName) || "Used tool";
    case "file_change":
      return it.fileName
        ? `Changed ${it.fileName}`
        : `Changed ${it.changes?.length || 1} files`;
    case "file_search":
      return "Searched files";
    case "web_search":
      return "Searched the web";
    case "assistant_message":
      return it.text || (it.streaming ? "" : "(empty response)");
    case "user_message":
      return it.text || "";
    case "approval_request":
      return "Waiting for approval";
    case "user_input_request":
      return it.questionAnswer ? "Answered questions" : "Input requested";
    case "error":
      return it.retry
        ? `Retrying provider (${it.retry.attempt}/${it.retry.maxAttempts || "…"})`
        : it.failure?.message || it.title || "Error";
    case "system_notice":
      return it.message || it.title || "Notice";
    case "notification":
      return it.summary || it.title || "Notification";
    case "todo_list":
      return `Tasks ${(it.steps || []).filter((s) => s.status === "completed").length}/${it.steps?.length || 0}`;
    case "proposed_plan":
      return it.markdown || "Plan";
    case "compaction":
      return it.summary || "Context compacted";
    case "subagent":
      return it.title || it.prompt || "Subagent";
    default:
      return it.title || it.type.replaceAll("_", " ");
  }
}
export function icon(it) {
  if (it.type === "reasoning") return "󰧑";
  if (it.type === "command_execution") return "";
  if (action(it) === "read") return "󰈈";
  if (action(it) === "edit") return "󰏫";
  if (["search", "code-search"].includes(action(it)))
    return action(it) === "search" ? "󰖟" : "󰍉";
  if (it.type === "error") return "󰅚";
  return "󰒓";
}

/** Three-level disclosure, ordered by projection; standalone notices break work groups. */
export function rows(state, expanded = new Set(), now = Date.now()) {
  const items = timeline(state),
    out = [];
  const segments = [];
  for (const it of items) {
    const previous = segments.at(-1);
    if (
      previous &&
      previous[0].runId === it.runId &&
      it.type !== "user_message"
    )
      previous.push(it);
    else segments.push([it]);
  }
  const seen = new Set();
  function itemRow(it) {
    const expandable =
      WORK.has(it.type) ||
      ["user_input_request", "approval_request"].includes(it.type);
    out.push({
      id: it.id,
      kind: it.type,
      text: label(it),
      item: it,
      expandable,
      expanded: expanded.has(it.id),
      icon: icon(it),
    });
  }
  function workRows(list, live) {
    let group = [],
      indicator = false;
    function flush(trailing = false) {
      if (!group.length) return;
      const entries = group;
      group = [];
      if (
        live &&
        (trailing ||
          entries.some((i) =>
            ["running", "pending", "waiting"].includes(i.status),
          ))
      ) {
        indicator = true;
        const reasoning = entries.findLast((i) => i.type === "reasoning");
        if (reasoning)
          out.push({
            id: `preview:${reasoning.id}`,
            kind: "preview",
            text: oneLine(reasoning.text),
            icon: "󰧑",
          });
        const tool = entries.findLast(
          (i) =>
            i.type !== "reasoning" &&
            ["running", "pending", "waiting"].includes(i.status),
        );
        if (tool) {
          const program =
            tool.type === "command_execution"
              ? oneLine(tool.input).split(" ")[0]
              : label(tool);
          out.push({
            id: tool.id,
            kind: "live",
            text: `Running ${program}`,
            item: tool,
            expandable: true,
            expanded: expanded.has(tool.id),
            icon: icon(tool),
          });
        } else
          out.push({
            id: "thinking:" + entries.at(-1).runId,
            kind: "thinking",
            text: "Thinking",
            icon: "󰧑",
          });
        return;
      }
      if (entries.length === 1) {
        itemRow(entries[0]);
        return;
      }
      const id = `group:${entries[0].id}`;
      out.push({
        id,
        kind: "group",
        runId: entries[0].runId,
        text: summarize(entries),
        expandable: true,
        expanded: expanded.has(id),
        icon: "󰒓",
      });
      if (expanded.has(id)) entries.forEach(itemRow);
    }
    for (const it of list) {
      if (WORK.has(it.type)) {
        if (group.length && attemptId(state, group[0]) !== attemptId(state, it))
          flush();
        group.push(it);
      } else {
        flush();
        itemRow(it);
      }
    }
    flush(true);
    if (live && !indicator)
      out.push({
        id: "thinking",
        kind: "thinking",
        text: "Thinking",
        icon: "󰧑",
      });
  }
  for (const list of segments) {
    const it = list[0];
    if (!it.runId) {
      list.forEach(itemRow);
      continue;
    }
    const continuation = seen.has(it.runId);
    seen.add(it.runId);
    const run = state.runs.get(it.runId),
      live = isActive(run);
    const prompts = list.filter((i) => i.type === "user_message");
    prompts.forEach(itemRow);
    const rest = list.filter((i) => i.type !== "user_message");
    const ms =
      Date.parse((!live && run?.completedAt) || new Date(now).toISOString()) -
      Date.parse(
        run?.startedAt || run?.requestedAt || new Date(now).toISOString(),
      );
    const id = `turn:${it.runId}${continuation ? ":" + it.id : ""}`;
    if (live) {
      out.push({
        id,
        kind: "working",
        runId: it.runId,
        text: `Working for ${duration(ms, true)}`,
        icon: "",
      });
      workRows(rest, true);
    } else {
      const final = rest.findLast(
        (i) => i.type === "assistant_message" && i.phase !== "commentary",
      );
      const keep = rest.filter(
        (i) =>
          i === final ||
          [
            "notification",
            "compaction",
            "error",
            "approval_request",
            "user_input_request",
          ].includes(i.type),
      );
      const work = rest.filter((i) => !keep.includes(i));
      if (work.length)
        out.push({
          id,
          kind: "turn",
          runId: it.runId,
          text: `${run?.status === "interrupted" ? "You stopped after" : "Worked for"} ${duration(ms)}`,
          expandable: true,
          expanded: expanded.has(id),
          startedAt: run?.startedAt || run?.requestedAt,
        });
      if (expanded.has(id)) workRows(work, false);
      keep.forEach(itemRow);
    }
  }
  return out;
}

// A single last-kill slot, shared by composer edits for this client process.
// Empty kills and ordinary deletion never replace it; no kill-ring coalescing.
let lastKill = "";
const previousCharacter = (value, cursor) =>
  cursor - ([...value.slice(0, cursor)].at(-1)?.length ?? 0);
const nextCharacter = (value, cursor) =>
  cursor + (value.codePointAt(cursor) > 0xffff ? 2 : cursor < value.length ? 1 : 0);

/** Own editing here; main owns submit, menus, interrupt and work expansion.
 * Cursor offsets remain UTF-16 for string slicing, motions respect code points.
 * Word kills use readline whitespace words; Alt motions use letter/number words.
 */
export function editInput(value, cursor, ch, key) {
  const unchanged = { value, cursor };
  const move = (to) => ({ value, cursor: to });
  const remove = (start, end, kill = false) => {
    if (kill && end > start) lastKill = value.slice(start, end);
    return { value: value.slice(0, start) + value.slice(end), cursor: start };
  };
  const insert = (text) => ({
    value: value.slice(0, cursor) + text + value.slice(cursor),
    cursor: cursor + text.length,
  });
  const lineStart = cursor > 0 ? value.lastIndexOf("\n", cursor - 1) + 1 : 0;
  const nextNewline = value.indexOf("\n", cursor);
  const lineEnd = nextNewline < 0 ? value.length : nextNewline;
  const wordBack = () => {
    const prefix = value.slice(lineStart, cursor);
    return cursor - (prefix.match(/\S*\s*$/u)?.[0].length ?? 0);
  };
  if (key.meta) {
    if (key.backspace || key.delete) return remove(wordBack(), cursor, true);
    if (ch === "b") {
      const prefix = value.slice(lineStart, cursor);
      const word = prefix.match(/[\p{L}\p{N}]+[^\p{L}\p{N}]*$|[^\p{L}\p{N}]+$/u)?.[0] ?? "";
      return move(cursor - word.length);
    }
    if (ch === "f") {
      const suffix = value.slice(cursor, lineEnd);
      const word = suffix.match(/^[^\p{L}\p{N}]*[\p{L}\p{N}]+|^[^\p{L}\p{N}]+/u)?.[0] ?? "";
      return move(cursor + word.length);
    }
    return unchanged;
  }
  if (key.ctrl) {
    switch (ch) {
      case "a": return move(lineStart);
      case "e": return move(lineEnd);
      case "b": return move(previousCharacter(value, cursor));
      case "f": return move(nextCharacter(value, cursor));
      case "u":
        return remove(cursor === lineStart ? Math.max(0, cursor - 1) : lineStart, cursor, true);
      case "k":
        return remove(cursor, cursor === lineEnd ? Math.min(value.length, cursor + 1) : lineEnd, true);
      case "w": return remove(wordBack(), cursor, true);
      case "d": return remove(cursor, nextCharacter(value, cursor));
      case "h": return remove(previousCharacter(value, cursor), cursor);
      case "y": return insert(lastKill);
      // In particular Ctrl-C/O/Q remain main's, Ctrl-P/N outside menus no-op.
      default: return unchanged;
    }
  }
  if (
    key.escape ||
    key.tab ||
    key.return ||
    key.pageUp ||
    key.pageDown ||
    key.upArrow ||
    key.downArrow
  )
    return unchanged;
  if (key.leftArrow) return move(previousCharacter(value, cursor));
  if (key.rightArrow) return move(nextCharacter(value, cursor));
  if (key.home) return move(0);
  if (key.end) return move(value.length);
  // Ink 5 calls both DEL (0x7f) and forward Delete "delete"; keep its existing
  // backward behavior. Ctrl-D is the unambiguous forward-delete binding.
  if (key.backspace || key.delete)
    return remove(previousCharacter(value, cursor), cursor);
  // Enter is owned by submit; a pasted multi-line chunk keeps its line breaks.
  const text = ch
    .replace(/\r\n?/g, "\n")
    .replace(/[\x00-\x09\x0b-\x1f\x7f]/g, "");
  return insert(text);
}

export function answerInput(question, text) {
  const options = question.options || [];
  const parts = text.split(",").map((value) => value.trim());
  const selected = parts.map((part) =>
    /^\d+$/.test(part) ? options[Number(part) - 1] : undefined,
  );
  if (selected.every(Boolean)) {
    if (!question.multiSelect && selected.length !== 1)
      return { error: "Choose one option." };
    const values = selected.map((option) => option.value ?? option.label);
    return { answer: question.multiSelect ? values : values[0] };
  }
  if (question.allowCustomAnswer === false)
    return { error: "Choose a numbered option." };
  return { answer: text };
}
