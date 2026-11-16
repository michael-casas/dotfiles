#!/usr/bin/env node
import React, { useEffect, useMemo, useRef, useState } from "react";
import { render, Box, Text, Transform, Static, useInput, useStdout } from "ink";
import path from "node:path";
import * as t3 from "./t3.mjs";
import * as view from "./view.mjs";
import * as layout from "./layout.mjs";
import * as commands from "./commands.mjs";
import * as modelPicker from "./model-picker.mjs";
import * as scrollback from "./scrollback.mjs";
import * as control from "./control.mjs";
import { createControlInput } from "./control-input.mjs";
import { loadTheme, watchTheme } from "./theme.mjs";

const h = React.createElement;
const controls = createControlInput(process.stdin);
const argv = process.argv.slice(2);
const flag = (name) => {
  const i = argv.indexOf(name);
  return i < 0 ? undefined : argv[i + 1];
};
const mode =
  argv[0] === "new"
    ? "new"
    : argv[0] && !argv[0].startsWith("-")
      ? "thread"
      : "pick";
const project = flag("--project") || process.cwd();
const safe = layout.safe;
function report(state, msg = "") {
  process.stdout.write(
    `\x1b]7501;state=${state}:app=t3:msg=${safe(msg).replace(/[:\n]/g, " ").slice(0, 60)}\x1b\\`,
  );
}
function DisplayLine({ segments }) {
  return h(
    Transform,
    { transform: layout.inkText },
    h(
      Text,
      { wrap: "truncate" },
      ...(segments.length ? segments : [{ text: " " }]).map((s, key) =>
        h(
          Text,
          {
            key,
            color: s.color ?? undefined,
            backgroundColor: s.bg ?? undefined,
            bold: s.bold,
            underline: s.underline,
            inverse: s.inverse,
          },
          s.text,
        ),
      ),
    ),
  );
}
function useSize() {
  const { stdout } = useStdout();
  const read = () => ({ cols: stdout.columns || 80, rows: stdout.rows || 24 });
  const [size, setSize] = useState(read);
  useEffect(() => {
    const resize = () => setSize(read());
    // Ink repaints from its own "resize" listener, registered before this
    // one. Run first so the tree already has the new size: otherwise Ink
    // measures the old, taller live frame against the new height, clears the
    // whole terminal (scrollback too) and replays every <Static> item.
    stdout.prependListener("resize", resize);
    return () => stdout.off("resize", resize);
  }, [stdout]);
  return size;
}
function Screen({ size, lines, inline = false }) {
  return h(
    Box,
    {
      flexDirection: "column",
      ...(inline ? {} : { height: size.rows - 1 }),
      width: size.cols,
      paddingX: 3,
      paddingY: inline ? 0 : 1,
    },
    ...lines.map((segments, key) => h(DisplayLine, { key, segments })),
  );
}

