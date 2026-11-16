import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import * as commonmark from "commonmark";
import Ajv from "ajv/dist/2020.js";
import formats from "ajv-formats";

export const LIMITS = Object.freeze({
  document: 2 * 1024 * 1024,
  header: 65536,
  record: 262144,
  depth: 32,
  blocks: 1000,
  diagrams: 64,
  diagram: 50 * 1024,
});
export const blockHash = (s) =>
  createHash("sha256")
    .update(s.replaceAll("\r\n", "\n").replace(/\n*$/, "") + "\n")
    .digest("hex");
export const safeText = (s) =>
  String(s).replace(
    /[\x00-\x08\x0b-\x1f\x7f-\x9f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]/gu,
    (c) =>
      `<U+${c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")}>`,
  );
export const safePath = (p) =>
  typeof p === "string" &&
  p.length > 0 &&
  !/^[A-Za-z]:|[\\\x00-\x1f\x7f-\x9f]/u.test(p) &&
  p.split("/").every((x) => x && x !== "." && x !== "..");

const schema = JSON.parse(
  readFileSync(new URL("./records.schema.json", import.meta.url)),
);
const ajv = new Ajv({ strict: false, allErrors: true });
formats(ajv);
ajv.addSchema(schema);
const validators = Object.fromEntries(
  ["header", "source", "thread"].map((name) => [
    name,
    ajv.compile({ $ref: `${schema.$id}#/$defs/${name}` }),
  ]),
);

/** Small RFC8259 lexer: duplicate-aware before schema, no eval/reviver collapse. */
export function strictJSON(text, maxBytes = LIMITS.record) {
  if (Buffer.byteLength(text) > maxBytes) throw Error("JSON size limit");
  let i = 0;
  const ws = () => {
    while (/[\t\r\n ]/.test(text[i] ?? "!")) i++;
  };
  const fail = () => {
    throw Error("Invalid or duplicate JSON");
  };
  const string = () => {
    const start = i++;
    while (i < text.length) {
      const c = text[i++];
      if (c === '"') {
        let value;
        try {
          value = JSON.parse(text.slice(start, i));
        } catch {
          fail();
        }
        if (!value.isWellFormed()) fail();
        return value;
      }
      if (c === "\\") i++;
      else if (c < " ") fail();
    }
    fail();
  };
  function value(depth) {
    if (depth > LIMITS.depth) fail();
    ws();
    const c = text[i];
    if (c === '"') return string();
    if (c === "{") {
      i++;
      ws();
      const out = Object.create(null),
        seen = new Set();
      if (text[i] === "}") {
        i++;
        return out;
      }
      while (i < text.length) {
        ws();
        if (text[i] !== '"') fail();
        const key = string();
        if (seen.has(key)) fail();
        seen.add(key);
        ws();
        if (text[i++] !== ":") fail();
        out[key] = value(depth + 1);
        ws();
        const end = text[i++];
        if (end === "}") return out;
        if (end !== ",") fail();
      }
      fail();
    }
    if (c === "[") {
      i++;
      ws();
      const out = [];
      if (text[i] === "]") {
        i++;
        return out;
      }
      while (i < text.length) {
        out.push(value(depth + 1));
        ws();
        const end = text[i++];
        if (end === "]") return out;
        if (end !== ",") fail();
      }
      fail();
    }
    for (const [token, v] of [
      ["true", true],
      ["false", false],
      ["null", null],
    ])
      if (text.startsWith(token, i)) {
        i += token.length;
        return v;
      }
    const number = text
      .slice(i)
      .match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/);
    if (!number) fail();
    i += number[0].length;
    const n = Number(number[0]);
    if (
      !Number.isFinite(n) ||
      (Number.isInteger(n) && !Number.isSafeInteger(n))
    )
      fail();
    return n;
  }
  const out = value(0);
  ws();
  if (
    i !== text.length ||
    !out ||
    Array.isArray(out) ||
    typeof out !== "object"
  )
    fail();
  return out;
}

