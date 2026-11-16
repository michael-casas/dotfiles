import React, { useState, useEffect, useRef } from "react";
import { render, Text, Box, useInput, useApp, useStdout } from "ink";
import { BoardSession } from "./session.mjs";
import { viewport, project } from "./view.mjs";
import { DiagramRenderer } from "./renderer.mjs";
import { pinnedSource } from "./source.mjs";
import { safeText } from "./document.mjs";

export async function openTui(opts) {
  const session = new BoardSession(opts),
    renderer = new DiagramRenderer();
  session.start();
  function App() {
    const { exit } = useApp(),
      { stdout } = useStdout();
    const [snapshot, setSnapshot] = useState(session.snapshot),
      [size, setSize] = useState([stdout.columns ?? 80, stdout.rows ?? 24]);
    const diagramsHash = useRef(null);
    const [diagrams, setDiagrams] = useState(new Map()),
      [sourcePane, setSourcePane] = useState(null),
      [sourceOnly, setSourceOnly] = useState(false);
    const [outline, setOutline] = useState(false),
      [lastQuery, setLastQuery] = useState("");
    const [top, setTop] = useState(0),
      [left, setLeft] = useState(0),
      [help, setHelp] = useState(false),
      [query, setQuery] = useState(null);
    useEffect(() => session.subscribe(setSnapshot), []);
    useEffect(() => {
      const resize = () => setSize([stdout.columns ?? 80, stdout.rows ?? 24]);
      stdout.on("resize", resize);
      return () => stdout.off("resize", resize);
    }, []);
    useEffect(() => {
      let current = true;
      setSourcePane(null);
      const doc = snapshot?.document;
      const blocks =
        doc?.valid && !doc.opaque
          ? doc.blocks.filter((b) => b.kind === "mermaid")
          : [];
      const sameRevision = diagramsHash.current === doc?.hash;
      diagramsHash.current = doc?.hash ?? null;
      setDiagrams(
        (previous) =>
          new Map(
            blocks.map((b) => [
              b.id,
              sameRevision && previous.has(b.id)
                ? previous.get(b.id)
                : { kind: "rendering", source: b.content },
            ]),
          ),
      );
      if (doc?.valid && !doc.opaque)
        (async () => {
          for (const b of blocks) {
            const value = await renderer.render(b.content, {
              width: size[0],
              theme: JSON.stringify(snapshot.theme),
              revision: doc.hash,
            });
            if (!current) break;
            if (current) setDiagrams((m) => new Map(m).set(b.id, value));
          }
        })();
      return () => {
        current = false;
      };
    }, [snapshot?.document?.hash, snapshot?.theme, size[0]]);
    const projection = snapshot
      ? project(snapshot, { diagrams, sourceOnly })
      : { rows: ["Loading local board…"], mapping: [] };
    const rows = sourcePane ?? projection.rows;
    useInput((input, key) => {
      if (key.ctrl && input === "c") {
        exit();
        return;
      }
      if (query !== null) {
        if (key.escape) {
          setQuery(null);
          return;
        }
        if (key.return) {
          const at = rows.findIndex(
            (line, i) =>
              i > top && line.toLowerCase().includes(query.toLowerCase()),
          );
          if (at >= 0) setTop(at);
          setLastQuery(query);
          setQuery(null);
          return;
        }
        if (key.backspace || key.delete) setQuery((q) => q.slice(0, -1));
        else if (!key.ctrl && !key.meta) setQuery((q) => safeText(q + input));
        return;
      }
      if (input === "q") {
        if (help) setHelp(false);
        else if (sourcePane) {
          setSourcePane(null);
          setTop(0);
        } else exit();
        return;
      }
      if (input === "?") {
        setHelp((x) => !x);
        return;
      }
      if (key.escape) {
        setHelp(false);
        return;
      }
      if (input === "/") {
        setQuery("");
        return;
      }
      if (key.tab) {
        setOutline((x) => !x);
        setTop(0);
        return;
      }
      if (input === "n" || input === "N") {
        if (lastQuery) {
          const indices = rows
            .map((line, i) =>
              line.toLowerCase().includes(lastQuery.toLowerCase()) ? i : -1,
            )
            .filter((i) => i >= 0);
          const at =
            input === "n"
              ? indices.find((i) => i > top)
              : indices.reverse().find((i) => i < top);
          if (at !== undefined) setTop(at);
        }
      }
      if (input === "e") {
        setSourcePane([
          `Board source: ${session.path}`,
          "Open this path in your editor. This viewer never invokes a shell/editor.",
        ]);
        setTop(0);
      }
      if (outline && key.return) {
        const section = snapshot?.document?.blocks.filter(
          (b) => b.kind === "heading" && b.level === 2,
        )[top];
        const row = projection.mapping.findIndex((m) => m.id === section?.id);
        if (row >= 0) setTop(row);
        setOutline(false);
        return;
      }
      if (input === "s") setSourceOnly((x) => !x);
      if (key.return && !sourcePane && !snapshot?.stale) {
        const id = projection.mapping[top]?.id,
          block = snapshot?.document.blocks.find(
            (b) => b.id === id && b.kind === "wb-source",
          );
        if (block) {
          const hash = snapshot.document.hash;
          void pinnedSource(block.record, opts.bindings).then((r) => {
            if (session.snapshot?.document?.hash === hash) {
              setSourcePane([
                `PINNED ${block.id}: ${r.state}`,
                r.notice ?? r.reason,
                ...r.lines,
              ]);
              setTop(0);
            }
          });
        }
      }
      if (input === "R") void session.retry();
      if (input === "j" || key.downArrow)
        setTop((t) => Math.min(Math.max(0, rows.length - size[1] + 2), t + 1));
      if (input === "k" || key.upArrow) setTop((t) => Math.max(0, t - 1));
      if (key.ctrl && input === "d")
        setTop((t) => Math.min(rows.length - 1, t + Math.max(1, size[1] - 3)));
      if (key.ctrl && input === "u")
        setTop((t) => Math.max(0, t - size[1] + 3));
      if (input === "g") setTop(0);
      if (input === "G") setTop(Math.max(0, rows.length - size[1] + 2));
      if (input === "h" || key.leftArrow) setLeft((n) => Math.max(0, n - 4));
      if (input === "l" || key.rightArrow) setLeft((n) => n + 4);
    });
    const shown = help
      ? [
          "Read-only local review document",
          "j/k arrows: scroll; Ctrl-d/u: page; g/G: first/last",
          "h/l: pan; s: approximation/source; Enter: pin at top row",
          "/: search forward; n/N repeat; Tab: section outline",
          "R: reload; ?: help; q/Ctrl-C: exit",
          "Original Mermaid source is always visible. No links execute.",
        ]
      : outline
        ? (snapshot?.document?.blocks
            .filter((b) => b.kind === "heading" && b.level === 2)
            .map((b) => b.raw.trim()) ?? [])
        : rows;
    const [width, height] = size,
      tokens = snapshot?.theme.tokens ?? {};
    return React.createElement(
      Box,
      { flexDirection: "column", width, height: Math.max(1, height - 1) },
      React.createElement(
        Text,
        { color: tokens.fg, wrap: "truncate" },
        viewport(shown, {
          width,
          height,
          top: help ? 0 : top,
          left: help ? 0 : left,
        }).join("\n"),
      ),
      React.createElement(
        Text,
        { color: tokens.muted, wrap: "truncate" },
        safeText(
          query !== null
            ? `/${query}`
            : `BOARD ${snapshot?.stale ? "STALE · " : ""}${top + 1}/${rows.length} · ${snapshot?.theme.id ?? "ansi"} · ? help · q close`,
        ),
      ),
    );
  }
  const ui = render(React.createElement(App), {
    exitOnCtrlC: false,
    patchConsole: false,
  });
  const stop = () => ui.unmount();
  process.once("SIGTERM", stop);
  process.once("SIGHUP", stop);
  try {
    await ui.waitUntilExit();
  } finally {
    session.close();
    renderer.close();
    ui.unmount();
    process.off("SIGTERM", stop);
    process.off("SIGHUP", stop);
  }
}
