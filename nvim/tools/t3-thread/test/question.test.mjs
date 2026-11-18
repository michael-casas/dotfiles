import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as L from "../layout.mjs";
import * as t3 from "../t3.mjs";
const Q = await import("../question.mjs").catch(e => { if (e.code !== "ERR_MODULE_NOT_FOUND") throw e; return {}; });
export const fixture = JSON.parse(fs.readFileSync(new URL("./fixtures/questions.json", import.meta.url)));
const T = Object.fromEntries(["fg", "muted", "faint", "border", "surface", "accent", "accent_fg", "user_bubble", "attention"].map(x => [x, `token:${x}`]));
const text = l => l.map(s => s.text).join("");
function state(card = fixture, capability = {type: "resumable"}) {
  return t3.applyValue(null, { kind: "snapshot", snapshotSequence: 1, projection: {
    thread: {id: "synthetic", title: "Question demo"}, runs: [],
    runtimeRequests: [{id: card.requestId, kind: "user_input", status: "pending", responseCapability: capability}],
    turnItems: [card], visibleTurnItems: [{position: 0, item: card}],
  }});
}
for (const cols of [40, 80, 120, 160]) test(`question window at ${cols}: width, centering, directly above composer and separate bubbles`, () => {
  const f = L.frame({state: state(), cols, rows: 30, tokens: T});
  const strings = f.lines.map(text);
  const top = strings.findIndex(s => s.includes("Which palette"));
  assert.ok(top >= 0);
  const edge = strings[top - 1];
  const column = L.geometry(cols).column;
  const w = Math.min(column, Math.max(30, Math.round(column * .6)));
  assert.equal(edge.trim().length, w);
  assert.ok(w < column, "answer window remains narrower than the composer");
  assert.equal(edge.indexOf("▗"), Math.floor((cols - w) / 2));
  const bottom = strings.findLastIndex(s => s.trim() === "▝" + "▀".repeat(w - 2) + "▘");
  assert.ok(bottom >= top);
  assert.equal(strings[bottom + 1].trim(), text(f.composer[0]).trim());
  for (const label of ["1 Ocean", "2 Forest", "3 Type your answer…"]) assert.ok(strings.some(s => s.includes(label)), label);
  assert.ok(strings.some(s => s.includes("1/3")));
  assert.ok(f.lines.flat().some(s => s.bg === T.accent && s.text.includes("Ocean")));
  if (cols >= 80) assert.ok(f.lines.flat().some(s => s.color === T.muted && s.text.includes("Quiet green")));
  assert.ok(strings.every(s => L.displayWidth(s) <= cols));
});
test("question custom absence, multi check state, scrolling around selection, height and resolved/nonresumable requests", () => {
  const card = structuredClone(fixture);
  card.questions = [{...card.questions[1], options: Array.from({length: 25}, (_, i) => ({label: `Check ${i + 1}`}))}];
  for (const rows of [8, 12, 18, 24, 40]) {
    const f = L.frame({state: state(card), cols: 80, rows, tokens: T, ui: {questionSelection: {requestId: card.requestId, questionId: "checks", selected: 20, checked: [20]}}});
    const strings = f.lines.map(text).join("\n");
    assert.ok(f.lines.length < rows);
    if (rows >= 12) { assert.match(strings, /■ 21 Check 21/); assert.doesNotMatch(strings, /Type your answer/); }
    if (rows >= 18) { assert.match(strings, /□/); assert.doesNotMatch(strings, /1 Check 1\b/); }
  }
  const custom = L.frame({state: state(), tokens: T, ui: {questionSelection: {requestId: fixture.requestId, questionId: "color", selected: 2, checked: []}}});
  assert.ok(custom.lines.flat().some(s => s.bg === T.accent && s.text.includes("Type your answer")));
  const ended = state(); ended.runtimeRequests.get(fixture.requestId).status = "answered";
  assert.ok(!L.frame({state: ended, tokens: T}).lines.map(text).join("\n").includes("Type your answer"));
  assert.match(L.frame({state: state(fixture, {type: "not_resumable", reason: "Open original client"}), tokens: T}).lines.map(text).join("\n"), /cannot resume in this client/);
});
test("question keys: arrows/control motions, digits, multi toggles, custom editor and exact answer values", () => {
  assert.equal(typeof Q.input, "function");
  let selection;
  let editor = {value: "", cursor: 0};
  const q = fixture.questions[0];
  const press = (ch, key = {}, question = q) => {
    const result = Q.input(question, Q.selection(fixture.requestId, question, selection), editor, ch, key);
    selection = result.selection; editor = result.editor; return result;
  };
  assert.equal(press("", {downArrow: true}).selection.selected, 1);
  assert.equal(press("p", {ctrl: true}).selection.selected, 0);
  assert.equal(press("", {upArrow: true}).selection.selected, 2);
  assert.equal(press("n", {ctrl: true}).selection.selected, 0);
  assert.equal(press("2").selection.selected, 1);
  assert.equal(press("", {return: true}).answer, "Forest");
  assert.equal(press("hello").selection.selected, 2);
  press("a", {ctrl: true}); press("k", {ctrl: true}); press("y", {ctrl: true});
  assert.equal(editor.value, "hello");
  assert.equal(press("", {return: true}).answer, "hello");
  editor = {value: "2", cursor: 1};
  assert.equal(press("", {return: true}).answer, "2", "custom text is literal, not parsed as an option index");
  selection = undefined; editor = {value: "", cursor: 0};
  const multi = fixture.questions[1];
  press(" ", {}, multi); press("2", {}, multi);
  assert.deepEqual(press("", {return: true}, multi).answer, ["unit", "integration"]);
  press(" ", {}, multi);
  assert.deepEqual(press("", {return: true}, multi).answer, ["unit"]);
  press("1", {}, multi);
  assert.match(press("", {return: true}, multi).error, /Choose/);
  assert.equal(press("unexpected", {}, multi).editor.value, "");
  assert.equal(Q.selection("new-request", q, selection).selected, 0);
  assert.equal(Q.input(q, Q.selection("r", q, {requestId: "r", questionId: q.id, selected: 2}), {value: "", cursor: 0}, "", {return:true}).answer, undefined);
});

