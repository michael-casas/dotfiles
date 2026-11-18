import "./support/guard.mjs"; // first: test isolation (temp HOME/T3CODE_HOME, no live T3)
import test from "node:test";
import assert from "node:assert/strict";
import * as t3 from "../t3.mjs";
import * as view from "../view.mjs";
import * as scrollback from "../scrollback.mjs";
// Missing implementation is an observable absence, not a broken test import.
const L = await import("../layout.mjs").catch((e) => {
  if (e.code !== "ERR_MODULE_NOT_FOUND") throw e;
  return {};
});
const text = (line) => line.map((s) => s.text).join("");
const T = Object.fromEntries(
  [
    "fg",
    "muted",
    "faint",
    "border",
    "surface",
    "accent",
    "accent_fg",
    "user_bubble",
    "code_bg",
    "link",
    "provider",
    "syn_keyword",
    "syn_flag",
    "syn_string",
    "syn_number",
    "fg_dim",
    "error",
    "warning",
    "attention",
    "success",
    "info",
  ].map((n) => [n, `token:${n}`]),
);
const state = () => {
  const items = [
    {
      id: "u",
      type: "user_message",
      runId: "r",
      text: "hello ".repeat(30),
      createdBy: "agent",
    },
    {
      id: "c",
      type: "command_execution",
      runId: "r",
      input: "git -C '/tmp/path here' log -3",
      output: "result\nnext",
      status: "completed",
    },
    {
      id: "f",
      type: "assistant_message",
      runId: "r",
      text: "## Answer\n\n- A **bold answer spanning the available width** and `inline code`\n\n| Name | Value |\n| --- | --- |\n| Alpha | Beta |",
    },
  ];
  return t3.applyValue(null, {
    kind: "snapshot",
    snapshotSequence: 1,
    projection: {
      thread: {
        id: "t",
        title: "A thread",
        modelSelection: { model: "raw-model" },
      },
      runs: [
        {
          id: "r",
          status: "completed",
          startedAt: "2026-01-01T00:00:00Z",
          completedAt: "2026-01-01T00:00:06.600Z",
        },
      ],
      turnItems: items,
      visibleTurnItems: items.map((item, position) => ({ position, item })),
    },
  });
};
test("live frame centres a shared column with horizontal padding without filling the screen", () => {
  assert.equal(typeof L.frame, "function");
  for (const [cols, rows, column, left] of [
    [155, 40, 92, 31],
    [80, 24, 74, 3],
  ]) {
    const f = L.frame({ state: state(), cols, rows, tokens: T });
    assert.equal(f.geometry.inner, cols - 6);
    assert.equal(f.geometry.column, column);
    assert.equal(f.geometry.left, left);
    assert.ok(f.lines.length < rows);
    assert.equal(text(f.lines[0]).trim(), "");
    assert.ok(text(f.lines.at(-1)).includes("A thread"));
    for (const row of f.lines) {
      assert.ok(L.displayWidth(text(row)) <= cols);
      assert.ok(text(row).startsWith("   "));
      assert.ok(text(row).endsWith("   "));
    }
    assert.equal(L.displayWidth(text(f.composer[0])), column);
    assert.equal(L.displayWidth(text(f.status)), column);
  }
});
test("user bubbles and agent chips fill only their right aligned eighty percent block", () => {
  assert.equal(typeof L.bubble, "function");
  for (const width of [92, 74]) {
    for (const agent of [false, true]) {
      const lines = L.bubble("words ".repeat(60), width, T, {
        agent,
        steer: true,
      });
      if (agent) assert.equal(lines.length, 1);
      for (const line of lines) {
        assert.equal(L.displayWidth(text(line)), width);
        const filled = line.filter((s) => s.bg === T.user_bubble);
        const fillWidth = L.displayWidth(text(filled));
        assert.ok(fillWidth <= Math.floor(width * 0.8));
        assert.ok(fillWidth > 2);
        assert.equal(line[0].text.length, width - fillWidth);
      }
    }
  }
});
test("markdown lists preserve numbered and nested hanging indents", () => {
  assert.equal(typeof L.markdown, "function");
  const lines = L.markdown(
    "1. alpha beta gamma delta epsilon\n   - nested words continue here for wrapping",
    18,
    T,
  ).map(text);
  assert.equal(lines[0], "1. alpha beta");
  assert.ok(lines[1].startsWith("   "));
  const nested = lines.findIndex((l) => l.startsWith("  • "));
  assert.ok(nested >= 0);
  assert.ok(lines[nested + 1].startsWith("    "));
});
test("inline styles are parsed before wrapping and retained on every fragment", () => {
  assert.equal(typeof L.markdown, "function");
  const lines = L.markdown(
    "**alpha beta gamma delta** then `long code fragment here` and [a link](https://example.test)",
    12,
    T,
  );
  const out = lines.map(text).join("\n");
  assert.ok(!/[`*]/.test(out));
  assert.ok(lines.filter((l) => l.some((s) => s.bold)).length > 1);
  assert.ok(lines.filter((l) => l.some((s) => s.bg === T.code_bg)).length > 1);
  assert.ok(lines.flat().some((s) => s.underline && s.color === T.link));
  assert.ok(lines.every((l) => L.displayWidth(text(l)) <= 12));
});
test("tables align separators, wrap cells and fences/quotes remain bounded", () => {
  assert.equal(typeof L.markdown, "function");
  const lines = L.markdown(
    "| Name | Value |\n| --- | --- |\n| a very long name | 42 |\n| X | much longer value |",
    24,
    T,
  ).map(text);
  const cells = lines.filter((l) => l.includes("│"));
  assert.ok(cells.length >= 3);
  assert.equal(new Set(cells.map((l) => l.indexOf("│"))).size, 1);
  assert.ok(lines.every((l) => L.displayWidth(l) <= 24));
  const blocks = L.markdown(
    "# Heading\n\n> quote words wrapping over lines\n\n```sh\necho a very very long command\n```",
    14,
    T,
  );
  assert.ok(blocks.some((l) => l.some((s) => s.bold)));
  assert.ok(blocks.some((l) => text(l).startsWith("│ ")));
  assert.ok(blocks.some((l) => l.some((s) => s.bg === T.code_bg)));
});
test("shell tokenizer preserves text and styles program, flags, quoted strings and numbers", () => {
  assert.equal(typeof L.shellTokens, "function");
  const command = "git -C '/tmp/path here' log 3 | head -2";
  const spans = L.shellTokens(command, T);
  assert.equal(text(spans), command);
  for (const [word, color] of [
    ["git", T.syn_keyword],
    ["-C", T.syn_flag],
    ["'/tmp/path here'", T.syn_string],
    ["3", T.syn_number],
    ["head", T.syn_keyword],
  ])
    assert.ok(
      spans.some((s) => s.text === word && s.color === color),
      word,
    );
});
test("expanded command has syntax, a blank row, dim output and a column rule", () => {
  assert.equal(typeof L.timelineLines, "function");
  const all = L.timelineLines(view.rows(state(), new Set(["turn:r", "c"])), 74, {}, T);
  const command = all.findIndex((l) =>
    l.some((s) => s.color === T.syn_keyword),
  );
  assert.ok(command >= 0);
  assert.equal(text(all[command + 1]), "");
  assert.ok(all[command + 2].some((s) => s.color === T.fg_dim));
  assert.ok(all.some((l) => text(l) === "─".repeat(74)));
  assert.ok(all.some((l) => text(l).startsWith("Worked for 6.6s ⌄")));
});
test("composer grows to six input rows, status/hints stay separate, fallback is round", () => {
  assert.equal(typeof L.frame, "function");
  const base = { state: state(), cols: 80, rows: 24, tokens: T };
  const f = L.frame(base);
  assert.ok(
    f.composer.some((l) =>
      text(l).includes("Ask anything. @ files, $ skills, / commands"),
    ),
  );
  assert.ok(!f.composer.some((l) => text(l).includes("Completed")));
  assert.ok(text(f.status).includes("Completed"));
  const multi = L.frame({
    ...base,
    ui: { editor: { value: "row\n".repeat(10), cursor: 40 } },
  });
  assert.equal(multi.composer.length, 10);
  const fallback = L.frame({ ...base, tokens: { ...T, surface: null } });
  assert.ok(text(fallback.composer[0]).startsWith("╭"));
  assert.ok(text(fallback.composer.at(-1)).endsWith("╯"));
  const hints = L.frame({ ...base, ui: { browse: true } });
  assert.ok(!text(hints.status).includes("Timeline:"));
  assert.ok(text(hints.status).includes("A thread"));
});
test("display widths handle ASCII, box/Nerd glyphs, CJK and emoji; hostile text cannot paint controls", () => {
  assert.equal(typeof L.displayWidth, "function");
  assert.equal(L.displayWidth("a─󰧑"), 3);
  assert.equal(L.displayWidth("中文🙂"), 6);
  const f = L.frame({
    state: state(),
    cols: 80,
    rows: 24,
    tokens: T,
    ui: { editor: { value: "中🙂".repeat(100) + "\u001b[31m", cursor: 400 } },
  });
  assert.ok(f.lines.every((l) => L.displayWidth(text(l)) <= 80));
  assert.ok(!f.lines.map(text).join("").includes("\u001b"));
});

test("layout widths agree with Ink for provider and steer glyphs (native truncation regression)", async () => {
  const { default: inkWidth } = await import("string-width");
  const f = L.frame({ state: state(), cols: 155, rows: 40, tokens: T });
  for (const row of f.lines)
    assert.ok(inkWidth(text(row)) <= 155, JSON.stringify(text(row)));
  assert.equal(L.displayWidth("✳ ↪"), inkWidth("✳ ↪"));
});

test("pasted multiline composer input preserves line breaks without admitting controls", async () => {
  const { editInput } = await import("../view.mjs");
  assert.equal(
    editInput("", 0, "one\ntwo\r\nthree\u001b", {}).value,
    "one\ntwo\nthree",
  );
});

test("question and approval cards remain in column and live tools keep a single indicator", () => {
  for (const kind of ["command", "user_input"]) {
    const s = state();
    s.runtimeRequests.set("request", {
      id: "request",
      kind,
      status: "pending",
      responseCapability: { type: "not_resumable" },
    });
    s.visibleTurnItems.push({
      position: 5,
      item: {
        id: "ask",
        type: kind === "command" ? "approval_request" : "user_input_request",
        requestId: "request",
        prompt: "Approve?",
        questions: [
          { id: "q", question: "Which one?", options: [{ label: "First" }] },
        ],
      },
    });
    const f = L.frame({ state: s, cols: 80, rows: 24, tokens: T });
    assert.ok(
      f.lines.some((l) => text(l).includes("cannot resume in this client")),
    );
    assert.ok(
      f.lines
        .flat()
        .some(
          (s) => s.color === (kind === "command" ? T.warning : T.attention),
        ),
    );
    assert.ok(f.lines.length < 24);
    assert.ok(f.lines.every((l) => L.displayWidth(text(l)) <= 80));
  }
  const s = state();
  s.runs.get("r").status = "running";
  s.turnItems.get("c").status = "running";
  const f = L.frame({
    state: s,
    cols: 80,
    rows: 24,
    tokens: T,
    ui: { now: Date.parse("2026-01-01T00:00:05Z") },
  });
  assert.equal(f.all.filter((l) => text(l).includes("Running git")).length, 1);
  assert.ok(f.all.some((l) => text(l).includes("Working for 5s")));
  assert.ok(f.composer.some((l) => text(l).includes(" ■ ")));
});

test("captured work group expands turn → group → command while keeping final markdown", async () => {
  const fs = await import("node:fs");
  const view = await import("../view.mjs");
  const frames = fs
    .readFileSync(new URL("./fixtures/turn.jsonl", import.meta.url), "utf8")
    .trim()
    .split("\n")
    .map(JSON.parse);
  const s = frames.reduce(
    (s, frame) => (frame.values || []).reduce(t3.applyValue, s),
    null,
  );
  const expanded = new Set();
  const turn = view.rows(s).findLast((r) => r.kind === "turn");
  expanded.add(turn.id);
  const group = view.rows(s, expanded).findLast((r) => r.kind === "group");
  assert.equal(group.text, "Ran 2 commands and read 1 file");
  expanded.add(group.id);
  const command = view
    .rows(s, expanded)
    .find(
      (r) =>
        r.kind === "command_execution" &&
        r.text === "git log --oneline -3",
    );
  assert.ok(command);
  expanded.add(command.id);
  const all = L.timelineLines(view.rows(s, expanded), 92, {}, T);
  assert.ok(
    all.some(
      (l) =>
        text(l).includes("Ran 2 commands and read 1 file") &&
        text(l).endsWith("⌄"),
    ),
  );
  assert.ok(
    all.some((l) =>
      l.some((s) => s.color === T.syn_keyword && s.text === "git"),
    ),
  );
  assert.ok(all.some((l) => text(l).includes("Example answer:")));
});

test("review: composer has cursor, filled spacer and complete controls tail", () => {
  for (const cols of [80, 155]) {
    const f = L.frame({ state: state(), cols, rows: 40, tokens: T });
    assert.equal(f.composer.length, 5);
    const input = f.composer[1];
    assert.ok(input.some((s) => s.inverse && s.text === " "));
    assert.ok(
      text(input).includes(" Ask anything. @ files, $ skills, / commands"),
    );
    assert.equal(text(f.composer[2]).trim(), "");
    for (const row of f.composer) {
      assert.equal(L.displayWidth(text(row)), f.geometry.column);
    }
    // Only content rows are fully painted; rounded edge cutouts stay transparent.
    for (const row of f.composer.slice(1, -1))
      assert.ok(row.every((s) => !s.text || s.bg != null));
    assert.equal(f.composer.at(-2).at(-1).bg, T.surface);
    assert.ok(f.composer.at(-2).at(-1).text.length >= 2);
  }
});

test("native history retains prompt spacing and centred committed lines; no selected viewport", () => {
  const p = scrollback.partition(state());
  const lines = p.committed.flatMap(b => L.historyLines(b, 155, T));
  assert.ok(lines.some(l => text(l).includes("Worked for 6.6s · Ran 1 command")));
  assert.ok(lines.every(l => text(l).startsWith(" ".repeat(31))));
  assert.ok(lines.every(l => L.displayWidth(text(l)) === 155));
  const f = L.frame({state:state(),cols:80,rows:24,tokens:T,ui:{scroll:10,browse:true,selected:"turn:r"}});
  assert.ok(!f.lines.some(l=>text(l).includes("Worked for")));
  assert.equal(f.top,undefined);
  assert.equal(text(f.innerLines[0]).trim(), "", "breathing room above composer");
});

test("review: table cells wrap without data loss with minimum widths and aligned separators", () => {
  const lines = L.markdown(
    "| Path | Description |\n| --- | --- |\n| exceptionally-long-filename.mjs | alpha beta gamma delta epsilon |",
    32,
    T,
  ).map(text);
  const content = lines.filter((l) => l.includes("│"));
  assert.ok(content.length > 2);
  assert.ok(!lines.join("").includes("…"));
  assert.equal(new Set(content.map((l) => l.indexOf("│"))).size, 1);
  const firstWidth = content[0].indexOf("│") - 1;
  assert.ok(firstWidth >= 8 && firstWidth <= 16);
  assert.ok(content.every((l) => L.displayWidth(l) <= 32));
  assert.equal(
    content
      .slice(1)
      .map((l) => l.split("│")[0].trim())
      .join(""),
    "exceptionally-long-filename.mjs",
  );
  assert.equal(
    content
      .slice(1)
      .map((l) => l.split("│")[1].trim())
      .join(" "),
    "alpha beta gamma delta epsilon",
  );
});

test("review: inline chips keep punctuation attached and never orphan filled padding", () => {
  for (const width of [12, 18, 24]) {
    const lines = L.markdown(
      "Use `theme.mjs`, `view.mjs`; and `layout.mjs`). Done.",
      width,
      T,
    );
    assert.ok(lines.every((l) => !/^[,.;:)]+/.test(text(l))));
    for (const line of lines) {
      const nonempty = line.filter((s) => s.text);
      assert.ok(!nonempty[0]?.chipPadding);
      assert.ok(!nonempty.at(-1)?.chipPadding);
      assert.ok(line.some((s) => s.text.trim()));
    }
    assert.ok(lines.every((l) => L.displayWidth(text(l)) <= width));
    assert.equal(
      lines
        .map(text)
        .join(" ")
        .replace(/\s+/g, " ")
        .replace(/\s+([,.;:)])/g, "$1")
        .trim(),
      "Use theme.mjs, view.mjs; and layout.mjs). Done.",
    );
  }
});

test("review: live verbs and icon muted, program foreground, failures error", () => {
  for (const verb of ["Running", "Ran", "Stopped", "Failed"]) {
    const lines = L.timelineLines(
      [
        {
          id: "c",
          kind: "live",
          text: `${verb} git`,
          icon: "",
          item: { status: verb === "Failed" ? "failed" : "running" },
        },
      ],
      74,
      {},
      T,
    );
    assert.ok(
      lines[0].some(
        (s) =>
          s.text.includes(verb) &&
          s.color === (verb === "Failed" ? T.error : T.muted),
      ),
    );
    assert.ok(
      lines[0].some(
        (s) =>
          s.text === "git" && s.color === (verb === "Failed" ? T.error : T.fg),
      ),
    );
  }
});

test("review: file paths use worktree/project scope, boundary-safe home fallback", () => {
  assert.equal(typeof L.displayPath, "function");
  const meta = {
    worktreePath: "/home/me/tree",
    workspaceRoot: "/home/me/project",
    projectTitle: ".dotfiles",
  };
  assert.equal(
    L.displayPath("/home/me/tree/src/a.mjs", meta, "/home/me"),
    ".dotfiles/src/a.mjs",
  );
  assert.equal(
    L.displayPath("/home/me/project/README.md", meta, "/home/me"),
    ".dotfiles/README.md",
  );
  assert.equal(
    L.displayPath("/home/me/tree-other/a", meta, "/home/me"),
    "~/tree-other/a",
  );
  assert.equal(L.displayPath("/other/path", meta, "/home/me"), "/other/path");
  assert.equal(L.displayPath("relative/path", {}, "/home/me"), "relative/path");
});

test("native status carries project/thread/branch metadata without latest hint", () => {
  const s = state();
  s.thread.projectId = "p";
  s.thread.branch = "feat/test";
  s.thread.worktreePath = "/tmp/worktree";
  s.turnItems.get("f").text = "paragraph\n\n".repeat(60);
  const f = L.frame({
    state: s,
    cols: 155,
    rows: 40,
    tokens: T,
    ui: {
      projects: new Map([
        ["p", { title: ".dotfiles", workspaceRoot: "/tmp/project" }],
      ]),
      scroll: 5,
    },
  });
  for (const icon of ["󰉋", "", "󰙅"]) assert.ok(text(f.status).includes(icon));
  assert.ok(!text(f.status).includes("↓ latest"));
  assert.ok(text(f.status).includes("A thread"));
  assert.ok(text(f.status).includes("Completed"));
});

test("review: post-measure Ink transform fills measured BMP emoji cells", async () => {
  const { tokenize, styledCharsFromTokens } = await import(
    "@alcalzone/ansi-tokenize"
  );
  const { default: measure } = await import("string-width");
  const f = L.frame({ state: state(), cols: 155, rows: 40, tokens: T });
  const controls = text(f.composer.at(-2));
  const outputCells = styledCharsFromTokens(
    tokenize(L.inkText(controls)),
  ).reduce((n, c) => n + (c.fullWidth || c.value.length > 1 ? 2 : 1), 0);
  assert.equal(outputCells, measure(controls));
});

test("review: typed end cursor remains visible and file rows consume metadata", () => {
  const f = L.frame({
    state: state(),
    cols: 80,
    rows: 24,
    tokens: T,
    ui: { editor: { value: "hello", cursor: 5 } },
  });
  assert.ok(f.composer[1].some((s) => s.inverse && s.text === " "));
  const rows = [
    {
      id: "read",
      kind: "dynamic_tool",
      text: "Read /repo/README.md",
      icon: "󰈈",
      item: { type: "dynamic_tool", toolName: "Read" },
    },
    {
      id: "edit",
      kind: "file_change",
      text: "Changed /repo/src/a.mjs",
      item: { type: "file_change", fileName: "/repo/src/a.mjs" },
    },
  ];
  const lines = L.timelineLines(rows, 74, {}, T, {
    workspaceRoot: "/repo",
    projectTitle: ".dotfiles",
  });
  assert.ok(text(lines[0]).includes("Read .dotfiles/README.md"));
  assert.ok(text(lines[1]).includes("Changed .dotfiles/src/a.mjs"));
});

test("round 2: message boundaries and expanded details have exactly one blank row", () => {
  const prompt = {
    id: "u",
    kind: "user_message",
    text: "hello",
    item: { createdBy: "agent" },
  };
  const reply = { id: "a", kind: "assistant_message", text: "demo ok" };
  const lines = L.timelineLines(
    [
      prompt,
      reply,
      prompt,
      { id: "turn", kind: "turn", text: "Worked for 1s" },
    ],
    74,
    {},
    T,
  );
  const a = lines.findIndex((l) => text(l) === "demo ok");
  assert.equal(text(lines[a - 1]), "");
  assert.ok(text(lines[a - 2]).includes("Agent"));
  for (let i = 1; i < lines.length; i++)
    assert.ok(
      text(lines[i]) !== "" || text(lines[i - 1]) !== "",
      "no duplicate gaps",
    );
  for (const type of ["command_execution", "reasoning", "file_change"]) {
    const item = {
      id: "detail",
      type,
      input: "echo test",
      output: "output\n",
      text: "reasoning",
      diffStr: "+line\n",
    };
    const result = L.timelineLines(
      [
        { id: "detail", kind: type, text: "detail", expanded: true, item },
        { id: "next", kind: "dynamic_tool", text: "next item" },
      ],
      74,
      {},
      T,
    );
    const next = result.findIndex((l) => text(l).startsWith("next item"));
    assert.equal(text(result[next - 1]), "");
    assert.ok(text(result[next - 2]).trim(), type + " has one gap only");
  }
});

test("round 2: table body rows have exactly their maximum cell height", () => {
  const lines = L.markdown(
    "| File | Purpose |\n| --- | --- |\n| `1234567890abcdef` | short |\n| last | final |",
    24,
    T,
  ).map(text);
  const separator = lines.findIndex((l) => l.includes("┼"));
  const body = lines.slice(separator + 1);
  assert.equal(body.length, 3);
  assert.ok(body.every((l) => l.replace("│", "").trim()));
  assert.ok(body.at(-1).includes("last"));
});

test("round 2: long table tokens prefer late path delimiters without losing text", () => {
  for (const delimiter of ["/", "-", "_", "."]) {
    const value = "abcdefgh" + delimiter + "t3contract";
    const lines = L.markdown(
      `| File | Note |\n| --- | --- |\n| ${value} | short |`,
      24,
      T,
    ).map(text);
    const body = lines.slice(lines.findIndex((l) => l.includes("┼")) + 1);
    assert.equal(body[0].split("│")[0].trimEnd(), "abcdefgh" + delimiter);
    assert.equal(body.map((l) => l.split("│")[0].trim()).join(""), value);
    assert.ok(body.every((l) => L.displayWidth(l) <= 24));
  }
});

test("round 2: provider/model have one rendered space and controls retain card width", async () => {
  const { tokenize, styledCharsFromTokens } = await import(
    "@alcalzone/ansi-tokenize"
  );
  for (const cols of [80, 155]) {
    const f = L.frame({ state: state(), cols, rows: 40, tokens: T });
    const line = L.inkText(text(f.composer.at(-2)));
    assert.ok(line.includes("✳ raw-model"));
    const cells = styledCharsFromTokens(tokenize(line)).reduce(
      (n, c) => n + (c.fullWidth || c.value.length > 1 ? 2 : 1),
      0,
    );
    assert.equal(cells, f.geometry.column);
  }
});

test("round 2: assistant blocks also separate from the following work row", () => {
  const lines = L.timelineLines(
    [
      { id: "a", kind: "assistant_message", text: "answer" },
      { id: "next", kind: "dynamic_tool", text: "next item" },
    ],
    74,
    {},
    T,
  );
  assert.equal(text(lines[1]), "");
  assert.ok(text(lines[2]).startsWith("next item"));
});

// Synthetic table with the cell widths and break points of a real repro (letters replaced).
const workspaceKeyFiles =
  "| Path | Role |\n|---|---|\n| `korm/phybuz/bws/mziykg/vvixvfqpoi/h2-daxmol.xv` | AJU bddgmg: vlkhtpe, zvhxst kfiph, pfkaou, kfmbcwqqx, uquucsk |\n| `korm/phybuz/bws/mziykg/vvixvfqpoi/h2-odmbdkja.xv` kpm `h2-odmbdkja.mftz.xv` | Jqsnnk D4 dpvdzty, lbbx vcqflyw kpm uplzc kfiph, r8q tlpfffa |\n| `korm/phybuz/bws/mziykg/h2-odnnhvi.xv` | Mncagt ccd yqlinnkhx kpm gecqs ccd rhjaw iaam kfd pcn fghud |\n| `korm/phybuz/bws/mziykg/h2-ftffq.xv` | Ivjvgxy-iosk KSbvr ftffq; sfyvsad Asac jtqosu |\n| `korm/phybuz/bws/mziykg/h2-rktaesm.xv` | Riqv-iosk mftz `qhoix/zwdl` rktaesm ra oawdgcr eiryiki ccd dhz |\n| `korm/phybuz/bws/mziykg/rrplebj/kyae-h2.xv` | Jspfsqss-hdiczacx kyae D4 fbbe qf G8/Y9/G5 |\n| `korm/phybuz/bws/gywzqxy/meicli.xv` | Ukj `QFT_WSYMAP_D4_*` gqeybjpg kpm alqdh qsckialqbq |\n| `korm/phybuz/bws/eifn.xv` | Bzfjlfwjq ccd `h2-daxmol` uldcpxw |\n| `korm/phybuz/albtkgkbwa/kfbypbi/h2-r8q.xv`, `h2-mftz.r8q.fefd.xv`, `h2-yuhwgpg.s5.fefd.xv` | Waw r8q ocbqsfnr wpi xf p mftz xidn kpm p kyae xidn |\n| `korm/phybuz/ztmfmqrd/phybuz-h2-yqlinnkhx.sdcuatx`, `phybuz-h2-r8q.sdcuatx`, `YGZOYHL-h2-r8q.dw` | Ejrjhh albtkgkbwa cmlpnovpp |\n| `korm/phybuz/TWJLQM.dw` | Rvvw r8q uqrmhml, rhjaw qnmchjpc, D4 yqlinnkhx otpow |\n| `korm/phybuz/slbvlqz.yqbj` | `h2-ftffq` kpm `r8q-h2-mftz` La hvadwyi |\n| `korm/phybuz/qmgexxdk/h2-r8q/` | Gbi nqqxkdg kpm kyae-xidn qmgexxdk |\n| `mugq/hgudwsrtuwnk-goosqwud-rmohie.yqbj` | Sdkmpvs R3Z-0..6, F9K-N kpm F9K-R |\n| `mugq/founxclto/qow-phybuz/*.dw` | Rgxizh, wuzvkzgqpeg kpm Ccahp 1 wwzry |\n| `qhoix/qow-phybuz-bhbfqw/TEDWTX.dw` | Ccahp 1 D4 rktaesm, wbomcy iosk 1.0.1-rmxwmgr uqudkjlkfd |\n| `ouqkmobw/uldcpxw/bws/hmbqljeix/uldcpxw-hmbqljeix.xcennj.xv` | Ynmqbcbx `h2` cv p vhpgmxqn-uldcpxw aojxygqj |\n| `.mfvyg/qow/palu/*.yqbj` | Eunj nqqxkdg xyb IIF-140, 394 kpm 176 |";

const keyFileRowHeights = new Map([
  // 44/45 cells: the charter's 92-cell conversation column at 155 × 40.
  [92, [2, 2, 2, 1, 2, 1, 2, 1, 3, 3, 2, 1, 1, 1, 1, 2, 2, 1]],
  // Also guard the reported ~60/61-cell column widths (124-cell table).
  [124, [1, 2, 1, 1, 2, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1]],
]);

test("round 3: table rows occupy max(cell heights), never an empty row", () => {
  const cells = workspaceKeyFiles
    .split("\n")
    .slice(2)
    .map((row) =>
      row
        .split("|")
        .slice(1, -1)
        .map((cell) => cell.trim()),
    );
  for (const [width, expectedHeights] of keyFileRowHeights) {
    const lines = L.markdown(workspaceKeyFiles, width, T);
    const divider = text(lines[0]).indexOf("│");
    const widths = [divider - 1, width - divider - 2];
    assert.deepEqual(widths, width === 92 ? [44, 45] : [60, 61]);
    const body = lines.slice(2).map(text);
    let offset = 0;
    for (const [r, row] of cells.entries()) {
      const wrapped = row.map((cell, c) =>
        L.wrapSegments(L.inline(cell, T), widths[c], { tokenBreaks: true }).map(
          text,
        ),
      );
      const height = Math.max(...wrapped.map((cell) => cell.length));
      assert.equal(height, expectedHeights[r], `${width}: ${row[0]}`);
      for (let y = 0; y < height; y++) {
        const line = body[offset + y];
        assert.ok(line !== undefined, `${row[0]} missing line ${y}`);
        assert.ok(line.replace("│", "").trim(), `${row[0]} empty line ${y}`);
        assert.equal(line.indexOf("│"), divider);
        assert.equal(L.displayWidth(line), width);
        assert.equal(line.slice(0, widths[0]).trimEnd(), wrapped[0][y] || "");
        assert.equal(line.slice(divider + 2).trimEnd(), wrapped[1][y] || "");
      }
      offset += height;
    }
    assert.equal(body.length, offset, "no trailing or inter-row spacer lines");
  }
});

test("round 3: native Ink adds no physical lines to the exact styled Workspace table", async () => {
  const { default: React } = await import("react");
  const { render, Box, Text, Transform } = await import("ink");
  const { PassThrough } = await import("node:stream");
  const { loadTheme } = await import("../theme.mjs");
  const h = React.createElement;
  for (const width of keyFileRowHeights.keys()) {
    // Exercise real colours and ANSI fallback, not invalid synthetic token names.
    for (const tokens of [loadTheme().tokens, {}]) {
      const lines = L.markdown(workspaceKeyFiles, width, tokens);
      const stdout = new PassThrough();
      stdout.columns = 155;
      stdout.rows = 100;
      let output = "";
      stdout.on("data", (chunk) => {
        output = chunk.toString();
      });
      const app = render(
        h(
          Box,
          { flexDirection: "column", width: 155, paddingX: 3 },
          ...lines.map((segments, key) =>
            h(
              Transform,
              { transform: L.inkText, key },
              h(
                Text,
                { wrap: "truncate" },
                ...segments.map((s, key) =>
                  h(
                    Text,
                    {
                      key,
                      color: s.color,
                      backgroundColor: s.bg,
                      bold: s.bold,
                      underline: s.underline,
                      inverse: s.inverse,
                    },
                    s.text,
                  ),
                ),
              ),
            ),
          ),
        ),
        { stdout, debug: true, patchConsole: false, exitOnCtrlC: false },
      );
      try {
        const actual = L.safe(output).trimEnd().split("\n");
        const expected = lines.map((line) =>
          ("   " + L.inkText(text(line))).trimEnd(),
        );
        assert.deepEqual(actual, expected, `native ${width}-cell table`);
      } finally {
        app.unmount();
        app.cleanup();
        stdout.destroy();
      }
    }
  }
});

for (const cols of [20, 40, 92]) {
  for (const working of [false, true]) {
    test(`rounded composer keeps its budget, pill and menus at ${cols} columns (${working ? "working" : "idle"})`, () => {
      const s = state();
      s.runs.get("r").status = working ? "running" : "completed";
      s.thread.modelSelection.model = "a-very-long-model-label";
      const width = L.geometry(cols).column;
      const ui = {
        editor: { value: "draft", cursor: 5 },
        menu: { trigger: { kind: "command" }, items: [{ label: "/model", description: "Select model" }] },
      };
      // The actual unpainted backdrop is the terminal default, not T.bg.
      const tokens = { ...T, bg: "token:bg" };
      const f = L.frame({ state: s, cols, rows: 24, tokens, ui });
      assert.equal(f.composer.length, 5);
      assert.equal(text(f.composer[0]), "▗" + "▄".repeat(width - 2) + "▖");
      assert.equal(text(f.composer.at(-1)), "▝" + "▀".repeat(width - 2) + "▘");
      for (const edge of [f.composer[0], f.composer.at(-1)])
        assert.ok(edge.every(seg => seg.color === T.surface && seg.bg == null));
      const control = f.composer.at(-2);
      const icon = working ? " ■ " : " ↑ ";
      // Powerline half circles: Herdr draws them as a true pill (REP live check).
      assert.ok(text(control).includes("\ue0b6" + icon + "\ue0b4"));
      const button = control.find(seg => seg.text === icon);
      assert.equal(button.bg, working ? T.error : T.accent);
      assert.equal(button.color, T.accent_fg);
      for (const glyph of ["\ue0b6", "\ue0b4"]) {
        const end = control.find(seg => seg.text === glyph);
        assert.equal(end.color, button.bg);
        assert.equal(end.bg, T.surface);
      }
      assert.ok(f.composer.every(line => L.displayWidth(text(line)) === width));
      assert.ok(f.lines.every(line => L.displayWidth(text(line)) <= cols));
      const menu = L.menuLines(ui.menu, width, T);
      assert.ok(menu.every(line => L.displayWidth(text(line)) === width));
      const fallback = L.frame({ state: s, cols, rows: 24, tokens: { ...T, surface: null }, ui });
      assert.equal(text(fallback.composer[0]), "╭" + "─".repeat(width - 2) + "╮");
      assert.equal(text(fallback.composer.at(-1)), "╰" + "─".repeat(width - 2) + "╯");
      assert.ok(text(fallback.composer.at(-2)).includes("▐" + icon + "▌"));
      assert.ok(fallback.composer.every(line => L.displayWidth(text(line)) === width));
    });
  }
}
