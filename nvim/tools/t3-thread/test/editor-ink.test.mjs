import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import React from "react";
import { render, Text, useInput } from "ink";
import { editInput } from "../view.mjs";

test("real Ink 5 input decodes control bytes, DEL, Ctrl-H and Option-Backspace for the editor", async () => {
  const stdin = new PassThrough();
  stdin.isTTY = true;
  stdin.setRawMode = () => {};
  stdin.ref = () => {};
  stdin.unref = () => {};
  const stdout = new PassThrough();
  stdout.columns = 80;
  stdout.rows = 24;
  stdout.resume();
  let editor = { value: "", cursor: 0 };
  let onKey;
  function App() {
    useInput((ch, key) => {
      editor = editInput(editor.value, editor.cursor, ch, key);
      onKey?.();
    });
    return React.createElement(Text, null, "editor test");
  }
  const app = render(React.createElement(App), { stdin, stdout, patchConsole: false, exitOnCtrlC: false });
  const press = (bytes) => new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Ink did not deliver input")), 2000);
    onKey = () => { clearTimeout(timeout); resolve(); };
    stdin.write(bytes);
  });
  try {
    await new Promise(resolve => setImmediate(resolve));
    for (const [bytes, value, cursor] of [
      ["one\ntwo words", "one\ntwo words", 13],
      ["\x15", "one\n", 4], // Ctrl-U
      ["\x19", "one\ntwo words", 13], // Ctrl-Y
      ["\x01", "one\ntwo words", 4],
      ["\x06", "one\ntwo words", 5],
      ["\x02", "one\ntwo words", 4],
      ["\x04", "one\nwo words", 4],
      ["\x05", "one\nwo words", 12],
      ["\x1bb", "one\nwo words", 7],
      ["\x1bf", "one\nwo words", 12],
      ["\x1b\x7f", "one\nwo ", 7],
      ["\x7f", "one\nwo", 6],
      ["\b", "one\nw", 5],
      ["\x17", "one\n", 4],
      ["\x01", "one\n", 4],
      ["\x0b", "one\n", 4],
    ]) {
      await press(bytes);
      assert.deepEqual(editor, { value, cursor }, JSON.stringify(bytes));
    }
  } finally {
    app.unmount();
    app.cleanup();
    stdin.destroy();
    stdout.destroy();
  }
});
