import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as L from "../layout.mjs";
import * as t3 from "../t3.mjs";
const fixture = JSON.parse(fs.readFileSync(new URL("./fixtures/questions.json", import.meta.url)));
const text = l => l.map(s => s.text).join("");
function active() {
  return t3.applyValue(null, {kind:"snapshot", snapshotSequence:1, projection:{
    thread:{id:"synthetic", title:"Synthetic thread"}, runs:[{id:"running", status:"running"}],
    runtimeRequests:[{id:fixture.requestId, kind:"user_input", status:"pending"}],
    turnItems:[{...fixture, runId:"running"}], visibleTurnItems:[{position:0,item:{...fixture,runId:"running"}}],
  }});
}
test("pending question does not duplicate the old timeline block and interrupt confirmation stays visible", () => {
  const f = L.frame({state:active(), cols:80, rows:24, tokens:{surface:"#333333",accent:"#abcdef"}, ui:{compactDialog:{allowed:true,text:"Interrupt the agent? y/n"}}});
  const strings = f.lines.map(text).join("\n");
  assert.match(strings, /Interrupt the agent\? y\/n/);
  assert.equal(strings.split("Which palette").length - 1, 1);
  assert.equal(strings.split("Which checks").length - 1, 0);
  assert.equal(strings.split("Anything else").length - 1, 0);
  assert.ok(f.lines.length < 24);
});
test("the original multiline composer stays usable, bounded and cursor-visible while a question is open", () => {
  const value = "line1\nline2\nline3\nline4\nline5\nline6\nlast line";
  for (const cols of [20,30,40,80,120]) {
    const f = L.frame({state:active(),cols,rows:24,ui:{editor:{value,cursor:value.length}}});
    assert.ok(f.lines.length < 24);
    assert.ok(f.lines.every(l => L.displayWidth(text(l)) <= cols));
    assert.ok(f.composer.flat().some(s => s.inverse));
    assert.match(f.composer.map(text).join("\n"), /line6/);
  }
});
