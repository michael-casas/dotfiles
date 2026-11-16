import path from "node:path";
import os from "node:os";
import * as t3 from "./t3.mjs";
import * as view from "./view.mjs";
import { partition } from "./scrollback.mjs";
import * as questionUI from "./question.mjs";

// Every display line is an array of styled segments. Keep styling before wrapping:
// a bold/code/link span may cross any number of physical terminal rows.
export const safe = (value) =>
  String(value ?? "")
    .replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
const graphemes = (s) => [...segmenter.segment(s)].map((g) => g.segment);
const wide = (n) =>
  n >= 0x1100 &&
  (n <= 0x115f ||
    n === 0x2329 ||
    n === 0x232a ||
    (n >= 0x2e80 && n <= 0xa4cf && n !== 0x303f) ||
    (n >= 0xac00 && n <= 0xd7a3) ||
    (n >= 0xf900 && n <= 0xfaff) ||
    (n >= 0xfe10 && n <= 0xfe19) ||
    (n >= 0xfe30 && n <= 0xfe6f) ||
    (n >= 0xff00 && n <= 0xff60) ||
    (n >= 0xffe0 && n <= 0xffe6) ||
    (n >= 0x1f000 && n <= 0x1faff) ||
    (n >= 0x20000 && n <= 0x3fffd));
function cellWidth(g) {
  if (/^[\p{Mark}\u200d\ufe0f]+$/u.test(g)) return 0;
  // Match Ink's emoji measurement even for text-default symbols (✳, ↪).
  if (
    g.includes("\ufe0f") ||
    g.includes("\u20e3") ||
    (g.codePointAt(0) > 0x7f && /\p{Emoji}/u.test(g))
  )
    return 2;
  return wide(g.codePointAt(0)) ? 2 : 1;
}
export const displayWidth = (s) =>
  graphemes(safe(s)).reduce((n, g) => n + cellWidth(g), 0);
export const lineText = (line) => line.map((s) => s.text).join("");
// Ink 5 measures BMP emoji as two cells, but its output tokenizer emits one.
// Apply AFTER Yoga measurement so coloured surfaces retain their last cell.
export const inkText = (text) =>
  text.replace(/[^\x00-\x7f]/gu, (g) =>
    g.length === 1 && cellWidth(g) === 2 && !wide(g.codePointAt(0))
      ? g + " "
      : g,
  );
const seg = (text, props = {}) => ({ text: safe(text), ...props });
const space = (n) => seg(" ".repeat(Math.max(0, n)));
function glyphs(spans) {
  return spans.flatMap(({ text, ...props }) =>
    graphemes(safe(text)).map((g) => ({ text: g, ...props })),
  );
}
function compact(spans) {
  const out = [];
  for (const s of spans) {
    const p = out.at(-1);
    if (
      p &&
      [
        "color",
        "bg",
        "bold",
        "underline",
        "inverse",
        "chip",
        "chipPadding",
      ].every((k) => p[k] === s[k])
    )
      p.text += s.text;
    else out.push({ ...s });
  }
  return out;
}
export function clip(spans, width, ellipsis = false) {
  if (displayWidth(lineText(spans)) <= width) return spans;
  const out = [];
  let used = 0;
  for (const s of glyphs(spans)) {
    const w = cellWidth(s.text);
    if (used + w > Math.max(0, width - (ellipsis ? 1 : 0))) break;
    out.push(s);
    used += w;
  }
  if (ellipsis && width > 0) out.push({ ...out.at(-1), text: "…" });
  return compact(out);
}
const pad = (line, width) => [
  ...line,
  space(width - displayWidth(lineText(line))),
];
export function wrapSegments(
  spans,
  width,
  { first = "", rest = first, tokenBreaks = false } = {},
) {
  width = Math.max(1, width);
  const out = [];
  let pending = glyphs(spans),
    prefix = first;
  while (pending.length) {
    while (pending[0]?.chipPadding) pending.shift();
    if (!pending.length) break;
    const room = Math.max(1, width - displayWidth(prefix));
    if (pending[0]?.chip != null) {
      const chip = pending[0].chip;
      const end = pending.findIndex((s) => s.chip !== chip);
      const length = end < 0 ? pending.length : end;
      const unit = pending.slice(0, length);
      if (displayWidth(lineText(unit)) > room)
        pending = [
          ...unit.filter((s) => !s.chipPadding),
          ...pending.slice(length),
        ];
    }
    let used = 0,
      end = 0,
      lastSpace = -1;
    while (end < pending.length && pending[end].text !== "\n") {
      const w = cellWidth(pending[end].text);
      if (used + w > room) break;
      if (
        /^\s$/.test(pending[end].text) &&
        pending[end].chip == null &&
        !pending[end].inverse
      )
        lastSpace = end;
      used += w;
      end++;
    }
    const hardBreak = pending[end]?.text === "\n";
    let cut = end;
    if (!hardBreak && end < pending.length && lastSpace > 0) cut = lastSpace;
    if (tokenBreaks && !hardBreak && end < pending.length && lastSpace < 1) {
      // Preserve recognisable path components; only sacrifice the last third.
      let cells = 0,
        delimiter = -1;
      for (let i = 0; i < end; i++) {
        cells += cellWidth(pending[i].text);
        if (
          cells >= Math.ceil((room * 2) / 3) &&
          /[/._-]/.test(pending[i].text)
        )
          delimiter = i;
      }
      if (delimiter >= 0) cut = delimiter + 1;
    }
    if (cut === 0 && !hardBreak) cut = Math.max(end, 1);
    // A code chip and directly following punctuation form one break unit.
    const crossing = pending[cut]?.chip;
    if (crossing != null && pending[cut - 1]?.chip === crossing) {
      let start = cut - 1;
      while (start > 0 && pending[start - 1].chip === crossing) start--;
      if (start > 0) cut = start;
      else {
        // An overlong chip may wrap, but punctuation still belongs to its tail.
        while (cut > 1 && /^[,.;:)]$/.test(pending[cut]?.text)) cut--;
      }
    }
    const line = pending.slice(0, cut);
    while (line[0]?.chipPadding) line.shift();
    while (
      line.at(-1)?.chipPadding ||
      (line.at(-1)?.text === " " &&
        line.at(-1)?.chip == null &&
        !line.at(-1)?.inverse)
    )
      line.pop();
    out.push(compact([seg(prefix), ...line]));
    pending = pending.slice(cut);
    if (hardBreak) pending = pending.slice(1);
    else
      while (
        (pending[0]?.text === " " && !pending[0]?.inverse) ||
        pending[0]?.chipPadding
      )
        pending.shift();
    prefix = rest;
    if (hardBreak && !pending.length) out.push([seg(prefix)]);
  }
  return out.length ? out : [first ? [seg(first)] : []];
}