export function parseBoard(input) {
  const bytes = Buffer.from(input),
    diagnostics = [];
  const result = {
    valid: false,
    opaque: false,
    bytes,
    hash: createHash("sha256").update(bytes).digest("hex"),
    header: null,
    blocks: [],
    diagnostics,
  };
  const add = (code, message, severity = "error", block = null) =>
    diagnostics.push({
      category: ["source", "source-unbound"].includes(code)
        ? "source"
        : code === "attachment"
          ? "attachment"
          : "structure",
      code,
      message,
      severity,
      block,
    });
  if (bytes.length > LIMITS.document) {
    add("limit", "Document exceeds 2 MiB");
    return result;
  }
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(
      bytes,
    );
  } catch {
    add("encoding", "Invalid UTF-8");
    return result;
  }
  const lines = text.split(/(?<=\n)/),
    offsets = [];
  let offset = 0;
  for (const line of lines) {
    offsets.push(offset);
    offset += Buffer.byteLength(line);
  }
  const lineText = (n) => (lines[n] ?? "").replace(/\r?\n$/, "");
  if (
    lineText(0).replace(/^\ufeff/, "") !== "---" ||
    !lines[0]?.endsWith("\n")
  ) {
    add("envelope", "Expected initial JSON envelope");
    return result;
  }
  let close = 1;
  while (
    close < lines.length &&
    lineText(close) !== "---" &&
    offsets[close] <= LIMITS.header
  )
    close++;
  if (offsets[close] > LIMITS.header) {
    add("limit", "Header exceeds 64 KiB");
    return result;
  }
  if (
    close >= lines.length ||
    !lines[close].endsWith("\n") ||
    lineText(close + 1) !== "" ||
    !lines[close + 1]?.endsWith("\n")
  ) {
    add("envelope", "Missing envelope close or blank separator");
    return result;
  }
  try {
    result.header = strictJSON(lines.slice(1, close).join(""), LIMITS.header);
  } catch {
    add(
      "json",
      "Invalid header JSON (duplicate keys, Unicode, depth or numeric bounds)",
    );
    return result;
  }
  const h = result.header;
  // An unknown version is opaque, not a v0 schema failure or a semantic downgrade.
  if (
    h.format === "envi-whiteboard" &&
    Number.isSafeInteger(h.version) &&
    h.version >= 0 &&
    h.version !== 0
  ) {
    result.opaque = true;
    add("unsupported", "Unknown version; opaque read-only source", "warning");
    result.valid = true;
    return result;
  }
  if (!validators.header(h)) {
    add("schema", "Header does not match v0 schema");
    return result;
  }
  if (h.requires?.length) {
    result.opaque = true;
    add(
      "unsupported",
      "Unknown required feature; opaque read-only source",
      "warning",
    );
    result.valid = true;
    return result;
  }
  const first = close + 2,
    body = lines.slice(first).join("");
  const ast = new commonmark.Parser({ smart: false }).parse(body);
  let pending = null,
    h1 = 0,
    marked = 0,
    diagrams = 0;
  const ids = new Map();
  for (let n = ast.firstChild; n; n = n.next) {
    const startLine = first + n.sourcepos[0][0] - 1,
      endLine = first + n.sourcepos[1][0] - 1;
    const raw = lines.slice(startLine, endLine + 1).join("");
    const marker =
      n.type === "html_block" &&
      raw
        .replace(/\r?\n$/, "")
        .match(/^<!-- wb:id ([a-z][a-z0-9-]{0,63}) -->$/);
    if (marker) {
      if (pending) add("marker", "Marker must immediately precede one target");
      pending = marker[1];
      if (ids.has(pending))
        add("duplicate-id", "Duplicate block ID", "error", pending);
      ids.set(pending, null);
      marked++;
      continue;
    }
    let kind = n.type,
      content = raw,
      record = null;
    if (n.type === "heading") {
      if (!/^ {0,3}#{1,6}(?:\s|$)/.test(raw))
        add("heading", "Only top-level ATX headings are supported");
      if (n.level === 1) h1++;
    }
    if (n.type === "code_block" && /^ {0,3}(`{3,}|~{3,})/.test(raw)) {
      const open = raw.match(/^ {0,3}(`{3,}|~{3,})([^\r\n]*)/),
        fence = open[1];
      const last = lineText(endLine);
      if (
        endLine === startLine ||
        !new RegExp(`^ {0,3}${fence[0]}{${fence.length},}[ \\t]*$`).test(last)
      )
        add("fence", "Unclosed fenced block");
      const info = (n.info ?? "").trim();
      if (["mermaid", "wb-source", "wb-thread"].includes(info)) {
        kind = info;
        content = n.literal;
      } else if (info.startsWith("wb-"))
        add(
          "unsupported",
          "Unknown record shown as literal source",
          "warning",
          pending,
        );
    }
    if (
      ["heading", "mermaid", "wb-source", "wb-thread"].includes(kind) &&
      !pending
    )
      add("required-marker", "Heading or reserved block needs a stable marker");
    const block = {
      id: pending,
      kind,
      raw,
      content,
      start: offsets[startLine],
      end: offsets[endLine] + Buffer.byteLength(lines[endLine]),
      line: startLine + 1,
      level: n.level ?? null,
      record,
    };
    if (kind === "html_block")
      add("html", "HTML is literal, not rendered", "warning", pending);
    if (kind === "mermaid") {
      diagrams++;
      if (Buffer.byteLength(content) > LIMITS.diagram)
        add("limit", "Diagram exceeds 50 KiB");
    }
    if (kind === "wb-source" || kind === "wb-thread") {
      try {
        record = strictJSON(content);
        block.record = record;
      } catch {
        add(
          "json",
          "Invalid record JSON (duplicates, depth, Unicode or bounds)",
          "error",
          pending,
        );
      }
      if (
        record &&
        !validators[kind === "wb-source" ? "source" : "thread"](record)
      )
        add("schema", "Record does not match v0 schema", "error", pending);
      else if (record && kind === "wb-source") {
        if (
          !Object.hasOwn(h.roots, record.root) ||
          !safePath(record.path) ||
          record.lines.end < record.lines.start
        )
          add(
            "source",
            "Unsafe path, undeclared root or reversed range",
            "error",
            pending,
          );
        else
          add(
            "source-unbound",
            "Source needs an explicit trusted root binding",
            "warning",
            pending,
          );
      } else if (record) {
        if (
          new Set(record.messages.map((m) => m.id)).size !==
          record.messages.length
        )
          add("thread", "Duplicate message ID", "error", pending);
      }
    }
    if (pending) ids.set(pending, block);
    pending = null;
    result.blocks.push(block);
  }
  if (pending) add("marker", "Marker has no target");
  if (h1 !== 1) add("heading", "Exactly one top-level H1 is required");
  if (marked > LIMITS.blocks || diagrams > LIMITS.diagrams)
    add("limit", "Too many marked blocks or diagrams");
  for (const b of result.blocks.filter(
    (b) => b.kind === "wb-thread" && b.record && validators.thread(b.record),
  )) {
    const target = ids.get(b.record.anchor.target);
    if (target?.kind === "wb-thread")
      add("thread", "A thread cannot target another thread", "error", b.id);
    b.attachment = !target
      ? "orphaned"
      : blockHash(target.raw) === b.record.anchor.baseSha256
        ? "attached"
        : "changed-target";
    if (b.attachment !== "attached")
      add("attachment", b.attachment, "warning", b.id);
    if (target && b.record.anchor.quote) {
      const q = b.record.anchor.quote,
        hay = target.raw.replaceAll("\r\n", "\n");
      let count = 0,
        pos = 0;
      while ((pos = hay.indexOf(q.exact, pos)) !== -1) {
        if (
          (!q.prefix || hay.slice(0, pos).endsWith(q.prefix)) &&
          (!q.suffix || hay.slice(pos + q.exact.length).startsWith(q.suffix))
        )
          count++;
        pos++;
      }
      b.quote = count === 1 ? "unique" : "ambiguous";
    }
  }
  result.valid = !diagnostics.some((d) => d.severity === "error");
  return result;
}
