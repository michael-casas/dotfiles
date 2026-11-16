import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseBoard, blockHash, safeText } from "../document.mjs";

export const header = {
  format: "envi-whiteboard",
  version: 0,
  id: "demo",
  roots: { repo: { kind: "git" } },
};
export const board = (body = "<!-- wb:id title -->\n# Demo\n", h = header) =>
  `---\n${JSON.stringify(h)}\n---\n\n${body}`;
const example = readFileSync(
  new URL("./fixtures/example.wb.md", import.meta.url),
);
const invalid = (text, code) => {
  const d = parseBoard(Buffer.from(text));
  assert.equal(d.valid, false);
  assert.ok(
    d.diagnostics.some((x) => x.code === code),
    JSON.stringify(d.diagnostics),
  );
};

test("ratified example has stable blocks, sections, attached thread and byte-identical source", () => {
  const d = parseBoard(example);
  assert.equal(d.valid, true, JSON.stringify(d.diagnostics));
  assert.equal(d.blocks.filter((b) => b.kind === "mermaid").length, 2);
  assert.equal(
    d.blocks.find((b) => b.id === "thread-fallback").attachment,
    "attached",
  );
  assert.equal(
    d.blocks.find((b) => b.id === "source-options").record.root,
    "repo",
  );
  assert.deepEqual(d.bytes, example);
  for (const b of d.blocks)
    assert.equal(example.subarray(b.start, b.end).toString(), b.raw);
});
test("duplicate keys at any JSON depth are errors, including escaped equivalent keys", () => {
  invalid(board().replace('"version":0', '"version":0,"version":0'), "json");
  invalid(
    board().replace('"kind":"git"', '"kind":"git","k\\u0069nd":"git"'),
    "json",
  );
});
test("duplicate IDs and markers without a target never resolve by first/last match", () => {
  invalid(
    board("<!-- wb:id title -->\n# Demo\n\n<!-- wb:id title -->\n## More\n"),
    "duplicate-id",
  );
  invalid(board() + "\n<!-- wb:id dangling -->\n", "marker");
  invalid(board() + "\n<!-- wb:id a -->\n\n<!-- wb:id b -->\ntext\n", "marker");
});
test("CommonMark boundaries: fences, lists, quotations and HTML cannot declare markers", () => {
  for (const body of [
    "````text\n<!-- wb:id fake -->\n# Fake\n````\n",
    "- item\n\n  <!-- wb:id fake -->\n  # Fake\n",
    "> <!-- wb:id fake -->\n> # Fake\n",
    "<div>\n<!-- wb:id fake -->\n# Fake\n</div>\n",
  ]) {
    const d = parseBoard(Buffer.from(board() + "\n" + body));
    assert.equal(d.valid, true, JSON.stringify(d.diagnostics));
    assert.ok(!d.blocks.some((b) => b.id === "fake"));
  }
});
test("only top-level ATX headings index sections; heading, reserved fence and closed fences required", () => {
  invalid(board("# Demo\n"), "required-marker");
  invalid(board("<!-- wb:id title -->\nTitle\n=====\n"), "heading");
  invalid(
    board() + "\n```mermaid\nflowchart LR\nA --> B\n```\n",
    "required-marker",
  );
  invalid(board() + "\n<!-- wb:id d -->\n```mermaid\nflowchart LR\n", "fence");
  const d = parseBoard(
    Buffer.from(board() + "\n```mermaid extra\nliteral\n```\n"),
  );
  assert.equal(d.valid, true);
  assert.ok(!d.blocks.some((b) => b.kind === "mermaid"));
});
test("unknown versions and requirements are opaque, preserve bytes and disable interpretation", () => {
  for (const h of [
    { ...header, version: 1 },
    { ...header, requires: ["future-feature"] },
  ]) {
    const bytes = Buffer.from(
      board("<!-- wb:id d -->\n```wb-source\nnot JSON\n```\n", h),
    );
    const d = parseBoard(bytes);
    assert.equal(d.opaque, true);
    assert.equal(d.blocks.length, 0);
    assert.deepEqual(d.bytes, bytes);
  }
});
test("BOM/CRLF spans are byte-exact; normalized block hashes agree", () => {
  const lf = parseBoard(example);
  const bytes = Buffer.from(
    "\ufeff" + example.toString().replaceAll("\n", "\r\n"),
  );
  const d = parseBoard(bytes);
  assert.equal(d.valid, true);
  assert.deepEqual(d.bytes, bytes);
  for (const b of d.blocks) {
    assert.equal(bytes.subarray(b.start, b.end).toString(), b.raw);
    assert.equal(
      blockHash(b.raw),
      blockHash(lf.blocks[d.blocks.indexOf(b)].raw),
    );
  }
  assert.equal(
    d.blocks.find((b) => b.id === "thread-fallback").attachment,
    "attached",
  );
});
test("strict envelope, schema, Unicode, integer and size limits", () => {
  invalid("prefix\n" + board(), "envelope");
  invalid(board().replace("---\n\n", "---\n"), "envelope");
  invalid(
    board().replace('"version":0', '"version":0.0,"x":9007199254740992'),
    "json",
  );
  invalid(board().replace('"demo"', '"\\ud800"'), "json");
  invalid(
    Buffer.concat([Buffer.from(board()), Buffer.from([0xff])]),
    "encoding",
  );
  invalid(board("x".repeat(2 * 1024 * 1024)), "limit");
  invalid(
    board().replace('"demo"', JSON.stringify("x".repeat(65536))),
    "limit",
  );
  invalid(board().replace('"demo"', "false"), "schema");
});
const source = (value) =>
  board() +
  `\n<!-- wb:id pin -->\n\`\`\`wb-source\n${JSON.stringify(value)}\n\`\`\`\n`;
