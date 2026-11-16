import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as t3 from "../t3.mjs";
import * as L from "../layout.mjs";
const S = await import("../scrollback.mjs").catch(e => {
  if (e.code !== "ERR_MODULE_NOT_FOUND") throw e;
  return {};
});
const text = lines => lines.map(l => l.map(s => s.text).join("")).join("\n");
function snapshot(status = "completed") {
  const items = [
    {id:"u",type:"user_message",runId:"r",text:"PROMPT"},
    {id:"w",type:"command_execution",runId:"r",input:"pwd",output:"/tmp",status:"completed"},
    {id:"a",type:"assistant_message",runId:"r",text:"FINAL_ANSWER",streaming:status === "running"},
    {id:"notice",type:"system_notice",message:"NOTICE"},
  ];
  return t3.applyValue(null,{kind:"snapshot",snapshotSequence:1,projection:{
    thread:{id:"t",title:"Native history"},
    runs:[{id:"r",status,startedAt:"2026-01-01T00:00:00Z",completedAt:status === "running" ? null : "2026-01-01T00:00:02Z"}],
    turnItems:items,visibleTurnItems:items.map((item,position)=>({item,position})),
  }});
}
test("partition commits prompts/notices but keeps unfinished work and answer live", () => {
  const p = S.partition(snapshot("running"),new Set(),Date.parse("2026-01-01T00:00:03Z"));
  assert.deepEqual(p.committed.map(b=>b.id),["u","notice"]);
  assert.ok(p.live.some(r=>r.kind === "working"));
  assert.ok(p.live.some(r=>r.text === "FINAL_ANSWER"));
  const done = S.partition(snapshot());
  assert.equal(done.live.length,0);
  assert.deepEqual(done.committed.map(b=>b.id),["u","turn:r","a","notice"]);
  assert.match(done.committed.find(b=>b.id === "turn:r").rows[0].text,/Worked for 2s · Ran 1 command/);
});
test("startup dumps oldest first; snapshot resync/reconnect/theme changes never recommit ids", () => {
  const ledger = S.ledger();
  const render = b => ({...b, theme:"old"});
  const first = S.append(ledger,S.partition(snapshot()).committed,render);
  assert.deepEqual(first.items.map(i=>i.id),["u","turn:r","a","notice"]);
  assert.equal(ledger.items.length,0,"immutable ledger");
  const resync = S.append(first,S.partition(snapshot()).committed,b=>({...b,theme:"new"}));
  assert.equal(resync,first);
  const state = snapshot();
  state.turnItems.set("n",{id:"n",type:"system_notice",message:"new"});
  state.visibleTurnItems.push({item:state.turnItems.get("n"),position:99});
  const next = S.append(first,S.partition(state).committed,b=>({...b,theme:"new"}));
  assert.equal(next.items.filter(i=>i.id === "a").length,1);
  assert.equal(next.items[0].theme,"old");
  assert.equal(next.items.at(-1).theme,"new");
});
test("a streaming standalone answer is not committed until final",()=>{
  const s = snapshot();s.turnItems.get("a").runId = null;s.turnItems.get("a").streaming = true;
  assert.ok(!S.partition(s).committed.some(b=>b.id === "a"));
  s.turnItems.get("a").streaming = false;
  assert.ok(S.partition(s).committed.some(b=>b.id === "a"));
});
test("expanded work is an explicit new block, not a replay of prompts or final answers",()=>{
  assert.equal(S.expandedBlock(snapshot("running")),null);
  const block = S.expandedBlock(snapshot());
  assert.match(block.rows[0].text,/Expanded work/);
  assert.ok(block.rows.some(r=>r.item?.id === "w" && r.expanded));
  assert.ok(!block.rows.some(r=>["u","a"].includes(r.item?.id)));
  assert.match(text(L.timelineLines(block.rows,74)),/pwd[\s\S]*\/tmp/);
});
test("live frame is short when idle, capped below the window when streaming, and has no scroll view",()=>{
  const idle = L.frame({state:snapshot(),cols:80,rows:24});
  assert.ok(idle.lines.length < 12);
  assert.ok(!text(idle.lines).includes("FINAL_ANSWER"));
  assert.ok(text(idle.status ? [idle.status] : []).includes("Native history"));
  for(const rows of [12,24,40,120]) {
    const s = snapshot("running");s.turnItems.get("a").text = "LONG_STREAM\n".repeat(150);
    const f = L.frame({state:s,cols:80,rows,ui:{editor:{value:"x\n".repeat(12),cursor:24}}});
    assert.ok(f.lines.length < rows,`${f.lines.length} < ${rows}`);
    assert.ok(f.lines.length <= 24);
    assert.ok(!text(f.lines).includes("↓ latest"));
    assert.equal(f.maxScroll,undefined);
  }
});
test("expanded work keeps tools after commentary without reprinting assistant messages",()=>{
  const s=snapshot();
  const comment={id:"comment",type:"assistant_message",phase:"commentary",runId:"r",text:"checking now"};
  s.turnItems.set(comment.id,comment);
  s.visibleTurnItems.splice(1,0,{item:comment,position:0.5});
  assert.ok(S.expandedBlock(s).rows.some(r=>r.item?.id === "w"));
  assert.ok(!S.expandedBlock(s).rows.some(r=>r.item?.type === "assistant_message"));
});

