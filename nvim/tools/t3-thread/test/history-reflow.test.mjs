import test from "node:test";
import assert from "node:assert/strict";
import * as C from "../control.mjs";
import * as S from "../scrollback.mjs";
import * as L from "../layout.mjs";
import { PassThrough } from "node:stream";
import { createControlInput } from "../control-input.mjs";

test("H1-04: layout check is correlated at every split and validates bounded IDs", () => {
  const seq = "\x1b[>777;9;42u";
  assert.equal(C.sequence("layout", 42), seq);
  for (let i = 0; i <= seq.length; i++) {
    const a = C.decode(seq.slice(0, i));
    const b = C.decode(seq.slice(i), a.state);
    assert.deepEqual([...a.events, ...b.events], [{type: "action", action: "layout", requestId: 42}]);
  }
  for (const id of [0, -1, 1.5, 1000000000, undefined]) assert.throws(() => C.sequence("layout", id));
  for (const id of ["0", "01", "-1", "1.2", "1000000000", "bad"]) assert.deepEqual(C.decode(`\x1b[>777;9;${id}u`).events, []);
});

test("H1-04/05: private layout bytes never enter Ink, including split UTF-8 and malformed reports", () => {
  const source = new PassThrough(), bridge = createControlInput(source);
  const actions = []; let text = "";
  bridge.stdin.on("data", d => text += d);
  bridge.onAction((action, requestId) => actions.push({action, requestId}));
  bridge.start();
  const bytes = Buffer.from("草\x1b[>777;9;999999999u\x1b[>777;9;0u!\x1b[H\x1b[F");
  for (const byte of bytes) source.write(Buffer.from([byte]));
  bridge.close();
  assert.equal(text, "草!\x01\x05");
  assert.deepEqual(actions, [{action: "layout", requestId: 999999999}]);
});

test("H1-01/02: semantic reflow keeps IDs, expanded detail, commit-time colour and strike policy", () => {
  const block = {id: "answer", rows: [{id: "answer", kind: "assistant_message", text: "HISTORY ~~plain~~ **bold** `code`"}]};
  const freeze = (b, cols) => ({...b, cols, lines: L.historyLines(b, cols, {fg: "#123456"})});
  const original = S.append(S.ledger(), [block], b => freeze(b, 100));
  assert.equal(S.frozenWidth(original, 160), 100);
  const changed = S.reflow(original, 160, freeze);
  assert.notEqual(changed, original);
  assert.equal(changed.ids, original.ids);
  assert.deepEqual(changed.items.map(b => b.id), ["answer"]);
  assert.deepEqual(changed.items[0].rows, original.items[0].rows);
  assert.deepEqual(changed.items[0].lines, freeze(block, 160).lines);
  assert.equal(S.append(changed, [block], () => assert.fail("no duplicate freeze")), changed);
  assert.equal(S.reflow(changed, 160, () => assert.fail("no same-width render")), changed);
  assert.equal(S.frozenWidth(S.ledger(), 160), 160);
  assert.equal(S.reflow(S.ledger(), 160, freeze).items.length, 0);
});

test("H1-01: direct history writer matches real Ink cell styles, surfaces and strike handling", async () => {
  const React = await import("react");
  const {render, Static, Box, Text, Transform} = await import("ink");
  const {historyOutput} = await import("../history-output.mjs");
  const spans = [
    {text: "plain ", color: "#123456"},
    {text: "bold ", bold: true, color: "cyan"},
    {text: "code ", color: "rgb(10, 20, 30)", bg: "#242933"},
    {text: "under ", underline: true, color: "ansi256(42)"},
    {text: "inverse", inverse: true},
    {text: "   "},
  ];
  const stdout = new PassThrough(); stdout.isTTY = true; stdout.columns = 100; stdout.rows = 40;
  let output = ""; stdout.on("data", d => output += d);
  const h = React.createElement;
  const app = render(h(Static, {items: [{id: "styled", lines: [spans]}]}, b =>
    h(Box, {key: b.id}, h(Transform, {transform: L.inkText}, h(Text, null, ...spans.map((s, key) => h(Text, {key, color:s.color, backgroundColor:s.bg, bold:s.bold, underline:s.underline, inverse:s.inverse}, s.text)))))),
    {stdout, patchConsole: false, exitOnCtrlC: false});
  try {
    await new Promise(r => setTimeout(r, 80));
    const expected = historyOutput([{lines:[spans]}]);
    const {tokenize, styledCharsFromTokens} = await import("@alcalzone/ansi-tokenize");
    const cells = text => styledCharsFromTokens(tokenize(text)).filter(c => c.value !== "\n");
    assert.deepEqual(cells(expected), cells(output), "same visible cells and style state, allowing redundant SGR resets");
    assert.ok(!expected.includes("\x1b[9m"), "no unintended strike-through");

  } finally { app.unmount(); app.cleanup(); stdout.destroy(); }
});
