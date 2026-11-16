// Workspace dialog, opened by ctrl-space then b in any layout.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, v_virtual_list, VirtualListScrollHandle, Scrollbar } from "gpui-base";
import { spaces, run, closeOverlay, props, theme } from "herdr";

const STATUS_COLORS = { working: "#88c0d0", blocked: "#bf616a", done: "#a3be8c", idle: "#4c566a" };

export default class SpaceSwitch extends View {
  init(_props, cx) {
    this.query = "";
    this.selected = spaces().find((space) => space.active)?.id ?? null;
    this.scroll = VirtualListScrollHandle.new();
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(50, () => this.handle.focus());
  }

  close() { this.scroll.release(); }
  dismiss() { closeOverlay(props().overlay); }

  choose(space) {
    if (!space) return;
    // Restore the underlying keyboard focus before changing workspace.
    this.dismiss();
    run("space.select", { id: space.id });
  }

  filtered() {
    const query = this.query.toLowerCase();
    return spaces().filter((space) => space.name.toLowerCase().includes(query));
  }

  keyDown(e, cx) {
    const rows = this.filtered();
    const current = Math.max(0, rows.findIndex((space) => space.id === this.selected));
    const key = e.key_char ?? e.key;
    const modified = e.modifiers.control || e.modifiers.platform || e.modifiers.alt;
    if (e.key === "escape") this.dismiss();
    else if (e.key === "enter") this.choose(rows[current]);
    else if (["up", "down"].includes(e.key) || ["ctrl-n", "ctrl-p"].includes(e.keystroke)) {
      if (rows.length) {
        const delta = e.key === "up" || e.keystroke === "ctrl-p" ? -1 : 1;
        const index = (current + delta + rows.length) % rows.length;
        this.selected = rows[index].id;
        this.scroll.scroll_to_item(index, "center");
      }
    } else if (!modified && !this.query && /^[1-9]$/.test(key)) {
      this.choose(spaces().find((space) => space.index === Number(key)));
    } else if (e.key === "backspace") {
      this.query = Array.from(this.query).slice(0, -1).join("");
      this.resetSelection();
    } else if (!modified && (e.key === "space" || Array.from(key).length === 1)) {
      this.query += e.key === "space" ? " " : key;
      this.resetSelection();
    }
    cx.stop_propagation();
    cx.notify();
  }

  resetSelection() {
    const rows = this.filtered();
    this.selected = rows[0]?.id ?? null;
    if (rows.length) this.scroll.scroll_to_item(0);
  }

  row(space, t) {
    const status = space.status ?? "idle";
    return h_flex().id(`space-${space.id}`).h(44).px(10).gap(10).items_center()
      .bg(space.id === this.selected ? t.selected : t.popover)
      .on_hover((hovered, cx) => {
        if (hovered && this.selected !== space.id) { this.selected = space.id; cx.notify(); }
      })
      .on_click(() => this.choose(space))
      .child(div().w(22).flex_none().text_color(t.dim).child(String(space.index)))
      .child(div().flex_none().text_color(t[status] ?? STATUS_COLORS[status]).child("●"))
      .child(v_flex().flex_1().min_w(0)
        .child(div().truncate().text_color(t.foreground).child(space.name))
        .when(Boolean(space.branch), (el) => el.child(div().truncate().text_size(11).text_color(t.dim).child(space.branch))))
      .child(div().flex_none().text_size(11).text_color(t.accent).child(space.active ? "active" : ""))
      .child(div().flex_none().text_size(11).text_color(t.muted)
        .child(`${space.tabs.length} ${space.tabs.length === 1 ? "tab" : "tabs"}`));
  }

  render() {
    const t = theme();
    const rows = this.filtered();
    if (!rows.some((space) => space.id === this.selected)) this.selected = rows[0]?.id ?? null;
    return v_flex().id("space-switch").track_focus(this.handle).size_full().p(14).gap(10)
      .bg(t.popover).text_size(13)
      .on_key_down((e, cx) => this.keyDown(e, cx))
      .child(h_flex().flex_none().justify_between()
        .child(div().font_semibold().text_color(t.foreground).child("Workspaces"))
        .child(div().text_size(11).text_color(t.dim).child("esc close")))
      .child(div().flex_none().pb(8).border_b_1().border_color(t.border)
        .text_color(this.query ? t.foreground : t.muted).child(`Filter: ${this.query || "type a workspace name…"}`))
      .child(rows.length ? v_flex().relative().flex_1().min_h(0)
        .child(v_virtual_list("space-switch-list", rows.length, 44,
          (index) => rows[index].id,
          (range) => rows.slice(range.start, range.end).map((space) => this.row(space, t)))
          .track_scroll(this.scroll).flex_1())
        .child(Scrollbar.vertical("space-switch-list").absolute().inset_0())
        : div().flex_1().text_color(t.muted).child("No matching workspaces"))
      .child(div().flex_none().text_size(11).text_color(t.dim)
        .child("↑ ↓ / ctrl-n ctrl-p select · enter switch · 1–9 quick switch"));
  }
}