test("answer-only finished turns get a summary and expansion never selects an older turn",()=>{
  const s = snapshot();
  const items = [
    {id:"u2",type:"user_message",runId:"r2",text:"second"},
    {id:"a2",type:"assistant_message",runId:"r2",text:"second answer"},
  ];
  s.runs.set("r2",{id:"r2",status:"completed",startedAt:"2026-01-01T00:00:03Z",completedAt:"2026-01-01T00:00:04Z"});
  for(const item of items) { s.turnItems.set(item.id,item);s.visibleTurnItems.push({item,position:s.visibleTurnItems.length}); }
  const blocks=S.partition(s).committed;
  assert.equal(blocks.filter(b=>b.id === "turn:r2").length,1);
  assert.match(blocks.find(b=>b.id === "turn:r2").rows[0].text,/Worked for 1s · No work recorded/);
  assert.match(S.expandedBlock(s).rows[0].text,/No work recorded/);
  assert.ok(!S.expandedBlock(s).rows.some(r=>r.item?.id === "w"));
});

test("active work groups from earlier attempts stay live, never committed early",()=>{
  const s=snapshot("running");
  s.turnItems.get("a").type="command_execution";s.turnItems.get("a").status="completed";s.turnItems.get("a").streaming=false;
  s.visibleTurnItems=s.visibleTurnItems.filter(r=>r.item.id !== "notice");
  const final={id:"preview",type:"assistant_message",phase:"commentary",runId:"r",text:"still going"};
  s.turnItems.set(final.id,final);s.visibleTurnItems.push({item:final,position:9});
  const p=S.partition(s);
  assert.ok(!p.committed.some(b=>b.id.startsWith("group:")));
  assert.ok(p.live.some(r=>r.kind === "group"));
});

test("29-frame replay commits every final row once, retaining folding and summary",()=>{
  const frames = fs.readFileSync(new URL("./fixtures/turn.jsonl",import.meta.url),"utf8").trim().split("\n").map(JSON.parse);
  let state, book=S.ledger();
  for(const frame of frames) for(const v of frame.values || []) {
    state=t3.applyValue(state,v);
    book=S.append(book,S.partition(state).committed,b=>b);
  }
  const ids=book.items.map(b=>b.id);
  assert.equal(ids.length,new Set(ids).size);
  assert.ok(book.items.some(b=>b.rows.some(r=>r.text.includes("Worked for 6.6s · Ran 2 commands and read 1 file"))));
  assert.equal(book.items.filter(b=>b.rows.some(r=>r.text.includes("Example answer: the latest commits"))).length,1);
});