export function inline(text, T, base = {}) {
  text = safe(text);
  const out = [],
    pattern = /\*\*([^*]+)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)/g;
  let at = 0;
  let m;
  while ((m = pattern.exec(text))) {
    if (m.index > at)
      out.push(seg(text.slice(at, m.index), { color: T.fg, ...base }));
    if (m[1]) out.push(...inline(m[1], T, { ...base, bold: true }));
    else if (m[2]) {
      const chip = m.index;
      const props = { color: T.fg, ...base, bg: T.code_bg, chip };
      out.push(
        seg(" ", { ...props, chipPadding: true }),
        seg(m[2], props),
        seg(" ", { ...props, chipPadding: true }),
      );
      // Consume punctuation with the chip; it must never open the next line.
      const punctuation =
        text.slice(m.index + m[0].length).match(/^[,.;:)]+/)?.[0] || "";
      if (punctuation) {
        out.push(seg(punctuation, { color: T.fg, ...base, chip }));
        pattern.lastIndex = m.index + m[0].length + punctuation.length;
      }
    } else out.push(seg(m[3], { color: T.link, ...base, underline: true }));
    at = pattern.lastIndex;
  }
  if (at < text.length) out.push(seg(text.slice(at), { color: T.fg, ...base }));
  return out;
}
const tableCells = (s) =>
  s
    .trim()
    .replace(/^\||\|$/g, "")
    .split("|")
    .map((s) => s.trim());
const tableRule = (s) =>
  /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(s);
function table(block, width, T) {
  const cells = block.filter((s) => !tableRule(s)).map(tableCells);
  const count = Math.max(...cells.map((r) => r.length));
  // Very wide schemas are rendered in column bands instead of dropping cells.
  const bandSize = Math.max(1, Math.floor((width + 3) / 11));
  const out = [];
  for (let offset = 0; offset < count; offset += bandSize) {
    const columns = Math.min(bandSize, count - offset);
    const available = width - 3 * (columns - 1);
    const widths = Array.from({ length: columns }, (_, c) =>
      Math.max(
        8,
        ...cells.map((r) =>
          displayWidth(lineText(inline(r[offset + c] || "", T))),
        ),
      ),
    );
    if (columns > 1) widths[0] = Math.min(widths[0], Math.floor(width / 2));
    else widths[0] = Math.min(widths[0], width);
    while (widths.reduce((a, b) => a + b, 0) > available) {
      const largest = Math.max(...widths);
      widths[widths.indexOf(largest)]--;
    }
    if (offset) out.push([]);
    cells.forEach((row, index) => {
      const wrapped = widths.map((w, c) =>
        wrapSegments(
          inline(row[offset + c] || "", T, index === 0 ? { bold: true } : {}),
          w,
          { tokenBreaks: true },
        ),
      );
      // A trailing code-chip pad is not an extra physical cell line.
      for (const cell of wrapped)
        while (cell.length > 1 && !lineText(cell.at(-1)).trim()) cell.pop();
      const height = Math.max(...wrapped.map((l) => l.length));
      for (let y = 0; y < height; y++)
        out.push(
          widths.flatMap((w, c) => [
            ...(c ? [seg(" │ ", { color: T.border })] : []),
            ...pad(wrapped[c][y] || [], w),
          ]),
        );
      if (index === 0)
        out.push([
          seg(widths.map((n) => "─".repeat(n)).join("─┼─"), {
            color: T.border,
          }),
        ]);
    });
  }
  return out;
}

