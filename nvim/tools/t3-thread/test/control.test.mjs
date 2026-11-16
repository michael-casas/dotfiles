import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import fs from "node:fs";
import * as L from "../layout.mjs";
const C = await import("../control.mjs").catch(e => {if(e.code !== "ERR_MODULE_NOT_FOUND") throw e;return {};});
const I = await import("../control-input.mjs").catch(e => {if(e.code !== "ERR_MODULE_NOT_FOUND") throw e;return {};});
const ready = {threadId:"t",conn:"live",working:false,busy:false,compactAvailable:true};

test("private controls parse in order at every split without contaminating ordinary input",()=>{
  const input = "draft"+C.sequence("model")+"!"+C.sequence("compact")+C.sequence("yes")+C.sequence("cancel")+"\x1b[A";
  const expected=[{type:"text",text:"draft"},{type:"action",action:"model"},{type:"text",text:"!"},{type:"action",action:"compact"},{type:"action",action:"yes"},{type:"action",action:"cancel"},{type:"text",text:"\x1b[A"}];
  assert.deepEqual(C.decode(input).events,expected);
  for(let split=0;split<=input.length;split++) {
    const a=C.decode(input.slice(0,split));const b=C.decode(input.slice(split),a.state);
    assert.equal([...a.events,...b.events].filter(e=>e.type==="text").map(e=>e.text).join(""),"draft!\x1b[A");
    assert.deepEqual([...a.events,...b.events].filter(e=>e.type==="action").map(e=>e.action),["model","compact","yes","cancel"]);
  }
  let state,events=[];
  for(const ch of input){const r=C.decode(ch,state);state=r.state;events.push(...r.events);}
  assert.equal(events.filter(e=>e.type==="text").map(e=>e.text).join(""),"draft!\x1b[A");
});
test("private unknown, malformed, partial and oversized reports are bounded and never printable",()=>{
  for(const sequence of ["\x1b[>777;99u","\x1b[>777;bad!u","\x1b[>777;"+"9".repeat(200)+"u"]){
    const r=C.decode("before"+sequence+"after");
    assert.equal(r.events.filter(e=>e.type==="text").map(e=>e.text).join(""),"beforeafter");
    assert.ok(!r.events.some(e=>e.type==="action"));
  }
  const p=C.decode("\x1b[>777;"+"1".repeat(200));
  assert.ok(p.state.pending.length<=32);
  assert.equal(C.flush(p.state),"");
  assert.equal(C.flush(C.decode("\x1b").state),"\x1b");
  assert.equal(C.flush(C.decode("\x1b[").state),"\x1b[");
});
test("filtered public Ink stdin delegates raw mode and removes only private controls",async()=>{
  const source=new PassThrough();source.isTTY=true;const raw=[];source.setRawMode=x=>raw.push(x);
  const bridge=I.createControlInput(source);const actions=[];let text="";
  bridge.stdin.on("data",s=>text+=s);bridge.onAction(a=>actions.push(a));bridge.start();bridge.start();bridge.stdin.setRawMode(true);
  const seq=C.sequence("model");source.write(seq.slice(0,4));source.write(seq.slice(4)+"my draft");
  source.write("\x1b");await new Promise(r=>setTimeout(r,80));
  assert.equal(text,"my draft\x1b");assert.deepEqual(actions,["model"]);assert.deepEqual(raw,[true]);
  bridge.close();bridge.close();assert.equal(source.listenerCount("data"),0);
});
test("filtered stdin preserves multibyte prompt text split between UTF-8 bytes",()=>{
  const source=new PassThrough();const bridge=I.createControlInput(source);let text="";
  bridge.stdin.on("data",s=>text+=s);bridge.start();
  for(const byte of Buffer.from("中文🙂 draft")) source.write(Buffer.from([byte]));
  assert.equal(text,"中文🙂 draft");bridge.close();
});

test("compact dialog y sends only the existing /compact path; n/other cancel and busy cannot send",()=>{
  const opened=C.compact(null,"open",ready);
  assert.match(opened.dialog.text,/Compact this thread\? y\/n/);
  assert.equal(C.compact(opened.dialog,"yes",ready).send,"/compact");
  for(const answer of ["cancel","n","other",undefined]){
    const r=C.compact(opened.dialog,answer,ready);assert.equal(r.dialog,null);assert.equal(r.send,undefined);
  }
  for(const context of [{...ready,working:true},{...ready,busy:true},{...ready,conn:"reconnecting"},{...ready,compactAvailable:false},{...ready,threadId:null}]){
    const blocked=C.compact(null,"open",context);assert.equal(blocked.dialog.allowed,false);assert.match(blocked.dialog.text,/Cannot compact/);
    assert.equal(C.compact(blocked.dialog,"yes",context).send,undefined);
  }
  assert.equal(C.compact(opened.dialog,"yes",{...ready,working:true}).send,undefined,"recheck busy at confirmation");
  assert.equal(C.compact(null,"yes",ready).send,undefined,"unsolicited answers do nothing");
});
test("Esc only dismisses transient views, never interrupts even with an empty running composer",()=>{
  assert.equal(C.escapeAction({model:true,menu:true,working:true}),"close-model");
  assert.equal(C.escapeAction({menu:true,working:true}),"close-menu");
  assert.equal(C.escapeAction({working:true,editor:""}),"ignore");
  const main=fs.readFileSync(new URL("../main.mjs",import.meta.url),"utf8");
  assert.match(main,/if \(result\.stop\)/,"only a confirmed dialog may stop");
  assert.ok(!/key\.escape[^\n]*working/.test(main));
});
test("compact confirmation lives above composer within the capped dynamic region",()=>{
  const dialog={allowed:true,text:"Compact this thread? y/n"};
  const f=L.frame({cols:80,rows:24,ui:{compactDialog:dialog,editor:{value:"KEPT_DRAFT",cursor:10}}});
  const text=f.lines.map(l=>l.map(s=>s.text).join(""));
  assert.ok(text.findIndex(l=>l.includes(dialog.text))>=0);
  assert.ok(text.findIndex(l=>l.includes(dialog.text))<text.findIndex(l=>l.includes("KEPT_DRAFT")));
  assert.ok(f.lines.length<24);
});
test("dismiss is a private control (Esc replacement) and decodes as an action",()=>{
  assert.equal(C.sequence("dismiss"),"\x1b[>777;6u");
  const r=C.decode("a\x1b[>777;6ub");
  assert.deepEqual(r.events.filter(e=>e.type==="action").map(e=>e.action),["dismiss"]);
  assert.equal(r.events.filter(e=>e.type==="text").map(e=>e.text).join(""),"ab");
});
