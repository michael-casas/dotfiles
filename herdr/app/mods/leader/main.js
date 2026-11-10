// Leader key (ctrl-space): a TUI-style hint popup that waits for one key.
// Built for macOS, which takes Ctrl+arrows (Mission Control), Cmd+Ctrl+Space
// (emoji) and Cmd+Opt+Space (Finder search) before Herdr sees them.
//
//   /           find a tab or agent by tab name (Herdr's picker)
//   b           switch workspace
//   h j k l     focus pane left/down/up/right (arrows too); repeatable
//   ctrl-space  send a literal ctrl-space to the focused terminal
//
// keys.json: "ctrl-space": "mod.open:leader" in global and terminal, and
// "mod:leader": { "ctrl-space": "leader.send-prefix" } so a second press
// reaches the program instead of closing this popup.
// Runs `hc keys` only for the literal ctrl-space.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, theme, props, closeOverlay, nextCommand, focused, shared, layouts, hc } from "herdr";

const REPEAT_MS = 600;
const omarchy = () => shared("layout") === "omarchy";
const has = (name) => layouts().includes(name);

// [keys, label, action, repeatable]. action: [command, args] or a function.
const BINDINGS = [
  [["/"], "find tab / agent", ["mod.open", { name: "picker" }]],
  [["b"], "switch workspace", ["mod.open", { name: "space-switch" }]],
  [["h", "left"], "pane left", ["pane.go", { direction: "left" }], true],
  [["j", "down"], "pane down", ["pane.go", { direction: "down" }], true],
  [["k", "up"], "pane up", ["pane.go", { direction: "up" }], true],
  [["l", "right"], "pane right", ["pane.go", { direction: "right" }], true],
  [["\\", "|"], "split right", ["pane.split", { direction: "right" }]],
  [["-"], "split down", ["pane.split", { direction: "down" }]],
  [["z"], "zoom pane", ["pane.zoom", {}]],
  [["x"], "close pane", ["pane.close", {}]],
  [["c"], "new tab", ["tab.new", {}]],
  [["n"], "next tab", ["tab.next", {}], true],
  [["p"], "previous tab", ["tab.prev", {}], true],
  [["]"], "next space", ["space.next", {}], true],
  [["["], "previous space", ["space.prev", {}], true],
  [["1-9"], "tab 1–9", null],
  [[":"], "command palette", () => (omarchy() ? run("mod.open", { name: "omarchy-palette" }) : run("app.palette"))],
  [["t"], "themes", () => (has("omarchy") ? run("mod.open", { name: "omarchy-themes" }) : run("app.settings", { section: "look" }))],
  [["?"], "all key bindings", () => (has("omarchy") ? run("mod.open", { name: "omarchy-keys" }) : run("app.help"))],
  [["s"], "toggle sidebar", ["layout.toggle", { id: "sidebar" }]],
  [["L"], "switch layout", ["layout.switch", {}]],
];

export default class Leader extends View {
  init(_props, cx) {
    this.repeat = false;
    this.gen = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(50, () => this.handle.focus());
    // A second ctrl-space arrives as a mod command (keys.json "mod:leader").
    cx.spawn(async (cx) => {
      for (;;) {
        if ((await nextCommand()) === "send-prefix") await this.sendPrefix();
        cx.notify();
      }
    });
  }

  close() { closeOverlay(props().overlay); }

  async sendPrefix() {
    const t = focused()?.terminal;
    this.close();
    if (t) await hc(["keys", t, "ctrl+space"]);
  }

  find(e) {
    const k = e.key_char ?? e.key;
    if (/^[1-9]$/.test(k)) return [[k], `tab ${k}`, ["tab.select", { index: Number(k) }]];
    return BINDINGS.find(([keys]) => keys.includes(k) || keys.includes(e.key));
  }

  act(b, cx) {
    const [, , action, repeatable] = b;
    // Close first so commands that open their own popup (picker, palette) get the keyboard.
    if (!repeatable) this.close();
    if (typeof action === "function") action();
    else if (action) run(action[0], action[1]);
    if (!repeatable) return;
    this.repeat = true;
    const gen = ++this.gen;
    cx.timer.after(REPEAT_MS, () => { if (gen === this.gen) this.close(); });
    cx.notify();
  }

  render() {
    const t = theme();
    const chip = (s) => div().flex_none().w(64).text_color(t.accent).child(s);
    const row = ([keys, label, , repeatable]) => h_flex().gap(10).h(20).items_center()
      .child(chip(keys.join(" ")))
      .child(div().flex_1().truncate().text_color(t.foreground).child(label))
      .when(Boolean(repeatable), (el) => el.child(div().text_color(t.dim).child("repeat")));
    return v_flex().id("leader").track_focus(this.handle).size_full().p(14).gap(8)
      .bg(t.popover).border_1().border_color(t.accent).text_size(12)
      .on_key_down((e, cx) => {
        if (e.key === "escape") { this.close(); return cx.stop_propagation(); }
        if (["shift", "control", "alt", "platform", "function"].includes(e.key)) return;
        const b = this.find(e);
        if (b && (!this.repeat || b[3])) { this.act(b, cx); return cx.stop_propagation(); }
        this.close();
      })
      .child(h_flex().justify_between().pb(6).border_b_1().border_color(t.border)
        .child(div().font_semibold().text_color(t.foreground).child(this.repeat ? `repeat · ${REPEAT_MS} ms` : "ctrl-space · waiting for a key"))
        .child(div().text_color(t.dim).child("esc cancel · ^space send")))
      .child(v_flex().flex_none().children(BINDINGS.map(row)));
  }
}
