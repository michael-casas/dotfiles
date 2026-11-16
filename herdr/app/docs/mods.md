# Mods: writing panels and plugins

A mod is a folder of JavaScript that draws native UI inside the window: a
sidebar list, a tab bar, a pane header, a popup, a floating drawer or a
pane beside terminals. Herdr's own sidebar, tab bar, menus, dialogs and
toasts are mods too. Read them as examples, but never edit them in place.

## Runtime: gpui-shell, not a browser

- Mods use **gpui-kit's gpui-shell**: QuickJS running on the host thread.
  The script describes **GPUI** elements and Rust draws them on the GPU.
- There is **no DOM, HTML, CSS, WebView, Node or `setTimeout`**.
- Herdr carries its own copy of gpui-kit with additions (`frames`, `loop`).
  The installed `gpui-kit.d.ts` and `herdr.d.ts` in the app home are the
  truth for your version. They are rewritten on every start.
- Imports: `"gpui-kit"` (`View`, `div`, `svg`, `image`, …), `"gpui-base"`
  (`v_flex`, `h_flex`, unstyled `Button`, `Checkbox`, `Switch`, `Input`,
  `TextView`, `Editor`, `Scrollbar`, …), `"herdr"` (app data and
  commands), `"fs/promises"`.

## Folder layout

```text
~/.config/herdr-app/mods/<name>/
  main.js     required; default-exports a class extending View
  mod.json    { "place": "right"|"left"|"top"|"bottom"|"none", "size": 320,
                "focusable": true?, "overlay": { "width", "height" }?, "title"? }
  *.js        more modules, imported as "./ui.js"
  *.svg       icons, referenced as "mods/<name>/icon.svg"
  fonts/      optional .ttf or .otf files loaded with the layout
```

- The first time Herdr sees a folder, it docks one copy where `place` says.
  `"none"` means the mod only appears where a layout or another mod puts
  it. After that, the layouts decide.
- Saving any file hot-reloads every copy in place. A broken save keeps the
  old build running and reports the error in `herdr-app status`.

## Minimal mod

```js
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, spaces, theme, run } from "herdr";

export default class Branches extends View {
  init(_props, cx) {
    this.branch = {};
    cx.timer.every(3000, (cx) => this.refresh(cx));   // data timer, gentle
    this.refresh(cx);
  }
  refresh(cx) {
    cx.spawn(async (cx) => {
      for (const p of spaces()) {
        const r = await exec("git", ["branch", "--show-current"], { cwd: p.folder, on: p.machine });
        this.branch[p.id] = r.stdout.trim();
      }
      cx.notify();
    });
  }
  render(cx) {
    const t = theme();
    return v_flex().size_full().bg(t.surface).p(10).gap(4).text_size(13).children(
      spaces().map((p) =>
        h_flex().id(`b-${p.id}`).gap(8).hover((s) => s.bg(t.raised))
          .on_click(() => run("space.select", { id: p.id }))
          .child(div().text_color(p.active ? t.foreground : t.muted).child(p.name))
          .child(div().text_color(t.dim).child(this.branch[p.id] ?? ""))));
  }
}
```

## Rules (hard requirements)

1. `init(props, cx)` runs once. `render(cx)` reruns after `cx.notify()`
   and whenever live data changes (spaces, agents, terminals, focus, theme,
   shared state). **Do not poll live data.**
2. **Never store a `cx` to use later.** Every callback gets its own:
   `on_click((e, cx) => …)`, `cx.spawn(async (cx) => …)`,
   `cx.timer.every(ms, (cx) => …)`.
3. Instead of `setTimeout` or `setInterval`, use `cx.timer`. Instead of
   top-level `await`, call `cx.spawn` in `init`.
4. Module scope runs once per source version and is shared by every copy.
   Keep state and host calls in `init` or the constructor. Keep side
   effects off `globalThis`.
5. **Animate natively, never with a timer.** Every mod redraw repaints the
   whole window. Use `.frames([...], ms)`, `svg(x).spin(ms)`,
   `.loop("opacity"|"width"|"height"|"left"|"top", {from, to, period})` and
   `.transition(...)`. Timers are for data only, and only as often as the
   data changes.