function Thread({ initialId, T }) {
  const size = useSize();
  const [projectMap, setProjectMap] = useState(new Map());
  const [threadId, setThreadId] = useState(initialId),
    [state, setState] = useState(null),
    [conn, setConn] = useState(initialId ? "connecting" : "new");
  const [editor, setEditor] = useState({ value: "", cursor: 0 }),
    [busy, setBusy] = useState(false),
    [flash, setFlash] = useState("");
  const [expanded, setExpanded] = useState(new Set());
  const [history, setHistory] = useState(scrollback.ledger);
  const expansionId = useRef(0);
  const [details, setDetails] = useState({}),
    [now, setNow] = useState(Date.now()),
    [answerDraft, setAnswerDraft] = useState({});
  // `/` and `$` completion: providers from server.getConfig, the highlighted
  // row per trigger, and the trigger the user closed with Esc.
  const [providers, setProviders] = useState(null),
    [menuPick, setMenuPick] = useState({ key: null, sel: 0 }),
    [dismissed, setDismissed] = useState(null);
  const [modelDraft, setModelDraft] = useState(null);
  const [compactDialog, setCompactDialog] = useState(null);
  const dialogRef = useRef(null);
  const controlHandler = useRef(null);
  useEffect(() => controls.onAction(action => controlHandler.current?.(action)), []);
  const catalogAsked = useRef(new Set());
  const client = useRef(null),
    streams = useRef(new Map()),
    loaded = useRef(new Map());
  const st = t3.status(state),
    working = st === "working" || st === "blocked";
  useEffect(() => {
    let active = true;
    Promise.resolve(t3.projects?.() || new Map()).then((projects) => {
      if (active) setProjectMap(projects);
    });
    return () => {
      active = false;
    };
  }, [state?.thread?.projectId]);
  useEffect(() => {
    if (!threadId) return;
    const close = t3.subscribe(threadId, {
      onState: setState,
      onConn: setConn,
      onConfig: (config) =>
        setProviders((old) =>
          commands.mergeProviders(old, config?.providers || []),
        ),
    });
    client.current = close;
    return () => {
      for (const stop of streams.current.values()) stop();
      streams.current.clear();
      close();
      client.current = null;
    };
  }, [threadId]);
  useEffect(() => {
    if (!working) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [working]);
  useEffect(() => {
    report(st, state?.thread?.title);
  }, [st, state?.thread?.title]);
  const partition = useMemo(
    () => scrollback.partition(state, expanded, now),
    [state, expanded, now],
  );
  const rows = partition.live;
  const freeze = (block, details = {}) => ({
    ...block,
    lines: layout.historyLines(block, size.cols, T, t3.threadMeta(state, projectMap), details),
  });
  useEffect(() => {
    setHistory(old => scrollback.append(old, partition.committed, freeze));
  }, [partition, size.cols, T, projectMap]);
  const pending = t3.pendingRequests(state),
    request = pending[0];
  const card =
    request && t3.timeline(state).find((i) => i.requestId === request.id);
  const question = card?.questions?.find(
    (q) => !Object.hasOwn(answerDraft, q.id),
  );
  const userInput = request?.kind === "user_input";
  const instanceId =
    state?.thread?.modelSelection?.instanceId ||
    state?.thread?.providerInstanceId;
  const cwd =
    state?.thread?.worktreePath ||
    projectMap.get(state?.thread?.projectId)?.workspaceRoot;
  const catalog = useMemo(
    () => commands.catalog(providers, instanceId, cwd),
    [providers, instanceId, cwd],
  );
  // Ask once per provider and folder for its own commands and skills.
  useEffect(() => {
    const ask = `${instanceId}\0${cwd}`;
    if (!catalog || catalog.hasSnapshot || !cwd || !client.current) return;
    if (catalogAsked.current.has(ask)) return;
    catalogAsked.current.add(ask);
    client.current
      .providerCatalog(instanceId, cwd)
      .then((reply) =>
        setProviders((old) =>
          commands.mergeProviders(old, reply?.providers || []),
        ),
      )
      .catch((e) => t3.debug("provider catalog", e.message));
  }, [catalog, instanceId, cwd]);
  const found =
    threadId && !userInput && !modelDraft && !compactDialog
      ? commands.menu(editor.value, editor.cursor, catalog, { working })
      : null;
  const menuKey = found
    ? `${found.trigger.kind}:${found.trigger.start}:${found.trigger.query}`
    : null;
  const tokenKey = found ? `${found.trigger.kind}:${found.trigger.start}` : null;
  useEffect(() => {
    if (dismissed && dismissed !== tokenKey) setDismissed(null);
  }, [tokenKey, dismissed]);
  const menu =
    found && dismissed !== tokenKey
      ? {
          ...found,
          sel: Math.min(
            menuPick.key === menuKey ? menuPick.sel : 0,
            Math.max(0, found.items.length - 1),
          ),
        }
      : null;
  const screen = useMemo(
    () =>
      layout.frame({
        state,
        cols: size.cols,
        rows: size.rows,
        tokens: T,
        ui: {
          threadId,
          conn,
          editor,
          expanded,
          details,
          now,
          answerDraft,
          projects: projectMap,
          timelineRows: rows,
          flash,
          compactDialog,
          menu,
          modelPicker: modelDraft
            ? modelPicker.columns(modelDraft, providers, state)
            : null,
        },
      }),
    [
      state,
      size,
      T,
      threadId,
      conn,
      editor,
      expanded,
      details,
      now,
      answerDraft,
      projectMap,
      rows,
      flash,
      compactDialog,
      menu,
      modelDraft,
      providers,
    ],
  );
  // Expanded detail belongs to its projected revision; refresh when a running item completes.
  useEffect(() => {
    const open = rows.filter(
      (r) =>
        r.expanded &&
        r.item &&
        ["command_execution", "dynamic_tool"].includes(r.item.type),
    );
    const openIds = new Set(open.map((r) => r.id));
    for (const [id, stop] of streams.current)
      if (
        !openIds.has(id) ||
        open.find((r) => r.id === id)?.item.status !== "running"
      ) {
        stop();
        streams.current.delete(id);
      }

    for (const row of open) {
      const it = row.item,
        rev = it.updatedAt + ":" + it.status;
      if (loaded.current.get(it.id) === rev) continue;
      loaded.current.set(it.id, rev);
      setDetails((d) => ({ ...d, [it.id]: { loading: true } }));
      client.current?.getItem(it).then(
        (result) => {
          setDetails((d) => ({
            ...d,
            [it.id]: { ...d[it.id], item: result.item, loading: false },
          }));
        },
        (e) => {
          loaded.current.delete(it.id);
          setDetails((d) => ({ ...d, [it.id]: { error: e.message } }));
        },
      );
      if (
        it.type === "command_execution" &&
        it.status === "running" &&
        !streams.current.has(it.id)
      ) {
        streams.current.set(
          it.id,
          client.current?.watchOutput(
            it.id,
            (frame) =>
              setDetails((d) => {
                const prev = d[it.id] || {};
                return {
                  ...d,
                  [it.id]: {
                    ...prev,
                    loading: false,
                    output: (frame.kind === "replace"
                      ? frame.text
                      : (prev.output || "") + frame.text
                    ).slice(-200000),
                    truncated:
                      (frame.kind === "append" && prev.truncated) ||
                      frame.truncated ||
                      (prev.output?.length || 0) + frame.text.length > 200000,
                  },
                };
              }),
            it.threadId,
          ) || (() => {}),
        );
      }
    }
  }, [rows]);
  async function act(task, message) {
    if (busy) return;
    setBusy(true);
    setFlash(message || "");
    try {
      await task();
      setFlash("");
    } catch (e) {
      setFlash(e.message);
    } finally {
      setBusy(false);
    }
  }
  const compactContext = {
    threadId, conn, working, busy,
    compactAvailable: Boolean(catalog?.slashCommands.some(c => c.name === "compact")),
  };
  function confirmationAction(action, kind = dialogRef.current?.kind) {
    const reduce = kind === "interrupt" ? control.interrupt : control.compact;
    const result = reduce(dialogRef.current, action, compactContext);
    // Consume before dispatch, even if open+yes+yes arrives in one stdin chunk.
    dialogRef.current = result.dialog;
    setCompactDialog(result.dialog);
    if (result.stop) act(() => client.current.stop(), "Interrupting…");
    if (result.send) act(() => client.current.send(result.send), "Compacting…");
  }
  controlHandler.current = action => {
    if (action === "model") {
      dialogRef.current = null;
      setCompactDialog(null);
      openModelPicker(true);
    } else if (action === "compact" || action === "interrupt") {
      setModelDraft(null);
      confirmationAction("open", action);
    } else if (action === "dismiss") {
      if (dialogRef.current) return confirmationAction("cancel");
      const next = control.escapeAction({ model: modelDraft, menu });
      if (next === "close-model") { setModelDraft(null); setFlash(""); }
      if (next === "close-menu") setDismissed(tokenKey);
    } else confirmationAction(action);
  };
  function openModelPicker(preserveDraft = false) {
    if (busy || !state?.thread) return;
    setModelDraft(modelPicker.open(providers, state));
    if (!preserveDraft) setEditor({ value: "", cursor: 0 });
    setFlash("");
  }
  async function submit(queue = false) {
    const text = editor.value.trim();
    if (!text || busy) return;
    if (userInput) {
      if (!question) return;
      if (request.responseCapability?.type === "not_resumable") {
        setFlash(
          request.responseCapability.reason ||
            "This request cannot be resumed.",
        );
        return;
      }
      const parsed = view.answerInput(question, text);
      if (parsed.error) {
        setFlash(parsed.error);
        return;
      }
      const answers = { ...answerDraft, [question.id]: parsed.answer };
      const next = card.questions.find((q) => !Object.hasOwn(answers, q.id));
      setEditor({ value: "", cursor: 0 });
      if (next) {
        setAnswerDraft(answers);
        return;
      }
      await act(async () => {
        await client.current.respond(request.id, { answers });
        setAnswerDraft({});
      }, "Sending answers…");
      return;
    }
    if (threadId && text === "/model") {
      openModelPicker();
      return;
    }
    await act(
      async () => {
        if (!threadId) {
          const id = await t3.start(project, text, {
            provider: flag("--provider"),
            model: flag("--model"),
            title: flag("--title"),
          });
          setThreadId(id);
        } else await client.current.send(text, { queue });
        setEditor({ value: "", cursor: 0 });
      },
      queue ? "Queuing…" : working ? "Steering…" : "Sending…",
    );
  }
  useInput((ch, key) => {
    if (dialogRef.current) {
      confirmationAction(!key.escape && !key.ctrl && !key.meta && ch === "y" ? "yes" : "cancel");
      return;
    }
    if (key.ctrl && ch === "c") {
      setModelDraft(null);
      confirmationAction("open", "interrupt");
      return;
    }
    if (key.escape) {
      const action = control.escapeAction({ model: modelDraft, menu });
      if (action === "close-model") { setModelDraft(null); setFlash(""); }
      if (action === "close-menu") setDismissed(tokenKey);
      return;
    }
    if (modelDraft) {
      if (busy) return;
      const result = modelPicker.input(modelDraft, ch, key, providers, state);
      if (result.action === "close") {
        setModelDraft(null);
        setFlash("");
      } else if (result.action === "apply") {
        const selection = modelPicker.selection(result.picker, providers, state);
        if (!selection) {
          setFlash("Choose an available harness and model before applying.");
          return;
        }
        act(async () => {
          await client.current.setModel(selection);
          // Only the server event updates state.thread and its composer label.
          setModelDraft(null);
        }, "Applying model…");
      } else {
        setModelDraft(result.picker);
        setFlash("");
      }
      return;
    }
    if (menu) {
      const n = menu.items.length;
      if (key.upArrow || (key.ctrl && ch === "p")) {
        setMenuPick({ key: menuKey, sel: n ? (menu.sel - 1 + n) % n : 0 });
        return;
      }
      if (key.downArrow || (key.ctrl && ch === "n")) {
        setMenuPick({ key: menuKey, sel: n ? (menu.sel + 1) % n : 0 });
        return;
      }
      if ((key.tab || key.return) && n) {
        const item = menu.items[menu.sel];
        if (item.action === "model") {
          openModelPicker();
          return;
        }
        if (
          key.return &&
          commands.isComplete(editor.value, menu.trigger, item)
        ) {
          submit(false);
          return;
        }
        setEditor(commands.accept(editor.value, menu.trigger, item));
        return;
      }
      if (key.tab) return;
    }
    if (key.ctrl && ch === "o") {
      act(async () => {
        const block = scrollback.expandedBlock(state);
        if (!block) throw new Error("No finished work to print.");
        const details = {};
        await Promise.all(block.rows.filter(r => r.item && ["command_execution", "dynamic_tool"].includes(r.item.type)).map(async r => {
          try { details[r.id] = await client.current.getItem(r.item); }
          catch (e) { details[r.id] = { error: e.message }; }
        }));
        const id = `expanded:${++expansionId.current}`;
        const frozen = freeze({ ...block, id }, details);
        setHistory(old => scrollback.append(old, [frozen]));
      }, "Loading expanded work…");
      return;
    }
    if (key.tab) {
      // No timeline focus: only currently live work can disclose in-place.
      setExpanded(old => old.size ? new Set() : new Set(rows.filter(r => r.expandable).map(r => r.id)));
      return;
    }
    if (
      request &&
      !userInput &&
      ["y", "a", "n"].includes(ch) &&
      !editor.value
    ) {
      if (request.responseCapability?.type === "not_resumable") {
        setFlash(
          request.responseCapability.reason ||
            "This request cannot be resumed.",
        );
        return;
      }
      act(
        () =>
          client.current.respond(request.id, {
            decision: { y: "accept", a: "acceptForSession", n: "decline" }[ch],
          }),
        "Responding…",
      );
      return;
    }
    if (key.ctrl && ch === "q") {
      submit(true);
      return;
    }
    if (key.return) {
      submit(false);
      return;
    }
    setEditor((e) => view.editInput(e.value, e.cursor, ch, key));
  });
  return h(React.Fragment, null,
    h(Static, { items: history.items }, block =>
      h(Box, { key: block.id, flexDirection: "column" },
        ...block.lines.map((segments, key) => h(DisplayLine, { key, segments })),
      ),
    ),
    h(Screen, { size, lines: screen.innerLines, inline: true }),
  );
}

function Picker({ onPick, T }) {
  const size = useSize();
  const g = layout.geometry(size.cols, size.rows);
  const [items, setItems] = useState(null);
  const [err, setErr] = useState("");
  const [i, setI] = useState(0);
  useEffect(() => {
    t3.list(project).then(setItems, (e) => setErr(e.message));
  }, []);
  useInput((ch, key) => {
    if (!items?.length) return;
    if (key.upArrow || ch === "k") setI((x) => Math.max(x - 1, 0));
    else if (key.downArrow || ch === "j")
      setI((x) => Math.min(x + 1, items.length - 1));
    else if (key.return) onPick(items[i].threadId);
    else if (ch === "n") onPick(null);
  });
  const count = Math.max(1, g.innerRows - 3);
  const start = Math.max(
    0,
    Math.min(i - Math.floor(count / 2), (items?.length || 0) - count),
  );
  const column = (segments) => [
    { text: " ".repeat(g.left - 3) },
    ...layout.clip(segments, g.column, true),
  ];
  const lines = [
    [
      {
        text: `T3 threads · ${path.basename(project)}`,
        color: T.fg,
        bold: true,
      },
    ],
    [],
    ...(!items || err
      ? [
          column([
            {
              text: err ? `t3 thread list: ${err}` : "Loading threads…",
              color: err ? T.error : T.muted,
            },
          ]),
        ]
      : items.slice(start, start + count).map((t, k) =>
          column([
            {
              text: t.activeRunId ? "● " : "○ ",
              color: t.activeRunId ? T.info : T.muted,
              inverse: start + k === i,
            },
            {
              text: `${t.title}  ${t.model || ""} · ${t.creationSource || ""}`,
              color: T.fg,
              inverse: start + k === i,
            },
          ]),
        )),
  ];
  while (lines.length < g.innerRows - 1) lines.push([]);
  lines.push(
    column([
      { text: "j/k move · Enter open · n new · Ctrl-C quit", color: T.faint },
    ]),
  );
  return h(Screen, {
    size,
    lines: lines.map((l) => layout.clip(l, g.inner, true)),
  });
}

function Root() {
  const [theme, setTheme] = useState(() => loadTheme());
  useEffect(() => watchTheme(setTheme), []);
  const [picked, setPicked] = useState(
    mode === "thread" ? argv[0] : mode === "new" ? null : undefined,
  );
  return picked === undefined
    ? h(Picker, { onPick: setPicked, T: theme.tokens })
    : h(Thread, { initialId: picked, T: theme.tokens });
}
process.on("exit", () => { controls.close(); report("idle"); });
controls.start();
try {
  await render(h(Root), { stdin: controls.stdin, exitOnCtrlC: false }).waitUntilExit();
} finally {
  controls.close();
}