// REP fix-round contract: spend height on all compact options before scrolling.
for (const optionCount of [3, 4, 6, 9]) test(`160x47: ${optionCount} options plus custom all fit inside the unchanged 20-row live cap`, () => {
  const card = structuredClone(fixture);
  card.questions = [{id: "checks", question: "Which checks should run?", multiSelect: true,
    options: Array.from({length: optionCount}, (_, i) => ({label: `Check ${i + 1}`}))}];
  for (const selected of [0, optionCount - 1, optionCount]) {
    const f = L.frame({state: state(card), cols: 160, rows: 47, tokens: T,
      ui: {questionSelection: {requestId: card.requestId, questionId: "checks", selected, checked: [0]}}});
    const strings = f.lines.map(text);
    assert.equal(f.cap, 20);
    assert.ok(f.lines.length <= 20);
    for (let i = 0; i < optionCount; i++) {
      const label = `${i === 0 ? "■" : "□"} ${i + 1} Check ${i + 1}`;
      assert.ok(strings.some(s => s.includes(label)), `${label} visible with selection ${selected}`);
    }
    assert.ok(strings.some(s => s.includes(`${optionCount + 1} Type your answer…`)));
    const selectedLabel = selected === optionCount ? "Type your answer…" : `${selected + 1} Check ${selected + 1}`;
    assert.ok(f.lines.flat().some(s => s.bg === T.accent && s.text.includes(selectedLabel)), "accent focus remains visible");
    assert.ok(strings.some(s => s.includes("\ue0b6") && s.includes("\ue0b4")), "compact one-row bubbles are pills");
    // Pill caps take the bubble colour over the window surface.
    const rowsWithAnswers = f.lines.filter(l => /Check \d|Type your answer/.test(text(l)));
    const caps = rowsWithAnswers.flat().filter(s => s.text === "\ue0b6" || s.text === "\ue0b4");
    assert.ok(caps.length >= 2 * (optionCount + 1));
    assert.ok(caps.every(s => s.bg === T.surface && (s.color === T.accent || s.color === T.user_bubble)));
  }
});

test("checkbox glyphs share one cell width so labels line up", () => {
  assert.equal(L.displayWidth("■"), 1);
  assert.equal(L.displayWidth("□"), 1);
});

test("160x47: scrolling starts only after compact capacity is exceeded", () => {
  const card = structuredClone(fixture);
  card.questions = [{id: "checks", question: "Choose checks", multiSelect: true, allowCustomAnswer: false,
    options: Array.from({length: 20}, (_, i) => ({label: `Check ${i + 1}`}))}];
  const f = L.frame({state: state(card), cols: 160, rows: 47, tokens: T,
    ui: {questionSelection: {requestId: card.requestId, questionId: "checks", selected: 15, checked: [15]}}});
  const strings = f.lines.map(text);
  assert.equal(strings.filter(s => s.includes("Check ")).length, 11, "all eleven available option rows are used");
  assert.ok(strings.some(s => s.includes("■ 16 Check 16")));
  assert.ok(!strings.some(s => /1 Check 1\b/.test(s)));
  assert.ok(f.lines.length <= 20);
});
