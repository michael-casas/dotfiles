// Real Ink + PTY, synthetic local T3 only. No hc, real threads or GUI.
import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import fs from "node:fs";
import { startFakeT3 } from "./support/fake-t3.mjs";
import * as S from "./support/synthetic-thread.mjs";
import * as C from "../control.mjs";
const here = p => fileURLToPath(new URL(p, import.meta.url));
const delay = ms => new Promise(r => setTimeout(r, ms));

test("overlay-aware dismiss has a bounded correlated private wire at every split", () => {
  const seq = "\x1b[>777;7;42u";
  for (let i = 0; i <= seq.length; i++) {
    const a = C.decode(seq.slice(0, i));
    const b = C.decode(seq.slice(i), a.state);
    assert.deepEqual([...a.events, ...b.events], [{type: "action", action: "escape", requestId: 42}]);
  }
  for (const bad of ["0", "-1", "1.2", "999999999999999999999", "bad"]) {
    assert.deepEqual(C.decode(`\x1b[>777;7;${bad}u`).events, []);
  }
});

test("filtered input preserves escape correlation without leaking composer bytes", async () => {
  const { PassThrough } = await import("node:stream");
  const { createControlInput } = await import("../control-input.mjs");
  const source = new PassThrough(), bridge = createControlInput(source);
  const actions = []; let text = "";
  bridge.stdin.on("data", data => text += data);
  bridge.onAction((action, requestId) => actions.push({action, requestId}));
  bridge.start();
  source.write("draft\x1b[>777;7;42u!");
  bridge.close();
  assert.equal(text, "draft!");
  assert.deepEqual(actions, [{action: "escape", requestId: 42}]);
});

for (const overlay of ["none", "slash", "skill", "model", "interrupt", "compact", "question"]) {
  test(`real TUI: ${overlay} overlay is acknowledged at dismiss time, never stops or answers`, async () => {
    const initial = S.snapshot();
    if (overlay === "question") {
      const card = JSON.parse(fs.readFileSync(here("./fixtures/questions.json")));
      initial.projection.runtimeRequests = [{id: card.requestId, kind: "user_input", status: "pending", responseCapability: {type: "resumable"}}];
      initial.projection.turnItems.push(card);
      initial.projection.visibleTurnItems.push({position: 99, item: card});
    }
    initial.projection.thread.modelSelection = {instanceId: "synthetic", model: "test-model"};
    const fake = await startFakeT3({initial: [initial], config: {providers: [{
      instanceId: "synthetic", enabled: true, status: "ready",
      models: [{slug: "test-model", name: "Synthetic model"}],
      slashCommands: [{name: "compact", description: "Compact"}],
      skills: [{name: "synthetic-skill", description: "Synthetic skill"}],
    }]}});
    const child = spawn("python3", [here("./support/pty-run.py"), "47", "160", "--", process.execPath, here("../main.mjs"), S.THREAD_ID], {
      env: {...process.env, T3_URL: fake.url, T3_SESSION_TOKEN: "synthetic", TERM: "xterm-256color", CI: "0"},
      stdio: ["pipe", "pipe", "pipe"],
    });
    let output = "", exited = false;
    child.stdout.on("data", d => output += d.toString());
    child.stderr.on("data", d => output += d.toString());
    child.on("exit", () => exited = true);
    const input = text => child.stdin.write(`input ${Buffer.from(text).toString("hex")}\n`);
    async function until(predicate) {
      const end = Date.now() + 5000;
      while (!predicate()) {
        assert.ok(!exited && Date.now() < end, `TUI evidence timeout: ${JSON.stringify(output.slice(-300))}`);
        await delay(20);
      }
    }
    try {
      await until(() => output.includes(S.historyMarker(7)));
      await delay(100);
      if (overlay === "slash") input("/");
      if (overlay === "skill") input("$");
      if (overlay === "model") input(C.sequence("model"));
      if (overlay === "interrupt") input(C.sequence("interrupt"));
      if (overlay === "compact") input(C.sequence("compact"));
      if (overlay === "question") await until(() => output.includes("Which palette"));
      if (overlay === "model") await until(() => output.includes("Harness"));
      if (overlay === "interrupt") await until(() => output.includes("Nothing to interrupt"));
      if (overlay === "compact") await until(() => output.includes("Compact this thread?"));
      // Allow Ink to render the open view before sending the Esc request.
      await delay(100);
      input("\x1b[>777;7;41u");
      const ack = value => `\x1b]7502;envi-t3-escape=41;overlay=${value}\x1b\\`;
      await until(() => output.includes(ack(overlay === "none" ? 0 : 1)));
      input("\x1b[>777;7;42u");
      await until(() => output.includes("\x1b]7502;envi-t3-escape=42;overlay=0\x1b\\"));
      assert.equal(fake.commands.length, 0, "Esc never interrupts, compacts, sends or answers");
      if (overlay === "question") {
        const after = output.slice(output.indexOf(ack(1)));
        // A dismissed question is not answered; it can be shown again by re-entering INSERT.
        assert.ok(!after.includes("Which palette"), "question stays dismissed after Esc");
        const beforeResume = output.length;
        input(C.sequence("resume"));
        await until(() => output.slice(beforeResume).includes("Which palette"));
        assert.equal(fake.commands.length, 0, "revealing pending question never answers it");
      }
    } finally {
      if (!exited) {
        child.stdin.end();
        await new Promise(r => child.once("exit", r));
      }
      await fake.close();
    }
  });
}
