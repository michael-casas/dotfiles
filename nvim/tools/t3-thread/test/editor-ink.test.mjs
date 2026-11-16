import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import React from "react";
import { render, Text, useInput } from "ink";
import { editInput } from "../view.mjs";
import { createControlInput } from "../control-input.mjs";

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


for (const [name, bytes, value, cursor, expectedValue, expectedCursor] of [
  ["Option-Left CSI", "\x1b[1;3D", "one\ntwo/three tail", 14, "one\ntwo/three tail", 8],
  ["Option-Right CSI", "\x1b[1;3C", "one\ntwo/three tail", 7, "one\ntwo/three tail", 13],
  ["Up", "\x1b[A", "abc\ndef", 6, "abc\ndef", 2],
  ["Down", "\x1b[B", "abc\ndef", 2, "abc\ndef", 6],
  ["Ctrl-P", "\x10", "中x\nab", 5, "中x\nab", 1],
  ["Ctrl-N", "\x0e", "中x\nab", 1, "中x\nab", 5],
  ...["\x1b[H", "\x1bOH", "\x1b[1~", "\x1b[7~"].map(bytes => ["Home", bytes, "one\ntwo", 5, "one\ntwo", 4]),
  ...["\x1b[F", "\x1bOF", "\x1b[4~", "\x1b[8~"].map(bytes => ["End", bytes, "one\ntwo", 5, "one\ntwo", 7]),
  ["Ctrl-T", "\x14", "a🙂b", 3, "ab🙂", 4],
  // V1 measured Herdr -> envi terminal bytes. These paths were already GREEN;
  // keep them explicit so physical Cmd/Option aliases cannot regress silently.
  ["Herdr Cmd-Left (Ctrl-A)", "\x01", "one\ntwo\nlast", 6, "one\ntwo\nlast", 4],
  ["Herdr Cmd-Right (Ctrl-E)", "\x05", "one\ntwo\nlast", 6, "one\ntwo\nlast", 7],
  ["Herdr Cmd-Backspace (Ctrl-U)", "\x15", "one\ntwo suffix\nlast", 7, "one\n suffix\nlast", 4],
  ["Herdr Cmd-Backspace at line start", "\x15", "one\ntwo", 4, "onetwo", 3],
  ["Herdr Cmd-Backspace at draft start", "\x15", "one\ntwo", 0, "one\ntwo", 0],
  ["Herdr Option-Backspace (Ctrl-W)", "\x17", "one\ntwo/three  tail", 15, "one\ntail", 4],
  ["Herdr Option-Backspace at line start", "\x17", "one\ntwo", 4, "one\ntwo", 4],
  ["Herdr Option-Left (ESC b)", "\x1bb", "one\ntwo/three tail", 14, "one\ntwo/three tail", 8],
  ["Herdr Option-Right (ESC f)", "\x1bf", "one\ntwo/three tail", 7, "one\ntwo/three tail", 13],
  ["Herdr Option-Left at line start", "\x1bb", "one\ntwo", 4, "one\ntwo", 4],
  ["Herdr Option-Right at line end", "\x1bf", "one\ntwo", 3, "one\ntwo", 3],
  ["Herdr Shift-Left uses plain code-point motion", "\x1b[1;2D", "a🙂b", 3, "a🙂b", 1],
  ["Herdr Shift-Right uses plain code-point motion", "\x1b[1;2C", "a🙂b", 1, "a🙂b", 3],
]) test(`real Ink ${name} ${JSON.stringify(bytes)} edits without literal escape text`, async () => {
  const stdin = new PassThrough();
  stdin.isTTY = true; stdin.setRawMode = () => {}; stdin.ref = () => {}; stdin.unref = () => {};
  const stdout = new PassThrough(); stdout.columns = 80; stdout.rows = 24; stdout.resume();
  let editor = {value, cursor}, delivered;
  function App() {
    useInput((ch, key) => { editor = editInput(editor.value, editor.cursor, ch, key); delivered?.(); });
    return React.createElement(Text, null, "synthetic editor");
  }
  const bridge = createControlInput(stdin);
  const app = render(React.createElement(App), {stdin: bridge.stdin, stdout, patchConsole: false, exitOnCtrlC: false});
  bridge.start();
  try {
    await new Promise(resolve => setImmediate(resolve));
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(Error("Ink did not deliver key")), 2000);
      delivered = () => {clearTimeout(timeout); resolve();};
      stdin.write(bytes);
    });
    assert.deepEqual(editor, {value: expectedValue, cursor: expectedCursor});
  } finally { bridge.close(); app.unmount(); app.cleanup(); stdin.destroy(); bridge.stdin.destroy(); stdout.destroy(); }
});
