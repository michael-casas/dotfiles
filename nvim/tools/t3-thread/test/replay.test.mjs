import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { applyValue } from "../t3.mjs";
import { rows } from "../view.mjs";

// Complete, secret-checked capture; snapshot history stays intact during replay.
// Expectations follow /tmp/t3-ui-capture/notes.md, captures 03–05.
const frames = fs.readFileSync(new URL("./fixtures/turn.jsonl", import.meta.url), "utf8")
  .trim().split("\n").map(JSON.parse);
const replay = () => frames.reduce(
  (state, frame) => (frame.values || []).reduce(applyValue, state),
  null,
);
const prompt = "Example task: list the latest commits, read the readme and search for a symbol, then answer briefly.";
const answer = "Example answer: the latest commits are listed, there is no readme, and the symbol was not found.";
const capturedRows = (state, expanded) => {
  const all = rows(state, expanded);
  const start = all.findIndex((row) => row.kind === "user_message" && row.text === prompt);
  assert.notEqual(start, -1, "the captured prompt must remain in the folded projection");
  return all.slice(start);
};
const content = (list) => list.map(({ kind, text }) => ({ kind, text }));

test("recorded-shape turn replay folds to the agent prompt, Worked for 6.6s and final answer", () => {
  assert.equal(frames.length, 29);
  assert.equal(frames[0].values[0].kind, "snapshot");
  const state = replay();
  const folded = capturedRows(state);
  assert.deepEqual(content(folded), [
    { kind: "user_message", text: prompt },
    { kind: "turn", text: "Worked for 6.6s" },
    { kind: "assistant_message", text: answer },
  ]);
  assert.equal(folded[0].item.createdBy, "agent");
  assert.equal(folded[0].item.creationSource, "mcp");
  assert.equal(folded[1].expanded, false);
});

test("recorded-shape turn replay expands to the exact desktop work-group summary", () => {
  const state = replay();
  const turn = capturedRows(state).find((row) => row.kind === "turn");
  const open = capturedRows(state, new Set([turn.id]));
  assert.deepEqual(content(open), [
    { kind: "user_message", text: prompt },
    { kind: "turn", text: "Worked for 6.6s" },
    { kind: "group", text: "Ran 2 commands and read 1 file" },
    { kind: "assistant_message", text: answer },
  ]);
});

test("recorded-shape turn replay expands five work items in captured reasoning/git/read/grep/reasoning order", () => {
  const state = replay();
  const turn = capturedRows(state).find((row) => row.kind === "turn");
  const expanded = new Set([turn.id]);
  const group = capturedRows(state, expanded).find((row) => row.kind === "group");
  expanded.add(group.id);
  const open = capturedRows(state, expanded);
  const start = open.findIndex((row) => row.kind === "group") + 1;
  const items = open.slice(start, -1);
  assert.deepEqual(content(items), [
    {
      kind: "reasoning",
      text: "Example reasoning: run the three read-only steps together.",
    },
    { kind: "command_execution", text: "git log --oneline -3" },
    { kind: "dynamic_tool", text: "Read /projects/example/README.md" },
    { kind: "command_execution", text: "grep -rn 'ExampleSymbol' ./src" },
    {
      kind: "reasoning",
      text: "Example reasoning: the readme is missing and the search found nothing, so answer in two short sentences.",
    },
  ]);
  assert.deepEqual(content(open.slice(-1)), [
    { kind: "assistant_message", text: answer },
  ]);
});
