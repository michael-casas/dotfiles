import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import { historyStdout } from "../history-stdout.mjs";
import { CLEAR_HISTORY } from "../history-output.mjs";
import * as L from "../layout.mjs";

test("H1-r1: stdout recovery inserts history before the live frame and acknowledges after the write callback", async () => {
  const stdout = new PassThrough(); stdout.columns=100; stdout.rows=8;
  const terminal = historyStdout(stdout);
  let output=""; stdout.on("data", d=>output+=d);
  let calls=0, flushed=0;
  const off=terminal.onClear(()=>{calls++; return {output:"HISTORY\n",flushed:()=>{flushed++;assert.ok(output.endsWith("LIVE"));}};});
  terminal.stream.write(CLEAR_HISTORY+"LIVE");
  assert.equal(output,CLEAR_HISTORY+"HISTORY\nLIVE");
  await new Promise(r=>setImmediate(r));
  assert.equal(flushed,1);
  terminal.historyWrite(text=>terminal.stream.write(text),CLEAR_HISTORY+"PLANNED_HISTORY\n");
  terminal.stream.write("ordinary live update");
  assert.equal(calls,1,"planned rebuild and ordinary writes never trigger recovery");
  off(); terminal.stream.write(CLEAR_HISTORY+"no active thread");
  assert.equal(calls,1,"unmount releases history handler");
  assert.equal(terminal.stream.rows,8);
  stdout.rows=12; assert.equal(terminal.stream.rows,12,"dimensions are never cached");
});

test("H1-r1: every tiny frame stays below terminal height and keeps its bottom status", () => {
  for (const rows of [1,2,3,4,5,6,8,12,24]) {
    const f=L.frame({cols:80,rows,ui:{editor:{value:"one\ntwo\nthree\nfour\nfive\nsix",cursor:27},flash:"STATUS_VISIBLE"}});
    assert.ok(f.innerLines.length<rows,`frame ${f.innerLines.length} < ${rows}`);
    if(f.innerLines.length) assert.ok(L.lineText(f.innerLines.at(-1)).includes("STATUS_VISIBLE"));
  }
});


test("H1-r1: tiny panes retain the editable composer row beside status when two rows fit", () => {
  for (const rows of [4,5,6]) {
    const f=L.frame({cols:80,rows,ui:{editor:{value:"DRAFT_VISIBLE",cursor:13},flash:"STATUS_VISIBLE"}});
    assert.ok(f.innerLines.map(L.lineText).join("\n").includes("DRAFT_VISIBLE"), `composer visible at ${rows} rows`);
    assert.ok(L.lineText(f.innerLines.at(-1)).includes("STATUS_VISIBLE"));
  }
});