/** A small block pass, deliberately independent of React and terminal state. */
export function markdown(value, width, T) {
  const source = safe(value).replace(/\t/g, "    ").split("\n"),
    out = [];
  const gap = () => {
    if (out.length && lineText(out.at(-1)) !== "") out.push([]);
  };
  const special = (s) => /^\s*(?:#{1,6}\s|```|~~~|>|[-+*]\s|\d+[.)]\s)/.test(s);
  for (let i = 0; i < source.length; ) {
    const raw = source[i];
    if (!raw.trim()) {
      gap();
      i++;
      continue;
    }
    const fence = raw.match(/^\s*(```+|~~~+)/);
    if (fence) {
      gap();
      i++;
      while (i < source.length && !source[i].trimStart().startsWith(fence[1])) {
        for (const l of wrapSegments(
          [seg(source[i], { color: T.fg, bg: T.code_bg })],
          width,
        ))
          out.push(pad(l, width).map((s) => ({ ...s, bg: T.code_bg })));
        i++;
      }
      if (i < source.length) i++;
      gap();
      continue;
    }
    if (raw.includes("|") && tableRule(source[i + 1] || "")) {
      gap();
      const block = [source[i++], source[i++]];
      while (i < source.length && source[i].includes("|") && source[i].trim())
        block.push(source[i++]);
      out.push(...table(block, width, T));
      gap();
      continue;
    }
    const heading = raw.match(/^\s*#{1,6}\s+(.+?)\s*#*$/);
    if (heading) {
      gap();
      out.push(...wrapSegments(inline(heading[1], T, { bold: true }), width));
      gap();
      i++;
      continue;
    }
    const list = raw.match(/^(\s*)([-+*]|\d+[.)])\s+(.+)$/);
    if (list) {
      const indent = list[1].length ? "  " : "";
      const marker = /^\d/.test(list[2]) ? list[2] : "•";
      const first = `${indent}${marker} `,
        rest = " ".repeat(displayWidth(first));
      let body = list[3];
      i++;
      while (
        i < source.length &&
        /^\s+\S/.test(source[i]) &&
        !special(source[i])
      )
        body += " " + source[i++].trim();
      out.push(...wrapSegments(inline(body, T), width, { first, rest }));
      continue;
    }
    if (/^\s*>/.test(raw)) {
      gap();
      while (i < source.length && /^\s*>/.test(source[i])) {
        out.push(
          ...wrapSegments(
            inline(source[i++].replace(/^\s*>\s?/, ""), T, { color: T.fg_dim }),
            width,
            { first: "│ ", rest: "│ " },
          ),
        );
      }
      gap();
      continue;
    }
    let paragraph = raw.trim();
    i++;
    while (
      i < source.length &&
      source[i].trim() &&
      !special(source[i]) &&
      !(source[i].includes("|") && tableRule(source[i + 1] || ""))
    )
      paragraph += " " + source[i++].trim();
    out.push(...wrapSegments(inline(paragraph, T), width));
  }
  while (out.length && lineText(out.at(-1)) === "") out.pop();
  return out;
}

export function shellTokens(value, T) {
  let program = true;
  return [
    ...safe(value).matchAll(
      /\s+|(?:[^\s'"|;&]+|'(?:\\.|[^'])*'|"(?:\\.|[^"])*")+|[|;&]+/g,
    ),
  ].map(([word]) => {
    let color = T.fg;
    if (/^\s+$/.test(word)) return seg(word, { color });
    if (/^[|;&]+$/.test(word)) {
      program = true;
      return seg(word, { color: T.syn_keyword });
    }
    if (/['"]/.test(word)) color = T.syn_string;
    else if (program) color = T.syn_keyword;
    else if (/^-/.test(word)) color = T.syn_flag;
    else if (/^\d+(?:\.\d+)?$/.test(word)) color = T.syn_number;
    if (!/^\w+=/.test(word)) program = false;
    return seg(word, { color });
  });
}

export function bubble(value, width, T, { agent = false, steer = false } = {}) {
  const max = Math.max(3, Math.floor(width * 0.8));
  let content;
  if (agent) {
    const prefix = [
      seg("󰍩 ", { color: T.fg }),
      seg("Agent  ", { color: T.muted }),
    ];
    const bodyWidth = Math.max(0, max - 2 - displayWidth(lineText(prefix)) - 2);
    content = [
      [
        ...prefix,
        ...clip(
          [seg(safe(value).split("\n")[0], { color: T.fg })],
          bodyWidth,
          true,
        ),
        seg(" ⌄", { color: T.muted }),
      ],
    ];
  } else
    content = wrapSegments(
      [
        ...(steer ? [seg("↪ Steer · ", { color: T.muted })] : []),
        seg(value, { color: T.fg }),
      ],
      max - 2,
    );
  const block = Math.min(
    max,
    Math.max(...content.map((l) => displayWidth(lineText(l)))) + 2,
  );
  return content.map((line) => [
    space(width - block),
    ...pad([space(1), ...clip(line, block - 2)], block).map((s) => ({
      ...s,
      bg: T.user_bubble,
    })),
  ]);
}
function ends(left, right, width) {
  const r = clip(right, width),
    rw = displayWidth(lineText(r));
  const l = clip(left, Math.max(0, width - rw - (rw ? 1 : 0)), true);
  return [...l, space(width - displayWidth(lineText(l)) - rw), ...r];
}
function timeLabel(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? ""
    : date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
}
export function displayPath(value, meta = {}, home = os.homedir()) {
  const file = safe(value);
  if (!path.isAbsolute(file)) return file;
  for (const root of [meta.worktreePath, meta.workspaceRoot]) {
    if (!root) continue;
    const relative = path.relative(root, file);
    if (
      relative === "" ||
      (relative !== ".." &&
        !relative.startsWith(".." + path.sep) &&
        !path.isAbsolute(relative))
    )
      return [meta.projectTitle || path.basename(root), relative]
        .filter(Boolean)
        .join("/");
  }
  return file === home
    ? "~"
    : file.startsWith(home + path.sep)
      ? "~" + file.slice(home.length)
      : file;
}
function rowLabel(row, meta) {
  const it = row.item;
  if (!it || !["read", "edit"].includes(view.action(it))) return row.text;
  if (it.fileName)
    return row.text.replace(it.fileName, displayPath(it.fileName, meta));
  return row.text.replace(/\/[^\n]+$/, (value) => displayPath(value, meta));
}
export function timelineLines(rows, width, details = {}, T = {}, meta = {}) {
  const lines = [];
  const gap = () => {
    while (lines.length && !lineText(lines.at(-1)).trim()) lines.pop();
    if (lines.length) lines.push([]);
  };
  for (const row of rows) {
    const it = row.item;
    const push = (line, selectable = false) =>
      lines.push(Object.assign(line, { rowId: row.id, selectable }));
    const plain = (text, color = T.muted) =>
      wrapSegments([seg(text, { color })], width).forEach((l) => push(l));
    if (row.kind === "user_message") {
      gap();
      bubble(row.text, width, T, {
        agent: it.createdBy === "agent" || it.creationSource === "mcp",
        steer: ["steer", "promoted_queued_to_steer"].includes(it.inputIntent),
      }).forEach((l) => push(l));
      gap();
      continue;
    }
    if (["assistant_message", "proposed_plan"].includes(row.kind)) {
      gap();
      markdown(row.text, width, T).forEach((l) => push(l));
      gap();
      continue;
    }
    const failure = it?.status === "failed";
    const color =
      failure || row.kind === "error"
        ? T.error
        : row.kind === "approval_request"
          ? T.warning
          : row.kind === "user_input_request"
            ? T.attention
            : T.muted;
    if (["turn", "working"].includes(row.kind)) {
      const left = [
        seg(row.text + (row.expandable ? (row.expanded ? " ⌄" : " ›") : ""), {
          color,
        }),
      ];
      const right = row.expanded
        ? [seg(timeLabel(row.startedAt), { color: T.faint })]
        : [];
      push(ends(left, right, width), true);
      push([seg("─".repeat(width), { color: T.border })]);
    } else {
      const live =
        row.kind === "live" &&
        /^(Running|Ran|Failed|Stopped) (.+)$/.exec(row.text);
      const label = live
        ? [
            seg(`${row.icon ? row.icon + " " : ""}${live[1]} `, {
              color: failure ? T.error : T.muted,
            }),
            seg(live[2], { color: failure ? T.error : T.fg }),
          ]
        : [
            seg(
              `${row.icon ? row.icon + " " : ""}${rowLabel(row, meta)}${failure ? "  ✕" : ""}`,
              { color },
            ),
          ];
      push(
        ends(
          label,
          row.expandable
            ? [seg(row.expanded ? "⌄" : "›", { color: T.faint })]
            : [],
          width,
        ),
        true,
      );
    }
    if (row.kind === "todo_list")
      for (const step of it.steps || [])
        plain(
          `   ${step.status === "completed" ? "✓" : step.status === "in_progress" ? "◉" : "○"} ${step.text}`,
        );
    if (!row.expanded || !it) continue;
    const detail = details[it.id],
      body = detail?.item || it;
    if (["command_execution", "dynamic_tool"].includes(it.type)) {
      const input =
        typeof body.input === "string"
          ? body.input
          : JSON.stringify(body.input, null, 2) || "";
      wrapSegments(shellTokens(input, T), width).forEach((l) => push(l));
      push([]);
      if (detail?.loading) plain("Loading output…");
      else if (detail?.error) plain(detail.error, T.error);
      else {
        const output = safe(detail?.output ?? body.output ?? "").split("\n");
        if (detail?.truncated || output.length > 120)
          plain("Earlier output not shown");
        plain(output.slice(-120).join("\n") || "No output.", T.fg_dim);
        if (body.exitCode != null && body.exitCode !== 0)
          plain(`exit ${body.exitCode}`, T.error);
      }
    } else if (it.type === "reasoning")
      markdown(it.text, width, T).forEach((l) => push(l));
    else if (it.type === "file_change") {
      for (const l of safe(
        it.diffStr ||
          `${displayPath(it.fileName, meta)} +${it.additions || 0} −${it.deletions || 0}`,
      ).split("\n"))
        plain(
          l,
          l.startsWith("+")
            ? T.diff_add
            : l.startsWith("-")
              ? T.diff_del
              : T.fg_dim,
        );
    } else if (it.type === "approval_request")
      plain(it.prompt || it.reason || JSON.stringify(it), T.warning);
    else if (it.type === "user_input_request")
      for (const q of it.questions || []) plain(q.question, T.attention);
    else plain(JSON.stringify(it, null, 2));
    gap();
  }
  return lines;
}

export function geometry(cols = 80, rows = 24) {
  const inner = Math.max(1, cols - 6),
    column = Math.min(92, inner);
  return {
    cols,
    rows,
    inner,
    column,
    left: 3 + Math.floor((inner - column) / 2),
    innerRows: Math.max(1, rows - 2),
  };
}
function composer(width, T, ui, model, working) {
  const inset = 2,
    inputWidth = Math.max(1, width - inset * 2);
  const value = safe(ui.editor?.value),
    cursor = Math.min(ui.editor?.cursor ?? value.length, value.length);
  let input;
  if (value)
    input = wrapSegments(
      [
        seg(value.slice(0, cursor), { color: T.fg }),
        ...(!ui.browse
          ? [
              seg(
                value[cursor] && value[cursor] !== "\n" ? value[cursor] : " ",
                { color: T.fg, inverse: true },
              ),
            ]
          : []),
        seg(
          value.slice(cursor + (!ui.browse && value[cursor] !== "\n" ? 1 : 0)),
          { color: T.fg },
        ),
      ],
      inputWidth,
    );
  else
    input = [
      [
        ...(!ui.browse ? [seg(" ", { color: T.fg, inverse: true })] : []),
        seg("Ask anything. @ files, $ skills, / commands", { color: T.muted }),
      ],
    ];
  const cursorRow = input.findIndex((l) => l.some((s) => s.inverse));
  const inputRows = ui.inputRows ?? 6;
  const start = Math.max(0, cursorRow - inputRows + 1);
  input = input.slice(start, start + inputRows).map((l) => clip(l, inputWidth));
  const buttonColor = working ? T.error : T.accent;
  // Powerline half circles (U+E0B6/U+E0B4) make a true pill; Herdr draws them
  // without a Nerd Font. The ANSI fallback keeps plain half blocks.
  const [capLeft, capRight] = T.surface != null ? ["\ue0b6", "\ue0b4"] : ["▐", "▌"];
  const button = [
    seg(capLeft, { color: buttonColor }),
    seg(working ? " ■ " : " ↑ ", {
      color: T.accent_fg,
      bg: buttonColor,
      bold: true,
    }),
    seg(capRight, { color: buttonColor }),
  ];
  const label = [
    seg("✳", { color: T.provider }),
    seg(model.name || "T3", { color: T.fg }),
    seg(model.effort ? ` ${model.effort}` : "", { color: T.muted }),
  ];
  // Reserve the whole control before clipping the label, including at 20 columns.
  const labelWidth = Math.max(0, inputWidth - displayWidth(lineText(button)) - 2);
  const controls = ends(
    [],
    [...clip(label, labelWidth, true), space(2), ...button],
    inputWidth,
  );
  const content = [...input, [], controls].map((l) =>
    pad([space(inset), ...l], width),
  );
  if (T.surface != null) {
    // Outside the card is unpainted terminal-default background, not T.bg.
    // Leave the empty quadrants transparent so standalone terminals match too.
    const edge = (left, fill, right) => [
      seg(left + fill.repeat(Math.max(0, width - 2)) + right, { color: T.surface }),
    ];
    return [
      edge("▗", "▄", "▖"),
      ...content.map((l) => l.map((s) => ({ ...s, bg: s.bg ?? T.surface }))),
      edge("▝", "▀", "▘"),
    ];
  }
  // Round outline is the ANSI fallback. It occupies the same cell budget as fill padding.
  return [
    [seg("╭" + "─".repeat(Math.max(0, width - 2)) + "╮", { color: T.border })],
    ...content.map((l) => [
      seg("│", { color: T.border }),
      ...pad(clip(l, width - 2), width - 2),
      seg("│", { color: T.border }),
    ]),
    [seg("╰" + "─".repeat(Math.max(0, width - 2)) + "╯", { color: T.border })],
  ];
}
/** The `/` / `$` completion list drawn just above the composer card. */
export function menuLines(menu, width, T, maxRows = 8) {
  if (!menu || maxRows < 1) return [];
  const fill = (l, bg) =>
    pad(clip(l, width, true), width).map((s) => ({ ...s, bg: s.bg ?? bg }));
  if (!menu.items.length)
    return [fill([space(2), seg(menu.empty, { color: T.muted })], T.surface)];
  const count = Math.min(menu.items.length, maxRows);
  const sel = Math.max(0, Math.min(menu.sel || 0, menu.items.length - 1));
  const start = Math.max(
    0,
    Math.min(sel - Math.floor(count / 2), menu.items.length - count),
  );
  const shown = menu.items.slice(start, start + count);
  const labelWidth = Math.min(
    Math.max(...shown.map((i) => displayWidth(i.label))),
    Math.floor(width * 0.4),
  );
  return shown.map((item, k) => {
    const on = start + k === sel;
    const label = clip([seg(item.label)], labelWidth, true)[0]?.text || "";
    const line = [
      seg(on ? " › " : "   ", { color: T.accent }),
      seg(label, { color: T.fg, bold: on }),
      space(labelWidth - displayWidth(label) + 2),
      seg(item.description, { color: T.muted }),
    ];
    if (!on) return fill(line, T.surface);
    return T.surface == null
      ? fill(line).map((s) => ({ ...s, inverse: true }))
      : fill(line, T.user_bubble);
  });
}
function modelColumnWidths(width) {
  const available = width - 6; // two three-cell dividers
  const widths = [Math.floor(available * 0.25), Math.floor(available * 0.49)];
  return [...widths, available - widths[0] - widths[1]];
}
/** A single viewport with independently scrolled harness/model/effort columns. */
export function modelPickerLines(columns, width, T, maxRows = 10) {
  if (!columns || maxRows < 3) return [];
  const widths = modelColumnWidths(width);
  const count = Math.min(
    maxRows - 2,
    Math.max(...columns.map((c) => c.items.length)),
  );
  const fill = (line, w, bg = T.surface) =>
    pad(clip(line, w, true), w).map((s) => ({ ...s, bg }));
  const join = (cells) =>
    cells.flatMap((cell, i) =>
      i ? [seg(" │ ", { color: T.border, bg: T.surface }), ...cell] : cell,
    );
  const lines = [
    join(
      columns.map((c, i) =>
        fill(
          [
            seg(` ${c.focused ? "›" : " "} ${c.label}`, {
              color: c.focused ? T.accent : T.muted,
              bold: c.focused,
            }),
          ],
          widths[i],
        ),
      ),
    ),
  ];
  const starts = columns.map((c) =>
    Math.max(
      0,
      Math.min(c.selected - Math.floor(count / 2), c.items.length - count),
    ),
  );
  for (let row = 0; row < count; row++) {
    lines.push(
      join(
        columns.map((c, i) => {
          const index = starts[i] + row,
            item = c.items[index];
          const selected = index === c.selected,
            focused = selected && c.focused;
          const line = fill(
            item
              ? [
                  seg(selected ? " › " : "   ", { color: T.accent }),
                  seg(item.label + (item.reason ? " (locked)" : ""), {
                    color: item.reason ? T.faint : T.fg,
                    bold: selected,
                  }),
                ]
              : [],
            widths[i],
            focused && T.surface != null ? T.user_bubble : T.surface,
          );
          return focused && T.surface == null
            ? line.map((s) => ({ ...s, inverse: true }))
            : line;
        }),
      ),
    );
  }
  lines.push(
    fill([space(1), seg(columns.note || "", { color: T.muted })], width),
  );
  return lines;
}
/** Centered answer surface. Scroll whole bubbles, not clipped fragments. */
export function questionLines(request, card, width, T, ui, maxRows) {
  const questions = card?.questions || [];
  const index = questions.findIndex(q => !Object.hasOwn(ui.answerDraft || {}, q.id));
  const q = questions[index];
  if (!q || maxRows < 3) return [];
  const current = questionUI.selection(request.id, q, ui.questionSelection);
  const contentWidth = Math.max(1, width - 4);
  const fill = (line, bg = T.surface) => pad(clip(line, width), width).map(s => ({...s, bg: s.bg ?? bg}));
  const edge = (left, middle, right, w, color) => [seg(left + middle.repeat(Math.max(0, w - 2)) + right, {color})];
  const rounded = (top, w, color) => T.surface != null
    ? edge(...(top ? ["▗", "▄", "▖"] : ["▝", "▀", "▘"]), w, color)
    : edge(...(top ? ["╭", "─", "╮"] : ["╰", "─", "╯"]), w, color);
  const progress = questions.length > 1 ? `${index + 1}/${questions.length} · ` : "";
  const header = [space(2), ...clip([seg(progress + safe(q.question), {color: T.fg, bold: true})], contentWidth, true)];
  const items = [...(q.options || []), ...(q.allowCustomAnswer !== false ? [{label: "Type your answer…"}] : [])];
  if (!items.length) items.push({label: "No answers available"});
  const room = maxRows - 3; // top, single-line header, bottom
  // Preserve every answer before scrolling: use the composer's half-row caps
  // only when all bubbles fit; otherwise spend one compact row per bubble.
  const bubbleRows = room >= items.length * 3 ? 3 : 1;
  const count = Math.min(items.length, Math.floor(room / bubbleRows));
  const start = Math.max(0, Math.min(current.selected - Math.floor(count / 2), items.length - count));
  const lines = [rounded(true, width, T.surface ?? T.border), fill(header)];
  for (let n = start; n < start + count; n++) {
    const item = items[n], on = n === current.selected;
    const bg = on ? T.accent : T.user_bubble ?? T.surface;
    const fg = on ? T.accent_fg : T.fg;
    const multi = q.multiSelect && n < (q.options?.length || 0);
    const label = `${multi ? (current.checked.includes(n) ? "☑ " : "☐ ") : ""}${n + 1} ${safe(item.label)}`;
    const details = safe(item.description);
    const line = [seg(label, {color: fg, bold: on})];
    if (details && displayWidth(label) + displayWidth(details) + 3 <= contentWidth - 2)
      line.push(space(3), seg(details, {color: on ? T.accent_fg : T.muted}));
    if (bubbleRows === 3) {
      lines.push(fill([space(1), ...rounded(true, width - 2, bg ?? T.border)]));
      const cell = T.surface != null
        ? pad([space(1), ...clip(line, contentWidth - 2, true)], width - 2).map(s => ({...s, bg}))
        : [seg("│", {color: T.border}), ...pad(clip(line, contentWidth - 2, true), width - 4).map(s => ({...s, inverse: on})), seg("│", {color: T.border})];
      lines.push(fill([space(1), ...cell]));
      lines.push(fill([space(1), ...rounded(false, width - 2, bg ?? T.border)]));
    } else {
      const cell = [seg("╭", {color: on ? T.accent : T.border}), ...pad(clip(line, contentWidth - 2, true), contentWidth - 2), seg("╮", {color: on ? T.accent : T.border})].map(s => ({...s, bg, inverse: T.surface == null && on}));
      lines.push(fill([space(2), ...cell]));
    }
  }
  lines.push(rounded(false, width, T.surface ?? T.border));
  return lines;
}
function requestLines(state, width, T, ui) {
  const request = t3.pendingRequests(state)[0];
  if (!request) return [];
  const card = t3.timeline(state).find((i) => i.requestId === request.id);
  const question = card?.questions?.find(
    (q) => !Object.hasOwn(ui.answerDraft || {}, q.id),
  );
  const input = request.kind === "user_input",
    color = input ? T.attention : T.warning;
  const title = `${input ? "Input requested" : "Waiting for approval"}${request.responseCapability?.type === "not_resumable" ? " · cannot resume in this client" : ""}`;
  const content = input
    ? [
        question?.question || "Preparing answers…",
        (question?.options || [])
          .map((o, i) => `${i + 1} ${o.label}`)
          .join(" · "),
      ]
    : [
        card?.prompt || card?.reason || "",
        "y Approve · a Allow this session · n Decline",
      ];
  return [
    [seg(title, { color, bold: true })],
    ...content.flatMap((s) => wrapSegments([seg(s, { color })], width)),
  ]
    .slice(0, 6)
    .map((l) => clip(l, width));
}

/** Frozen at commit time: history keeps its original width and theme on resize. */
export function historyLines(block, cols = 80, T = {}, meta = {}, details = {}) {
  const g = geometry(cols);
  return [...timelineLines(block.rows, g.column, details, T, meta), []].map(l =>
    pad([space(g.left), ...clip(l, g.column)], cols),
  );
}

/** Only the live region. Strictly shorter than the terminal (Ink 5 otherwise
 * clears the screen and reprints Static history). No viewport or scroll offset. */
export function frame({ state, cols = 80, rows = 24, tokens: T = {}, ui = {} } = {}) {
  const g = geometry(cols, rows), width = g.column;
  const cap = Math.max(1, Math.min(20, rows - 2));
  const meta = t3.threadMeta?.(state, ui.projects || new Map()) || {
    title: state?.thread?.title || ui.threadId || "New thread",
  };
  const model = t3.modelLabel?.(state?.thread) || { name: "T3", effort: "" };
  const working = ["working", "blocked"].includes(t3.status(state));
  const pending = t3.pendingRequests(state)[0];
  const questionCard = pending?.kind === "user_input" && pending.responseCapability?.type !== "not_resumable"
    ? t3.timeline(state).find(i => i.requestId === pending.id) : null;
  const questionWidth = Math.min(width, Math.max(30, Math.round(width * 0.6)));
  // Leave a compact question viewport even for a six-line/pasted draft. Keep
  // the accepted editor viewport rather than forcing custom answers to one row.
  const card = composer(width, T, { ...ui, browse: false, inputRows: Math.max(1, Math.min(6, cap - (questionCard ? 9 : 6))) }, model, working);
  const requestRoom = Math.max(0, cap - card.length - 3);
  const dialog = ui.compactDialog
    ? wrapSegments([seg(ui.compactDialog.text, { color: ui.compactDialog.allowed ? T.attention : T.warning, bold: true })], width)
    : [];
  const questionWindow = questionCard ? questionLines(pending, questionCard, questionWidth, T, ui, Math.max(0, cap - card.length - dialog.length - 1))
    .map(l => [space(Math.floor((width - questionWidth) / 2)), ...l]) : [];
  const requests = questionCard ? dialog.slice(0, Math.max(0, cap - card.length - questionWindow.length - 1))
    : [...dialog, ...requestLines(state, width, T, ui)].slice(0, requestRoom);
  const room = Math.max(0, cap - card.length - requests.length - questionWindow.length - 3);
  const menu = ui.modelPicker
    ? modelPickerLines(ui.modelPicker, width, T, Math.min(11, room))
    : menuLines(ui.menu, width, T, Math.min(8, room));
  const menuGap = menu.length ? [[]] : [];
  const projected = ui.timelineRows || partition(state, ui.expanded, ui.now ?? 0).live;
  // The pending input is already represented by the window. Do not repeat its
  // old timeline text when live details are expanded with Tab.
  const all = timelineLines(projected.filter(r => !(questionCard && r.item?.requestId === pending.id)), width, ui.details || {}, T, meta);
  const bodyRows = Math.max(0, cap - card.length - requests.length - questionWindow.length - menu.length - menuGap.length - (questionCard ? 1 : 2));
  let timeline = all;
  if (all.length > bodyRows) {
    // Preserve the timer and latest answer/output. The final complete answer is
    // never truncated: it is printed separately into append-only scrollback.
    timeline = bodyRows > 2
      ? [all[0], [seg("… live preview (full answer on completion)", { color: T.faint })], ...all.slice(-(bodyRows - 2))]
      : all.slice(-bodyRows);
    if (!bodyRows) timeline = [];
  }
  const [label, statusToken] = t3.statusLabel(state, ui.conn || "live");
  const usage = t3.contextUsage(state);
  const left = [
    meta.projectTitle ? `󰉋 ${meta.projectTitle}` : "",
    meta.title || ui.threadId || "New thread",
    meta.branch ? ` ${meta.branch}` : "",
    meta.worktreeName ? `󰙅 worktree ${meta.worktreeName}` : "",
  ].filter(Boolean).join(" · ");
  const status = ui.flash || ui.modelPicker || ui.menu
    ? pad(clip([seg(ui.flash || (ui.modelPicker
        ? "h/l ←/→ columns · j/k ↑/↓ ^N/^P · gg/G · Enter apply · Esc/q close"
        : `${ui.menu.trigger.kind === "skill" ? "Skills" : "Commands"}: ↑/↓ select · Tab/Enter insert · Esc close${ui.menu.items.length ? ` · ${ui.menu.items.length} found` : ""}`),
        { color: ui.flash ? T.error : T.muted })], width, true), width)
    : ends([seg(left, { color: T.muted })], [
        seg(label, { color: T[statusToken] ?? T.muted }),
        seg(usage == null ? "" : ` · Context ${usage}%`, { color: usage >= 90 ? T.error : usage >= 80 ? T.warning : T.faint }),
      ], width);
  const columnLine = l => pad([space(g.left - 3), ...pad(clip(l, width), width)], g.inner);
  const innerLines = [...timeline, ...requests, ...(questionCard ? [] : [[]]), ...menu, ...menuGap, ...questionWindow, ...card, status]
    .slice(-cap).map(columnLine);
  const lines = innerLines.map(l => [space(3), ...l, space(3)]);
  return { geometry: g, lines, innerLines, all, bodyRows, composer: card, status, cap };
}
