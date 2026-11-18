import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import * as C from "../commands.mjs";
import * as L from "../layout.mjs";

const text = (line) => line.map((s) => s.text).join("");
const providers = [
  {
    instanceId: "claudeAgent",
    slashCommands: [
      {
        name: "compact",
        description: "Summarize the conversation and reduce context usage",
        input: { hint: "<optional custom summarization instructions>" },
      },
      { name: "clear", description: "Clear conversation history" },
      { name: "context", description: "Show context usage" },
      { name: "codex:review", description: "Ask Codex to review" },
      { name: "audit" },
    ],
    skills: [
      { name: "audit", description: "Run the purity review", path: "/a", enabled: true },
      { name: "caveman", shortDescription: "Talk like caveman", path: "/c", enabled: true },
      { name: "hidden", description: "agent only", path: "/h", enabled: true, userInvocable: false },
      { name: "off", description: "disabled", path: "/o", enabled: false },
      { name: "audit", description: "duplicate", path: "/a2", enabled: true },
    ],
    workspaceSnapshots: [
      {
        cwd: "/repo",
        slashCommands: [{ name: "compact" }, { name: "repo-only" }],
        skills: [{ name: "repo-skill", path: "/r", enabled: true }],
      },
    ],
  },
  { instanceId: "codex", slashCommands: [{ name: "goal" }], skills: [] },
];
const cat = C.catalog(providers, "claudeAgent", "/elsewhere");

test("detectTrigger finds / and $ tokens at the cursor", () => {
  assert.deepEqual(C.detectTrigger("/comp"), {
    kind: "slash",
    query: "comp",
    start: 0,
    end: 5,
  });
  assert.deepEqual(C.detectTrigger("use $cav"), {
    kind: "skill",
    query: "cav",
    start: 4,
    end: 8,
  });
  assert.equal(C.detectTrigger("/usr/bin"), null, "paths are not commands");
  assert.equal(C.detectTrigger("costs $10k"), null, "amounts are not skills");
  assert.equal(C.detectTrigger("plain words"), null);
  assert.equal(C.detectTrigger("/compact ", 9), null, "a finished token closes the menu");
  assert.equal(C.detectTrigger("/compact now", 3).query, "co", "cursor bounds the token");
});

test("catalog prefers the folder snapshot, then the machine lists", () => {
  assert.equal(cat.hasSnapshot, false);
  assert.equal(cat.slashCommands.length, 5);
  const repo = C.catalog(providers, "claudeAgent", "/repo");
  assert.equal(repo.hasSnapshot, true);
  assert.deepEqual(
    repo.slashCommands.map((c) => c.name),
    ["compact", "repo-only"],
  );
  assert.equal(C.catalog(providers, "missing", "/repo"), null);
  assert.equal(C.catalog(null, "claudeAgent", "/repo"), null);
});

test("mergeProviders keeps folder snapshots across replies", () => {
  const merged = C.mergeProviders(providers, [
    {
      instanceId: "claudeAgent",
      slashCommands: [],
      skills: [],
      workspaceSnapshots: [{ cwd: "/new", slashCommands: [], skills: [] }],
    },
  ]);
  assert.deepEqual(
    merged[0].workspaceSnapshots.map((s) => s.cwd).sort(),
    ["/new", "/repo"],
  );
});

test("slash menu ranks like the desktop and gates /compact and /clear", () => {
  const m = C.menu("/comp", 5, cat);
  assert.equal(m.items[0].label, "/compact");
  assert.equal(m.items[0].insert, "/compact ");
  assert.ok(m.items.every((i) => i.label !== "/clear"), "provider /clear hidden");
  assert.equal(C.menu("/co", 3, cat).items[0].label, "/compact", "prefix beats boundary");
  assert.ok(
    C.menu("/rev", 4, cat).items.some((i) => i.label === "/codex:review"),
    "boundary match after ':'",
  );
  const all = C.menu("/", 1, cat);
  assert.equal(all.items.length, 5, "empty query lists provider commands and built-in /model");
  assert.ok(
    !C.menu("/comp", 5, cat, { working: true }).items.some((i) => i.label === "/compact"),
    "no /compact while working",
  );
  assert.ok(
    !C.menu("/comp later", 5, cat).items.some((i) => i.label === "/compact"),
    "no /compact with other text",
  );
  assert.equal(C.menu("say /comp", 9, cat), null, "commands only at message start");
  assert.equal(C.menu("/zzzz", 5, cat).empty, "No matching command.");
  assert.equal(C.menu("/co", 3, null).empty, "Loading commands…");
});

test("skill menu filters disabled, agent-only and duplicate skills", () => {
  const m = C.menu("$", 1, cat);
  assert.deepEqual(
    m.items.map((i) => i.label),
    ["$audit", "$caveman"],
  );
  const c = C.menu("try $talk", 9, cat);
  assert.equal(c.items[0].insert, "$caveman ", "description matches, mid-message");
  assert.equal(C.menu("$nope", 5, cat).items.length, 0);
});

test("accept replaces the token and isComplete spots a typed command", () => {
  const trigger = C.detectTrigger("/comp", 5);
  const item = C.menu("/comp", 5, cat).items[0];
  assert.deepEqual(C.accept("/comp", trigger, item), {
    value: "/compact ",
    cursor: 9,
  });
  const mid = C.detectTrigger("use $cav now", 8);
  assert.deepEqual(
    C.accept("use $cav now", mid, { insert: "$caveman " }),
    { value: "use $caveman now", cursor: 13 },
    "absorbs the following space",
  );
  const typed = C.detectTrigger("/compact", 8);
  assert.equal(C.isComplete("/compact", typed, item), true);
  assert.equal(C.isComplete("/comp", trigger, item), false);
});

test("menuLines draws the window around the highlight, above the composer", () => {
  const T = { fg: "fg", muted: "muted", accent: "accent", surface: "s", user_bubble: "u" };
  const m = { ...C.menu("/", 1, cat), sel: 1 };
  const lines = L.menuLines(m, 60, T, 8);
  assert.equal(lines.length, 5);
  assert.match(text(lines[1]), /^ › \/context +Show context usage/);
  assert.ok(lines[1].every((s) => s.bg === "u"), "highlight row");
  assert.ok(lines[0].every((s) => s.bg === "s"), "other rows on the surface");
  assert.ok(lines.every((l) => L.displayWidth(text(l)) === 60));
  const ansi = L.menuLines(m, 60, { ...T, surface: null }, 8);
  assert.ok(ansi[1].every((s) => s.inverse), "ANSI fallback uses inverse");
  assert.equal(L.menuLines(m, 60, T, 2).length, 2, "respects the row budget");

  const frame = L.frame({
    state: null,
    cols: 100,
    rows: 30,
    tokens: T,
    ui: { threadId: "t", editor: { value: "/", cursor: 1 }, menu: m },
  });
  const screen = frame.innerLines.map(text);
  const at = screen.findIndex((l) => l.includes("/context"));
  const card = screen.findIndex((l, i) => i > at && l.trim() === "/");
  assert.ok(at > 0 && card > at, "menu sits above the composer card");
  assert.match(screen.at(-1), /Commands: ↑\/↓ select · Tab\/Enter insert · Esc close · 5 found/);
});
