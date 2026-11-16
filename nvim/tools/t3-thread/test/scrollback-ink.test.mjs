import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import React from "react";
import { render, Static, Box, Text } from "ink";
import * as L from "../layout.mjs";
import { append, ledger } from "../scrollback.mjs";
const h = React.createElement;
const frame = () => new Promise(resolve => setTimeout(resolve, 70));

test("real Ink Static emits history once across repaint/resize and appends above capped live region", async () => {
  const stdout = new PassThrough();
  stdout.isTTY = true;
  stdout.columns = 80;
  stdout.rows = 24;
  let output = "";
  stdout.on("data", data => output += data);
  const block = (id,text) => ({id,rows:[{id,kind:"assistant_message",text}]});
  const freeze = b => ({...b,lines:L.historyLines(b,stdout.columns)});
  let book = append(ledger(),[block("a","UNIQUE_STATIC_FIRST")],freeze);
  function App({book, tick}) {
    const f = L.frame({cols:stdout.columns,rows:stdout.rows,ui:{flash:`tick ${tick}`}});
    return h(React.Fragment,null,
      h(Static,{items:book.items}, b => h(Box,{key:b.id,flexDirection:"column"},...b.lines.map((l,key)=>h(Text,{key},l.map(s=>s.text).join(""))))),
      h(Box,{flexDirection:"column"},...f.lines.map((l,key)=>h(Text,{key},l.map(s=>s.text).join("")))),
    );
  }
  const app = render(h(App,{book,tick:0}),{stdout,patchConsole:false,exitOnCtrlC:false});
  try {
    await frame();
    app.rerender(h(App,{book,tick:1}));
    await frame();
    stdout.columns=100;stdout.emit("resize");
    app.rerender(h(App,{book,tick:2}));
    await frame();
    book=append(book,[block("a","UNIQUE_STATIC_FIRST"),block("b","UNIQUE_STATIC_SECOND")],freeze);
    app.rerender(h(App,{book,tick:3}));
    await frame();
    assert.equal(output.split("UNIQUE_STATIC_FIRST").length-1,1);
    assert.equal(output.split("UNIQUE_STATIC_SECOND").length-1,1);
    assert.ok(!output.includes("\x1b[2J"),"never clears/replays whole terminal");
    assert.ok(!output.includes("\x1b[?1049"),"no alternate screen");
    assert.ok(!output.includes("\x1b[?100"),"no mouse tracking");
    assert.equal(book.items[0].lines[0].map(s=>s.text).join("").length,80,"old width frozen");
  } finally { app.unmount();app.cleanup();stdout.destroy(); }
});
