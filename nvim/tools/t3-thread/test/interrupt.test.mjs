import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as C from "../control.mjs";
import * as t3 from "../t3.mjs";
const active={threadId:"t",conn:"live",working:true,busy:false};

test("interrupt confirmation requires active/y and consumes its dialog before one dispatch",()=>{
  let dialog=C.interrupt(null,"open",active).dialog;
  assert.equal(dialog.text,"Interrupt the agent? y/n");
  let dispatches=0;
  for(const answer of ["yes","yes"]){const r=C.interrupt(dialog,answer,active);dialog=r.dialog;if(r.stop)dispatches++;}
  assert.equal(dispatches,1);
  assert.equal(t3.stopCommand("t","r",{threadStop:true}).type,"thread.stop");
  assert.equal(t3.stopCommand("t","r",{}).type,"run.interrupt");
});
test("n, other and Esc cancel interrupt; idle and ended-before-y never stop",()=>{
  const opened=C.interrupt(null,"open",active).dialog;
  for(const answer of ["cancel","n","other","escape",undefined]) assert.equal(C.interrupt(opened,answer,active).stop,undefined);
  const idle={...active,working:false};
  const notice=C.interrupt(null,"open",idle).dialog;
  assert.match(notice.text,/Nothing to interrupt/);
  assert.equal(C.interrupt(notice,"yes",active).stop,undefined);
  const ended=C.interrupt(opened,"yes",idle);
  assert.equal(ended.stop,undefined);assert.match(ended.dialog.text,/Nothing to interrupt/);
  for(const context of [{...active,conn:"reconnecting"},{...active,busy:true}])assert.equal(C.interrupt(opened,"yes",context).stop,undefined);
});
test("private interrupt action5 decodes at every boundary with no composer bytes",()=>{
  assert.equal(C.sequence("interrupt"),"\x1b[>777;5u");
  const seq=C.sequence("interrupt");
  for(let i=0;i<=seq.length;i++){
    const a=C.decode(seq.slice(0,i));const b=C.decode(seq.slice(i),a.state);
    assert.deepEqual([...a.events,...b.events],[{type:"action",action:"interrupt"}]);
  }
});
test("Ink Ctrl-C exit is disabled; Esc remains dismiss-only, stop belongs to confirmed interrupt",()=>{
  const main=fs.readFileSync(new URL("../main.mjs",import.meta.url),"utf8");
  assert.match(main,/exitOnCtrlC:\s*false/);
  assert.match(main,/if \(result\.stop\)/);
  assert.equal(C.escapeAction({working:true}),"ignore");
  assert.equal(C.escapeAction({model:true,working:true}),"close-model");
  assert.ok(!/key\.escape[^\n]*working/.test(main));
});
