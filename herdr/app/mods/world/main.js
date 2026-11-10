// World: the shown workspace as a small 3D clearing. Each tab is an NPC (its
// agent); walk up and right-click to "talk": the tab's terminal opens over
// the world as a dialog.
//
// Drawing: three.js does the scene math (Projector -> screen triangles) and
// GPUI paints them as native paths (gpui-shell has no WebGL). Faces are
// depth-sorted and runs of one color share a path.
//
// Controls (the world must have the keyboard: click it once):
//   W/S forward/back, A/D turn (strafe while right button held), Q/E strafe,
//   hold right mouse + move: turn character and camera together,
//   right-click an NPC within reach: talk (its terminal pops over).
import { View, div, PathBuilder } from "gpui-kit";
import { v_flex } from "gpui-base";
import { spaces, focused, agents, panes, openOverlay } from "herdr";
import * as THREE from "./vendor/three.module.min.js";
import { Projector, RenderableFace } from "./vendor/Projector.js";
import { buildWorld, makeNpc, makeHero } from "./content.js";

const FRAME_MS = 33;
const REACH = 4.2;           // talk distance
const NPC_RING = 4.6;
const SKY_TOP = "#6f9fd0", SKY_LOW = "#cfe3f2", GROUND = "#5b8a46", GROUND_FAR = "#7aa35c";
const STATUS = { working: ["…", "#EBCB8B"], blocked: ["!", "#BF616A"], done: ["!", "#EBCB8B"], idle: ["", "#D8DEE9"] };

function hash(s) { let h = 2166136261; for (const c of String(s)) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0; return h; }
const NPC_COLORS = [0xc79c6e, 0xf58cba, 0xff7d0a, 0xffffff, 0x0070de, 0x69ccf0, 0x9482c9, 0xfff569, 0xabd473];

export default class World extends View {
  init(_props, cx) {
    this.size = { width: 1200, height: 800 };
    this.focus = cx.focus_handle();
    this.held = new Set();
    this.drag = null;        // { x, y, moved, at }
    this.mouse = { x: 0, y: 0 };
    this.player = { x: 0, z: 10, yaw: 0 };
    this.stats = { faces: 0, paths: 0, ms: 0 };
    this.hint = "Click the world, then WASD · Q/E strafe · hold right-click to turn · right-click an NPC to talk · ⌃Space b: workspaces";
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(60, 1.5, 0.3, 90);
    this.projector = new Projector();
    const world = buildWorld(THREE, 7);
    this.colliders = world.userData.colliders || [];
    this.scene.add(world);
    this.hero = makeHero(THREE);
    this.scene.add(this.hero);
    this.npcs = new Map();   // tabId -> { group, x, z, tab, terminal, color, head }
    this.loop = null;
    this.focus.focus();
  }

  // NPCs = tabs of the shown space.
  syncNpcs() {
    const f = focused();
    const space = spaces().find((s) => s.id === (f && f.space)) || spaces().find((s) => s.active);
    const tabs = space ? space.tabs : [];
    const seen = new Set();
    tabs.forEach((tab, i) => {
      seen.add(tab.id);
      let n = this.npcs.get(tab.id);
      if (!n) {
        const h = hash(tab.id);
        const color = NPC_COLORS[h % NPC_COLORS.length], accent = NPC_COLORS[(h >> 8) % NPC_COLORS.length];
        const group = makeNpc(THREE, { color, accent });
        n = { group, head: group.userData.head || 1.8 };
        this.scene.add(group);
        this.npcs.set(tab.id, n);
      }
      const a = (i / Math.max(tabs.length, 1)) * Math.PI * 2 + Math.PI / 2;
      const r = tabs.length === 1 ? 0 : NPC_RING;
      n.x = Math.cos(a) * r; n.z = -Math.sin(a) * r * 0.8;
      n.tab = tab;
      const ag = agents().find((x) => x.tab === tab.id);
      const pn = panes().find((p) => p.tab === tab.id && p.terminal);
      n.terminal = ag ? ag.address : pn ? pn.terminal : null;
      n.app = ag ? ag.program?.name || ag.app : pn ? pn.program?.name : "";
      n.group.position.set(n.x, 0, n.z);
    });
    for (const [id, n] of this.npcs) if (!seen.has(id)) { this.scene.remove(n.group); this.npcs.delete(id); }
  }

