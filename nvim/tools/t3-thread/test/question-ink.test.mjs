// Real main.mjs, Ink stdin, PTY and local synthetic websocket boundary.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import {spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import {startFakeT3} from "./support/fake-t3.mjs";
const fixture = JSON.parse(fs.readFileSync(new URL("./fixtures/questions.json", import.meta.url)));
const here = p => fileURLToPath(new URL(p, import.meta.url));
const delay = ms => new Promise(r => setTimeout(r, ms));
function snapshot(card, seq = 1, status = "pending", kind = "user_input", capability = {type:"resumable"}) {
  return {kind:"snapshot", snapshotSequence:seq, projection:{
    thread:{id:"synthetic-question", title:"Synthetic question"}, runs:[],
    runtimeRequests:[{id:card.requestId, kind, status, responseCapability:capability}],
    turnItems:[card], visibleTurnItems:[{item:card, position:0}],
  }};
}
async function client(card = fixture, kind, capability) {
  const fake = await startFakeT3({initial:[snapshot(card, 1, "pending", kind, capability)]});
  const child = spawn("python3", [here("./support/pty-run.py"), "30", "120", "--", process.execPath, here("../main.mjs"), "synthetic-question"], {
    env:{...process.env, CI:"0", T3_URL:fake.url, T3_SESSION_TOKEN:"synthetic", FORCE_COLOR:"3"}, stdio:["pipe","pipe","pipe"],
  });
  let raw = ""; child.stdout.on("data", d => raw += d.toString());
  child.stderr.on("data", d => raw += d.toString());
  const c = {
    fake,
    text: () => raw,
    async until(predicate) { const end = Date.now()+8000; while (!predicate()) { if(Date.now()>end) throw Error(`Timeout: ${raw.slice(-600)}`); await delay(20); } },
    async press(bytes) { child.stdin.write(`input ${Buffer.from(bytes).toString("hex")}\n`); await delay(80); },
    async resize(rows, cols) { child.stdin.write(`resize ${rows} ${cols}\n`); await delay(150); },
    async close() { child.stdin.end(); await new Promise(r => child.once("exit",r)); await fake.close(); },
  };
  await c.until(() => raw.includes("Synthetic question"));
  return c;
}
test("real Ink collects single, multi and custom answers into one final unchanged response; dismiss never stops", async () => {
  const c = await client();
  try {
    await c.until(() => c.text().includes("Type your answer"));
    await c.press("\x1b"); await c.press("\x1b[>777;6u");
    assert.deepEqual(c.fake.commands, []);
    await c.press("\x1b[B"); await c.press("\r"); // Forest
    await c.until(() => c.text().includes("Which checks"));
    assert.deepEqual(c.fake.commands, []);
    await c.press(" "); await c.press("\x0e"); await c.press(" "); await c.press("\r");
    await c.until(() => c.text().includes("Anything else"));
    assert.deepEqual(c.fake.commands, []);
    await c.press("one word"); await c.press("\x17"); await c.press("\x19");
    await c.press("\x01"); await c.press("\x04"); // remove o; emacs still edits
    await c.press("\r");
    await c.until(() => c.fake.commands.length === 1);
    const [{type, requestId, answers}] = c.fake.commands;
    assert.equal(type, "runtime-request.respond");
    assert.equal(requestId, fixture.requestId);
    assert.deepEqual(answers, {color:"Forest", checks:["unit","integration"], note:"ne word"});
    c.fake.push([snapshot(fixture,2,"answered")]);
    await delay(150);
    await c.press("a normal prompt"); await c.press("\r");
    await c.until(() => c.fake.commands.length === 2);
    assert.equal(c.fake.commands[1].type, "message.dispatch");
  } finally { await c.close(); }
});
test("real Ink digit picks, Ctrl-P, literal numeric custom text and cannot-resume guard", async () => {
  const c = await client({...fixture, questions:[fixture.questions[0]]});
  try {
    await c.until(() => c.text().includes("Type your answer"));
    await c.press("2"); await c.press("\x10"); await c.press("\r");
    await c.until(() => c.fake.commands.length === 1);
    assert.deepEqual(c.fake.commands[0].answers, {color:"ocean"});
  } finally { await c.close(); }
  const custom = await client({...fixture, questions:[fixture.questions[0]]});
  try {
    await custom.until(() => custom.text().includes("Type your answer"));
    await custom.press("3"); // custom bubble
    await custom.press("2");
    await custom.press("\r"); await custom.press("\r");
    await custom.until(() => custom.fake.commands.length === 1);
    assert.deepEqual(custom.fake.commands[0].answers, {color:"2"});
    assert.equal(custom.fake.commands.length, 1, "duplicate Enter never resends the pending request");
  } finally { await custom.close(); }
  const locked = await client(fixture, "user_input", {type:"not_resumable", reason:"Original client required"});
  try {
    await locked.press("1"); await locked.press("\r");
    assert.deepEqual(locked.fake.commands, []);
    assert.match(locked.text(), /cannot resume in this client/);
  } finally { await locked.close(); }
});
for (const [key, decision] of [["y","accept"],["a","acceptForSession"],["n","decline"]]) test(`real Ink approval ${key} remains ${decision}`, async () => {
  const c = await client({...fixture, type:"approval_request", prompt:"Approve synthetic action?"}, "command");
  try {
    await c.press(key); await c.until(() => c.fake.commands.length === 1);
    assert.equal(c.fake.commands[0].decision, decision);
  } finally { await c.close(); }
});
test("real Ink pending list resize stays below screen height with one debounced width reflow", async () => {
  const card = {...fixture,questions:[{...fixture.questions[0],options:Array.from({length:30},(_,i)=>({label:`Long option ${i+1}`}))}]};
  const c = await client(card);
  try {
    await c.until(() => c.text().includes("Long option"));
    const offset=c.text().length;
    await c.resize(12,40);
    for(let i=0;i<12;i++) await c.press("\x1b[B");
    assert.match(c.text().slice(offset),/13 Long option 13/);
    const resized = c.text().slice(offset);
    assert.equal((resized.match(/\x1b\[3J/g) || []).length, 1, "one intentional history reflow after the width change");
    const afterReflow = resized.slice(resized.indexOf("\x1b[3J") + 4);
    assert.doesNotMatch(afterReflow,/\x1b\[(?:2J|3J)|\x1b\[(?:1;1)?H\x1b\[0?J/, "question navigation never clears again");
    const frames=[...c.text().slice(offset).matchAll(/(?:\x1b\[2K\x1b\[1A)*\x1b\[2K\x1b\[G/g)];
    const tail=c.text().slice(offset).slice(frames.at(-1).index+frames.at(-1)[0].length);
    assert.ok(tail.split("\n").length-1 < 12);
    await c.press("\r"); await c.until(()=>c.fake.commands.length===1);
    assert.deepEqual(c.fake.commands[0].answers,{color:"Long option 13"});
  } finally { await c.close(); }
});