const pin = {
  root: "repo",
  path: "src/file.txt",
  commit: "a".repeat(40),
  lines: { start: 1, end: 2 },
};
test("source paths, root declaration, ordered ranges and safe integers enforced independently of binding", () => {
  for (const path of [
    "../x",
    "a/../x",
    "a//b",
    "./x",
    "/tmp/x",
    "C:/x",
    "a\\b",
    "a\u0000b",
    "a\u0085b",
  ])
    invalid(source({ ...pin, path }), "source");
  invalid(source({ ...pin, root: "undeclared" }), "source");
  invalid(source({ ...pin, lines: { start: 3, end: 2 } }), "source");
  invalid(source({ ...pin, commit: "HEAD" }), "schema");
  const d = parseBoard(Buffer.from(source(pin)));
  assert.equal(d.valid, true);
  assert.ok(d.diagnostics.some((x) => x.code === "source-unbound"));
});
test("thread attachment is recoverable, message IDs/date-time and thread targets checked", () => {
  const d = parseBoard(example);
  const thread = d.blocks.find((b) => b.kind === "wb-thread");
  const replace = (record) =>
    example.toString().replace(thread.content, JSON.stringify(record) + "\n");
  const r = structuredClone(thread.record);
  r.anchor.baseSha256 = "0".repeat(64);
  assert.equal(
    parseBoard(Buffer.from(replace(r))).blocks.find(
      (b) => b.kind === "wb-thread",
    ).attachment,
    "changed-target",
  );
  r.anchor.target = "gone";
  assert.equal(parseBoard(Buffer.from(replace(r))).valid, true);
  r.anchor.target = thread.id;
  invalid(replace(r), "thread");
  r.anchor.target = "diagram-pipeline";
  r.messages.push(r.messages[0]);
  invalid(replace(r), "thread");
  r.messages.pop();
  r.messages[0].createdAt = "2026-99-99";
  invalid(replace(r), "schema");
});
test("hash contract includes delimiters, excludes markers and strips LF only", () => {
  assert.equal(blockHash("a\r\n\r\n"), blockHash("a\n"));
  assert.notEqual(blockHash("a \n"), blockHash("a\n"));
  assert.notEqual(blockHash("```mermaid\na\n```\n"), blockHash("a\n"));
});
test("terminal controls and bidi are visible literals, never forwarded", () => {
  const s = safeText("x\x1b]52;c;payload\x07\u009b31m\u202eABC\t\n");
  assert.ok(!/[\x00-\x08\x0b-\x1f\x7f-\x9f\u202e]/u.test(s));
  assert.match(s, /U\+001B/);
  assert.match(s, /U\+202E/);
});