  blocked(x, z) {
    for (const c of this.colliders) if ((x - c.x) ** 2 + (z - c.z) ** 2 < (c.r + 0.4) ** 2) return true;
    for (const n of this.npcs.values()) if ((x - n.x) ** 2 + (z - n.z) ** 2 < 0.9 ** 2) return true;
    return x * x + z * z > 27 ** 2;
  }

  move(dx, dz) {
    const p = this.player;
    if (!this.blocked(p.x + dx, p.z)) p.x += dx;
    if (!this.blocked(p.x, p.z + dz)) p.z += dz;
  }

  step(dt) {
    const p = this.player, k = this.held, sp = 5.5 * dt;
    const fx = -Math.sin(p.yaw), fz = -Math.cos(p.yaw), rx = Math.cos(p.yaw), rz = -Math.sin(p.yaw);
    if (k.has("w")) this.move(fx * sp, fz * sp);
    if (k.has("s")) this.move(-fx * sp * 0.6, -fz * sp * 0.6);
    const strafeA = k.has("q") || (k.has("a") && this.drag), strafeD = k.has("e") || (k.has("d") && this.drag);
    if (strafeA) this.move(-rx * sp * 0.8, -rz * sp * 0.8);
    if (strafeD) this.move(rx * sp * 0.8, rz * sp * 0.8);
    if (k.has("a") && !this.drag) p.yaw += 2.4 * dt;
    if (k.has("d") && !this.drag) p.yaw -= 2.4 * dt;
  }

  wake(cx) {
    if (this.loop) return;
    let last = Date.now();
    this.loop = cx.timer.every(FRAME_MS, (cx) => {
      const now = Date.now();
      this.step(Math.min(0.1, (now - last) / 1000)); last = now;
      cx.notify();
      if (!this.held.size && !this.drag) { this.loop.cancel(); this.loop = null; }
    });
  }

  toScreen(v) {
    const { width: W, height: H } = this.size;
    const q = v.clone().project(this.camera);
    if (q.z < -1 || q.z > 1) return null;
    return { x: (q.x + 1) * 0.5 * W, y: (1 - q.y) * 0.5 * H, z: q.z };
  }

  paint() {
    const t0 = Date.now();
    const { width: W, height: H } = this.size, p = this.player, cam = this.camera;
    this.hero.position.set(p.x, 0, p.z);
    this.hero.rotation.y = p.yaw;
    for (const n of this.npcs.values()) {
      const d2 = (p.x - n.x) ** 2 + (p.z - n.z) ** 2;
      if (d2 < 49) n.group.rotation.y = Math.atan2(p.x - n.x, p.z - n.z);
    }
    cam.aspect = W / H; cam.updateProjectionMatrix();
    cam.position.set(p.x + Math.sin(p.yaw) * 6.5, 3.4, p.z + Math.cos(p.yaw) * 6.5);
    cam.lookAt(p.x, 1.3, p.z);
    this.scene.updateMatrixWorld();

    // Backdrop: sky, then ground from the horizon down.
    const far = this.toScreen(new THREE.Vector3(p.x - Math.sin(p.yaw) * 85, 0, p.z - Math.cos(p.yaw) * 85));
    const horizon = Math.max(0, Math.min(H, far ? far.y : H * 0.4));
    const els = [
      div().absolute().left(0).top(0).w(W).h(horizon).bg(SKY_LOW).child(div().size_full().bg(SKY_TOP).opacity(0.55)),
      div().absolute().left(0).top(horizon).w(W).h(Math.max(0, H - horizon)).bg(GROUND)
        .child(div().w_full().h(Math.min(40, H - horizon)).bg(GROUND_FAR)),
    ];

    const data = this.projector.projectScene(this.scene, cam, true, false);
    const sx = (v) => (v.x + 1) * 0.5 * W, sy = (v) => (1 - v.y) * 0.5 * H;
    let run = null, runColor = null, faces = 0, paths = 0;
    const flush = () => { if (run) { els.push(div().absolute().inset_0().child(window.paint_path(run.build(), runColor))); paths++; } run = null; };
    for (const el of data.elements) {
      if (!(el instanceof RenderableFace)) continue;
      const a = el.v1.positionScreen, b = el.v2.positionScreen, c = el.v3.positionScreen;
      if (a.z < -1 || a.z > 1 || b.z < -1 || b.z > 1 || c.z < -1 || c.z > 1) continue;
      const n = el.normalModel;
      const shade = 0.62 + 0.38 * Math.max(0, n.y * 0.7 + n.x * 0.25 + n.z * 0.15);
      const col = "#" + el.material.color.clone().multiplyScalar(shade).getHexString();
      if (col !== runColor) { flush(); run = PathBuilder.fill(); runColor = col; }
      run.add_polygon([[sx(a), sy(a)], [sx(b), sy(b)], [sx(c), sy(c)]], true);
      faces++;
    }
    flush();

    // Nameplates.
    for (const n of this.npcs.values()) {
      const s = this.toScreen(new THREE.Vector3(n.x, n.head + 0.45, n.z));
      if (!s) continue;
      const near = (p.x - n.x) ** 2 + (p.z - n.z) ** 2 <= REACH * REACH;
      const [mark, markColor] = STATUS[n.tab.status] || STATUS.idle;
      els.push(div().absolute().left(s.x - 90).top(s.y - (mark ? 44 : 22)).w(180).child(v_flex().w_full().items_center()
        .child(mark ? div().text_size(22).font_semibold().text_color(markColor).child(mark) : div())
        .child(div().px(6).bg(near ? "#1E222AE6" : "#1E222A99").text_size(12).font_semibold()
          .text_color(near ? "#ECEFF4" : "#D8DEE9").child(n.tab.name))
        .child(div().text_size(10).text_color("#2E3440").child(near ? "right-click to talk" : n.app || ""))));
    }
    this.stats = { faces, paths, ms: Date.now() - t0 };
    return els;
  }

