import test from "node:test";
import assert from "node:assert/strict";
import { editInput } from "../view.mjs";

const ctrl = (value, cursor, ch) => editInput(value, cursor, ch, { ctrl: true });
const alt = (value, cursor, ch) => editInput(value, cursor, ch, { meta: true });
const check = (actual, value, cursor) => assert.deepEqual(actual, { value, cursor });

test("Ctrl-U kills only the current logical line prefix, then the preceding newline", () => {
  check(ctrl("hello", 5, "u"), "", 0);
  check(ctrl("one\ntwo suffix\nlast", 7, "u"), "one\n suffix\nlast", 4);
  check(ctrl("one\n suffix\nlast", 4, "u"), "one suffix\nlast", 3);
  check(ctrl("one suffix\nlast", 3, "u"), " suffix\nlast", 0);
  check(ctrl("one\ntwo", 0, "u"), "one\ntwo", 0);
  check(ctrl("one\ntwo", 3, "u"), "\ntwo", 0);
  check(ctrl("", 0, "u"), "", 0);
});
test("Ctrl-A/E address logical rather than wrapped or whole-draft lines", () => {
  for (const [cursor, start, end] of [[0,0,3], [2,0,3], [3,0,3], [4,4,7], [5,4,7], [7,4,7]]) {
    check(ctrl("one\ntwo", cursor, "a"), "one\ntwo", start);
    check(ctrl("one\ntwo", cursor, "e"), "one\ntwo", end);
  }
  check(ctrl("a\n\nb", 2, "e"), "a\n\nb", 2);
});
test("Ctrl-B/F move by Unicode character and clamp at draft edges", () => {
  check(ctrl("a🙂b", 3, "b"), "a🙂b", 1);
  check(ctrl("a🙂b", 1, "f"), "a🙂b", 3);
  check(ctrl("one\ntwo", 4, "b"), "one\ntwo", 3);
  check(ctrl("one\ntwo", 3, "f"), "one\ntwo", 4);
  check(ctrl("x", 0, "b"), "x", 0);
  check(ctrl("x", 1, "f"), "x", 1);
});
test("Ctrl-K kills a line suffix or the newline at its end", () => {
  check(ctrl("one\ntwo\nlast", 5, "k"), "one\nt\nlast", 5);
  check(ctrl("one\ntwo", 3, "k"), "onetwo", 3);
  check(ctrl("one\ntwo", 7, "k"), "one\ntwo", 7);
  check(ctrl("\n\n", 0, "k"), "\n", 0);
});
test("Ctrl-W and Option-Backspace kill a whitespace-delimited word without crossing a line", () => {
  for (const key of [{ ctrl: true }, { meta: true, delete: true }, { meta: true, backspace: true }]) {
    const ch = key.ctrl ? "w" : "";
    check(editInput("one\ntwo/three  tail", 15, ch, key), "one\ntail", 4);
    check(editInput("one\ntwo", 4, ch, key), "one\ntwo", 4);
    check(editInput("one\n  two", 6, ch, key), "one\ntwo", 4);
    check(editInput("", 0, ch, key), "", 0);
  }
});
test("Alt-B/F skip punctuation and move over letter/number words within a logical line", () => {
  check(alt("one\ntwo/three  tail", 15, "b"), "one\ntwo/three  tail", 8);
  check(alt("one\ntwo/three  tail", 7, "f"), "one\ntwo/three  tail", 13);
  check(alt("one\ntwo", 4, "b"), "one\ntwo", 4);
  check(alt("one\ntwo", 3, "f"), "one\ntwo", 3);
  check(alt("été 中文", 6, "b"), "été 中文", 4);
  check(alt("été 中文", 0, "f"), "été 中文", 3);
});
test("Ctrl-D deletes forward; Ctrl-H and Ink DEL still backspace without splitting Unicode", () => {
  check(ctrl("a🙂b", 1, "d"), "ab", 1);
  check(ctrl("a🙂b", 3, "h"), "ab", 1);
  check(editInput("a🙂b", 3, "", { backspace: true }), "ab", 1);
  check(editInput("a🙂b", 3, "", { delete: true }), "ab", 1);
  check(ctrl("one\ntwo", 3, "d"), "onetwo", 3);
  check(ctrl("one\ntwo", 4, "h"), "onetwo", 3);
  check(ctrl("a", 1, "d"), "a", 1);
  check(ctrl("a", 0, "h"), "a", 0);
});
test("Ctrl-Y yanks the last nonempty kill; ordinary edits and empty kills preserve it", () => {
  ctrl("keep\nthis", 4, "u");
  check(ctrl("a\nb", 2, "y"), "a\nkeepb", 6);
  ctrl("", 0, "k");
  ctrl("", 0, "u");
  ctrl("", 0, "w");
  editInput("a", 1, "!", {});
  ctrl("ab", 1, "d");
  ctrl("ab", 1, "h");
  check(ctrl("", 0, "y"), "keep", 4);
  ctrl("a\nb", 1, "k");
  check(ctrl("", 0, "y"), "\n", 1);
  ctrl("new word", 8, "w");
  check(ctrl("", 0, "y"), "word", 4);
});
test("unowned controls, menu motions and navigation never insert literal letters", () => {
  for (const ch of ["c", "o", "q", "p", "n", "z"])
    check(ctrl("draft", 3, ch), "draft", 3);
  for (const key of [{ return: true }, { escape: true }, { tab: true }, { pageUp: true }, { pageDown: true }, { upArrow: true }, { downArrow: true }])
    check(editInput("draft", 3, "", key), "draft", 3);
  check(alt("draft", 3, "x"), "draft", 3);
  check(editInput("ab", 1, "x\r\ny\u001b\u0003", {}), "ax\nyb", 4);
});

test("line-start controls handle a draft beginning with a newline at cursor zero", () => {
  check(ctrl("\nnext", 0, "a"), "\nnext", 0);
  check(ctrl("\nnext", 0, "u"), "\nnext", 0);
  check(ctrl("\nnext", 0, "w"), "\nnext", 0);
  check(alt("\nnext", 0, "b"), "\nnext", 0);
});

test("approval letter shortcuts must not swallow Ctrl-Y yank with an empty composer", async () => {
  const { readFileSync } = await import("node:fs");
  const main = readFileSync(new URL("../main.mjs", import.meta.url), "utf8");
  assert.match(main, /request\s*&&\s*!userInput\s*&&\s*!key\.ctrl\s*&&\s*!key\.meta\s*&&\s*\["y", "a", "n"\]/);
});