6. Use `theme()` colors so the mod follows the person's theme. Use
   `settings().font_family` for code text, not a hardcoded font.
7. Mods don't know their block's size. Measure it with
   `.id("root").on_size_change((size, cx) => …)`.
8. Optional `async close(cx)` runs at teardown. Cleanup gets at most
   250 ms. On quit, only `exec` and `run("terminal.kill")` are guaranteed to
   go out.
9. Hidden copies keep running, timers included, so poll gently.
   `<mod>.<command>` keys reach shown copies only.

## The `herdr` module (summary; `herdr.d.ts` is complete)

| Group | API |
|---|---|
| Live data | `spaces()`, `machines()`, `agents()`, `terminals()`, `panes()`, `focused()`, `layout()`, `layouts()`, `theme()`, `settings()`, `keys()`, `commands()` |
| Act | `run(command, args)`, `setAgentOrder(addresses)` (call it on render if the mod lists agents) |
| Overlays | `openOverlay({ mod, props, kind: "dialog"\|"popup"\|"window", width, height, at, frame, key, keep, layout })`, `closeOverlay(id)`, `notify({ title, body, level, icon, timeout, action })` |
| Machine | `exec(cmd, args, { cwd, on, timeout })` (runs in the person's real environment; `on: space.machine` runs it remotely), `hc(args)`, `home()`, `appHome()`, `playSound()`, `knownAgents({ on })`, `pickFolder()` |
| Files | `readTextFile(path, { on })`, `writeTextFile(path, text, expected)` (here only), `watchFolder(dir)` |
| This copy | `props()`, `shared(key)`, `setShared(key, value)`, `nextCommand()` (key commands sent to this mod), `placement()` (when floating) |
| Built-ins | `localStorage` (per copy), `console.log`, `fetch`, `fs/promises` (reads anywhere in home; writes only under the app home) |

## Common patterns

- **Key commands:**
  `cx.spawn(async (cx) => { for (;;) { const c = await nextCommand(); …; cx.notify(); } })`.
  Bind them in `keys.json` as `"<mod>.<command>"`.
- **Focusable panel:** add `"focusable": true` to `mod.json`. When the mod
  receives `"focus"` from `nextCommand()`, call `this.handle.focus()` and
  handle keys with `.track_focus(h).on_key_down(...)`. Leave with
  `run("pane.go", {direction})`.
- **Pane header mod:** reads `props().pane` and `props().terminal`, takes
  facts from `panes()`, and runs `pane.*` commands with that pane.
- **One mod, many roles:** pass `props: { role: "rail" }` from different
  layout blocks and branch on `props().role` (see the gallery's Pasture
  recipe).
- **Viewer beside a shell:**
  `run("pane.split", { direction: "right", mod: "<name>", props: { file } })`.
- **Watch files:**
  `for (;;) { await watchFolder(dir); reload(); cx.notify(); }` inside
  `cx.spawn`.
- **Assets:** `image("mods/<name>/logo.svg")` draws full color;
  `svg("mods/<name>/icon.svg")` is tinted with the text color.

## Changing a shipped mod

```sh
herdr-app do mod.clone '{"name":"tabs","as":"tui-tabs"}'
```

Then point your layout's block at `"mod": "tui-tabs"`. The clone rewrites
its own asset paths and overlay names. It records `cloned_from` and never
receives upstream updates. This is how to square off the tab pills and
sidebar rows that `tui.json` cannot reach.

## Definition of done

1. `herdr-app check ~/.config/herdr-app/mods/<name>` passes. It loads the
   mod once and checks the first render, but does not cover later async
   states.
2. `herdr-app status` shows no `errors`.
3. You have seen the mod in the window (`herdr-app shot` or cua-driver;
   see [verification.md](verification.md)).
4. Disclose it if the mod reaches the network, runs programs (`exec`,
   `hc`) or reads files outside its folder.

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "What mods are written in", "Mods", "UI", "The herdr module", "Keep in mind"
- https://github.com/herdrdev/herdr-app/blob/master/docs/mods.md
- https://gpui-kit.com/shell (gpui-shell runtime model)
- https://herdr.dev/mods/herdrdev/tmux-prefix, https://herdr.dev/layouts/herdrdev/pasture (recipes)
