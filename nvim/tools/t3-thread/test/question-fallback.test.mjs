import test from "node:test";
import assert from "node:assert/strict";
import {questionLines} from "../layout.mjs";
test("ANSI fallback keeps selected option distinguishable in full and compact bubbles", () => {
  const card={questions:[{id:"q",question:"Choose one",options:[{label:"First"},{label:"Second"}],allowCustomAnswer:false}]};
  for (const maxRows of [5,10]) {
    const lines=questionLines({id:"r"},card,30,{}, {}, maxRows);
    assert.ok(lines.flat().some(s=>s.inverse && s.text.includes("First")));
    assert.ok(lines.length<=maxRows);
    if(maxRows===10) assert.ok(lines.some(l=>l.map(s=>s.text).join("").includes("│")));
  }
});