  // Right-click without dragging: talk to the NPC under the pointer.
  talkAt(x, y) {
    const p = this.player;
    let best = null;
    for (const n of this.npcs.values()) {
      const top = this.toScreen(new THREE.Vector3(n.x, n.head, n.z)), foot = this.toScreen(new THREE.Vector3(n.x, 0, n.z));
      if (!top || !foot) continue;
      const h = foot.y - top.y, w = Math.max(24, h * 0.55);
      if (x < top.x - w / 2 || x > top.x + w / 2 || y < top.y - 20 || y > foot.y) continue;
      if (!best || foot.z < best.z) best = { n, z: foot.z };
    }
    if (!best) return;
    const n = best.n, d = Math.hypot(p.x - n.x, p.z - n.z);
    if (d > REACH) { this.hint = `${n.tab.name} is too far away. Walk closer.`; return; }
    if (!n.terminal) { this.hint = `${n.tab.name} has nothing to say (no terminal).`; return; }
    this.hint = `Talking to ${n.tab.name}. Click outside the window to leave.`;
    openOverlay({ kind: "dialog", width: 0.74, height: 0.78, layout: { id: "talk", type: "block", content: { terminal: n.terminal } } });
  }

  render(cx) {
    this.syncNpcs();
    const key = (e) => String(e.key || "").toLowerCase();
    const plain = (e) => !(e.modifiers && (e.modifiers.control || e.modifiers.platform || e.modifiers.alt));
    const root = div().id("root").size_full().relative().overflow_hidden().bg(SKY_TOP)
      .track_focus(this.focus)
      .on_size_change((size, cx) => { this.size = size; cx.notify(); })
      .on_key_down((e, cx) => {
        const k = key(e);
        if (plain(e) && k.length === 1 && "wasdqe".includes(k)) { this.held.add(k); this.wake(cx); cx.stop_propagation(); }
      })
      .on_key_up((e) => { this.held.delete(key(e)); })
      .on_mouse_down("left", () => { this.focus.focus(); })
      .on_mouse_down("right", (e, cx) => {
        this.focus.focus();
        this.drag = { x: this.mouse.x, moved: 0, at: Date.now() };
        this.wake(cx);
      })
      .on_mouse_up("right", (_e, cx) => {
        const d = this.drag; this.drag = null;
        if (d && d.moved < 6 && Date.now() - d.at < 400) { this.talkAt(this.mouse.x, this.mouse.y); cx.notify(); }
      })
      .on_mouse_move((e) => {
        const lp = e.local_position || e.position;
        if (this.drag) { const dx = lp.x - this.mouse.x; this.drag.moved += Math.abs(dx); this.player.yaw -= dx * 0.008; }
        this.mouse = { x: lp.x, y: lp.y };
      });
    root.children(this.paint());
    root.child(div().absolute().left(10).top(8).px(6).py(2).bg("#1E222AB3").text_size(11).text_color("#ECEFF4")
      .child(`${this.hint}   ·   ${this.stats.faces} faces / ${this.stats.paths} paths / ${this.stats.ms} ms`));
    return root;
  }
}
