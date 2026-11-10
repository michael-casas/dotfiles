// World: the shown workspace as a small 3D camp. Each tab is an NPC (its
// agent) gathered around a central campfire; walk up and right-click one to
// "talk": its terminal opens over the world as a dialog. Terminals labeled
// `world.visit=<space id>` join as visitors.
//
// Drawing: three.js does the scene math (Projector -> screen triangles) and
// GPUI paints them as native paths (gpui-shell has no WebGL). Faces are
// depth-sorted and runs of one color share a path.
//
// Controls (click the world once so it has the keyboard):
//   W/S forward/back, A/D turn (strafe while right button held), Q/E strafe,
//   Space jump, mouse wheel zoom,
//   hold left + move: orbit the camera 360° around the character (and tilt),
//   hold right + move: turn the character with the camera,
//   quick right-click on an NPC within reach: talk.
// While a button is held the cursor is hidden by bin/world-cursor (a small
// native helper, tools/cursor), which also recenters it so turning never stops.
import { View, div, PathBuilder } from "gpui-kit";
import { v_flex } from "gpui-base";
import { spaces, focused, agents, panes, terminals, openOverlay, exec, appHome } from "herdr";
import * as THREE from "./vendor/three.module.min.js";
import { Projector, RenderableFace } from "./vendor/Projector.js";
import { CAMP, buildCamp, npcSlots } from "./camp.js";
import { makeHero, makeNpc, animate } from "./figures.js";

const MOVE_MS = 33, AMBIENT_MS = 125;       // ~30 fps while moving, 8 fps idle (fire, breathing)
const REACH = 3.6;
const GRAVITY = 20, JUMP_V = 6.8;
const RECENTER_PX = 140;
const SKY_TOP = "#1d2b44", SKY_LOW = "#4a5f86", GROUND = "#33502f", GROUND_FAR = "#3f6138";
const STATUS = { working: ["…", "#EBCB8B"], blocked: ["!", "#BF616A"], done: ["!", "#EBCB8B"], idle: ["", "#D8DEE9"] };
const NPC_COLORS = [0xc79c6e, 0xf58cba, 0xff7d0a, 0xe5e9f0, 0x0070de, 0x69ccf0, 0x9482c9, 0xfff569, 0xabd473];

function hash(s) { let h = 2166136261; for (const c of String(s)) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0; return h; }

export default class World extends View {
  init(_props, cx) {
    this.size = { width: 1200, height: 800 };
    this.focus = cx.focus_handle();
    this.held = new Set();
    this.drag = null;          // { button, x0, y0, moved, at }
    this.mouse = { x: 0, y: 0 };
    this.player = { x: CAMP.spawn.x, z: CAMP.spawn.z, y: 0, vy: 0, yaw: CAMP.spawn.yaw, moving: false };
    this.cam = { orbit: 0, pitch: 0.32, dist: 6.5 };
    this.t = 0;
    this.stats = { faces: 0, paths: 0, ms: 0 };
    this.hint = "Click the world · WASD, Q/E strafe, Space jump · hold left: orbit · hold right: turn · wheel: zoom · right-click an NPC to talk · ⌃Space b: workspaces";
    this.cursorBin = `${appHome()}/mods/world/bin/world-cursor`;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(60, 1.5, 0.3, 60);
    this.projector = new Projector();
    const camp = buildCamp(THREE, 7);
    this.colliders = camp.userData.colliders || [];
    this.flames = camp.userData.flames || [];
    this.scene.add(camp);
    this.hero = makeHero(THREE);
    this.scene.add(this.hero);
    this.npcs = new Map();
    this.loop = null;
    this.last = Date.now();
    this.focus.focus();
    cx.timer.every(AMBIENT_MS, (cx) => { if (!this.loop && this.focus.is_focused()) this.tick(cx); });
  }

  // NPCs = tabs of the shown space + visitors, placed at the camp's seats.
  syncNpcs() {
    const f = focused();
    const space = spaces().find((s) => s.id === (f && f.space)) || spaces().find((s) => s.active);
    const visitors = space ? terminals().filter((t) => t.labels && t.labels["world.visit"] === space.id && t.state === "live")
      .map((t) => ({ id: `visit:${t.address}`, visitor: t,
        name: t.labels["world.name"] || String(t.labels.where || t.name || t.address).split(" / ").pop(),
        status: typeof t.status === "string" ? t.status : t.report && t.report.state })) : [];
    const list = space ? [...space.tabs, ...visitors] : [];
    const slots = npcSlots(list.length);
    const seen = new Set();
    list.forEach((tab, i) => {
      seen.add(tab.id);
      let n = this.npcs.get(tab.id);
      if (!n) {
        const h = hash(tab.id);
        const group = makeNpc(THREE, { color: NPC_COLORS[h % NPC_COLORS.length], accent: NPC_COLORS[(h >> 8) % NPC_COLORS.length], seed: h });
        n = { group, head: group.userData.head || 1.8 };
        this.scene.add(group);
        this.npcs.set(tab.id, n);
      }
      const s = slots[i] || { x: 0, z: -3, yaw: 0 };
      n.x = s.x; n.z = s.z; n.restYaw = s.yaw;
      n.tab = tab;
      if (tab.visitor) {
        n.terminal = tab.visitor.address;
        n.app = `${tab.visitor.program?.name || tab.visitor.report?.app || "terminal"} · visiting`;
      } else {
        const ag = agents().find((x) => x.tab === tab.id);
        const pn = panes().find((p) => p.tab === tab.id && p.terminal);
        n.terminal = ag ? ag.address : pn ? pn.terminal : null;
        n.app = ag ? ag.program?.name || ag.app : pn ? pn.program?.name : "";
      }
      n.group.position.set(n.x, 0, n.z);
    });
    for (const [id, n] of this.npcs) if (!seen.has(id)) { this.scene.remove(n.group); this.npcs.delete(id); }
  }

  blocked(x, z) {
    for (const c of this.colliders) if ((x - c.x) ** 2 + (z - c.z) ** 2 < (c.r + 0.35) ** 2) return true;
    for (const n of this.npcs.values()) if ((x - n.x) ** 2 + (z - n.z) ** 2 < 0.8 ** 2) return true;
    return x * x + z * z > (CAMP.radius - 0.6) ** 2;
  }

  move(dx, dz) {
    const p = this.player;
    if (!this.blocked(p.x + dx, p.z)) p.x += dx;
    if (!this.blocked(p.x, p.z + dz)) p.z += dz;
  }

  step(dt) {
    const p = this.player, k = this.held, sp = 5 * dt, turning = this.drag && this.drag.button === "right";
    const fx = -Math.sin(p.yaw), fz = -Math.cos(p.yaw), rx = Math.cos(p.yaw), rz = -Math.sin(p.yaw);
    const x0 = p.x, z0 = p.z;
    if (k.has("w")) this.move(fx * sp, fz * sp);
    if (k.has("s")) this.move(-fx * sp * 0.6, -fz * sp * 0.6);
    if (k.has("q") || (k.has("a") && turning)) this.move(-rx * sp * 0.8, -rz * sp * 0.8);
    if (k.has("e") || (k.has("d") && turning)) this.move(rx * sp * 0.8, rz * sp * 0.8);
    if (k.has("a") && !turning) p.yaw += 2.4 * dt;
    if (k.has("d") && !turning) p.yaw -= 2.4 * dt;
    if (p.y > 0 || p.vy > 0) { p.vy -= GRAVITY * dt; p.y = Math.max(0, p.y + p.vy * dt); if (p.y === 0) p.vy = 0; }
    p.moving = Math.hypot(p.x - x0, p.z - z0) > 1e-4;
  }

  busy() { return this.held.size || this.drag || this.player.y > 0 || this.player.vy > 0; }

  tick(cx) {
    const now = Date.now();
    const dt = Math.min(0.1, (now - this.last) / 1000);
    this.last = now; this.t += dt;
    this.step(dt);
    cx.notify();
  }

  wake(cx) {
    if (this.loop) return;
    this.last = Date.now();
    this.loop = cx.timer.every(MOVE_MS, (cx) => {
      this.tick(cx);
      if (!this.busy()) { this.loop.cancel(); this.loop = null; }
    });
  }

  cursor(cmd) { exec(this.cursorBin, [cmd], { timeout: cmd === "hold" ? 130000 : 3000 }).catch(() => {}); }

  toScreen(v) {
    const { width: W, height: H } = this.size;
    const q = v.clone().project(this.camera);
    if (q.z < -1 || q.z > 1) return null;
    return { x: (q.x + 1) * 0.5 * W, y: (1 - q.y) * 0.5 * H, z: q.z };
  }

  paint() {
    const t0 = Date.now();
    const { width: W, height: H } = this.size, p = this.player, cam = this.camera, c = this.cam;
    this.hero.position.set(p.x, p.y, p.z);
    this.hero.rotation.y = p.yaw;
    animate(this.hero, { moving: p.moving && (this.held.size > 0), speed: 1, airborne: p.y > 0.02, talking: false }, this.t);
    for (const n of this.npcs.values()) {
      const near = (p.x - n.x) ** 2 + (p.z - n.z) ** 2 < 36;
      n.group.rotation.y = near ? Math.atan2(p.x - n.x, p.z - n.z) : n.restYaw;
      animate(n.group, { moving: false, speed: 0, airborne: false, talking: n.tab.status === "working" }, this.t + (hash(n.tab.id) % 100) / 37);
    }
    this.flames.forEach((f, i) => { const s = 1 + 0.12 * Math.sin(this.t * 9 + i * 2.1) + 0.06 * Math.sin(this.t * 23 + i); f.scale.set(1, s, 1); });

    // Camera: behind the character, plus the orbit offset, tilted by pitch.
    // Pull the camera in when the edge of the camp or a tree/rock is in the way.
    const yaw = p.yaw + c.orbit;
    let dist = c.dist;
    for (; dist > 1.6; dist -= 0.25) {
      const h = Math.cos(c.pitch) * dist, x = p.x + Math.sin(yaw) * h, z = p.z + Math.cos(yaw) * h;
      if (x * x + z * z > (CAMP.radius - 1) ** 2) continue;
      if (this.colliders.some((k) => (x - k.x) ** 2 + (z - k.z) ** 2 < (k.r + 0.5) ** 2)) continue;
      break;
    }
    const horiz = Math.cos(c.pitch) * dist;
    cam.aspect = W / H; cam.updateProjectionMatrix();
    cam.position.set(p.x + Math.sin(yaw) * horiz, p.y + 1.2 + Math.sin(c.pitch) * dist, p.z + Math.cos(yaw) * horiz);
    cam.lookAt(p.x, p.y + 1.2, p.z);
    this.scene.updateMatrixWorld();

    const far = this.toScreen(new THREE.Vector3(cam.position.x - Math.sin(yaw) * 55, 0, cam.position.z - Math.cos(yaw) * 55));
    const horizon = Math.max(0, Math.min(H, far ? far.y : H * 0.3));
    const els = [
      div().absolute().left(0).top(0).w(W).h(horizon).bg(SKY_LOW).child(div().size_full().bg(SKY_TOP).opacity(0.6)),
      div().absolute().left(0).top(horizon).w(W).h(Math.max(0, H - horizon)).bg(GROUND)
        .child(div().w_full().h(Math.min(30, Math.max(0, H - horizon))).bg(GROUND_FAR)),
    ];

    const data = this.projector.projectScene(this.scene, cam, true, false);
    const sx = (v) => (v.x + 1) * 0.5 * W, sy = (v) => (1 - v.y) * 0.5 * H;
    let run = null, runColor = null, faces = 0, paths = 0;
    const flush = () => { if (run) { els.push(div().absolute().inset_0().child(window.paint_path(run.build(), runColor))); paths++; } run = null; };
    for (const el of data.elements) {
      if (!(el instanceof RenderableFace)) continue;
      const a = el.v1.positionScreen, b = el.v2.positionScreen, d = el.v3.positionScreen;
      if (a.z < -1 || a.z > 1 || b.z < -1 || b.z > 1 || d.z < -1 || d.z > 1) continue;
      const n = el.normalModel;
      const shade = 0.6 + 0.4 * Math.max(0, n.y * 0.7 + n.x * 0.25 + n.z * 0.15);
      const col = "#" + el.material.color.clone().multiplyScalar(shade).getHexString();
      if (col !== runColor) { flush(); run = PathBuilder.fill(); runColor = col; }
      run.add_polygon([[sx(a), sy(a)], [sx(b), sy(b)], [sx(d), sy(d)]], true);
      faces++;
    }
    flush();

    for (const n of this.npcs.values()) {
      const s = this.toScreen(new THREE.Vector3(n.x, n.head + 0.4, n.z));
      if (!s) continue;
      const near = (p.x - n.x) ** 2 + (p.z - n.z) ** 2 <= REACH * REACH;
      const [mark, markColor] = STATUS[n.tab.status] || STATUS.idle;
      els.push(div().absolute().left(s.x - 90).top(s.y - (mark ? 44 : 22)).w(180).child(v_flex().w_full().items_center()
        .child(mark ? div().text_size(22).font_semibold().text_color(markColor).child(mark) : div())
        .child(div().px(6).bg(near ? "#1E222AE6" : "#1E222A99").text_size(12).font_semibold()
          .text_color(near ? "#ECEFF4" : "#D8DEE9").child(n.tab.name))
        .child(div().px(4).bg("#1E222A66").text_size(10).text_color("#E5E9F0").child(near ? "right-click to talk" : n.app || ""))));
    }
    this.stats = { faces, paths, ms: Date.now() - t0 };
    return els;
  }

  talkAt(x, y) {
    const p = this.player;
    let best = null;
    for (const n of this.npcs.values()) {
      const top = this.toScreen(new THREE.Vector3(n.x, n.head, n.z)), foot = this.toScreen(new THREE.Vector3(n.x, 0, n.z));
      if (!top || !foot) continue;
      const h = foot.y - top.y, w = Math.max(24, h * 0.6);
      if (x < top.x - w / 2 || x > top.x + w / 2 || y < top.y - 24 || y > foot.y) continue;
      if (!best || foot.z < best.z) best = { n, z: foot.z };
    }
    if (!best) return;
    const n = best.n, d = Math.hypot(p.x - n.x, p.z - n.z);
    if (d > REACH) { this.hint = `${n.tab.name} is too far away. Walk closer.`; return; }
    if (!n.terminal) { this.hint = `${n.tab.name} has nothing to say (no terminal).`; return; }
    this.hint = `Talking to ${n.tab.name}. Click outside the window to leave.`;
    openOverlay({ kind: "dialog", width: 0.74, height: 0.78, layout: { id: "talk", type: "block", content: { terminal: n.terminal } } });
  }

  press(button, cx) {
    this.focus.focus();
    this.drag = { button, x0: this.mouse.x, y0: this.mouse.y, moved: 0, at: Date.now() };
    this.cursor("hold");
    this.wake(cx);
  }

  release(button, cx) {
    const d = this.drag;
    if (!d || d.button !== button) return;
    this.drag = null;
    this.cursor("release");
    if (button === "right") {
      if (d.moved < 6 && Date.now() - d.at < 400) { this.talkAt(d.x0, d.y0); cx.notify(); }
      else this.cam.orbit = 0;            // after turning, the camera sits behind the character
    }
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
        if (!plain(e)) return;
        if (k === "space") {
          if (this.player.y === 0 && this.player.vy === 0) { this.player.vy = JUMP_V; this.wake(cx); }
          cx.stop_propagation();
        } else if (k.length === 1 && "wasdqe".includes(k)) { this.held.add(k); this.wake(cx); cx.stop_propagation(); }
      })
      .on_key_up((e) => { this.held.delete(key(e)); })
      .on_mouse_down("left", (_e, cx) => this.press("left", cx))
      .on_mouse_up("left", (_e, cx) => this.release("left", cx))
      .on_mouse_down("right", (_e, cx) => this.press("right", cx))
      .on_mouse_up("right", (_e, cx) => this.release("right", cx))
      .on_scroll_wheel((e, cx) => {
        const dy = (e.delta && e.delta.y) || 0;
        this.cam.dist = Math.max(3, Math.min(11, this.cam.dist - dy * 0.02));
        cx.notify();
      })
      .on_mouse_move((e) => {
        const lp = e.local_position || e.position;
        const d = this.drag;
        if (d) {
          const dx = lp.x - this.mouse.x, dy = lp.y - this.mouse.y;
          d.moved += Math.abs(dx) + Math.abs(dy);
          if (d.button === "left") this.cam.orbit -= dx * 0.008;
          else { this.player.yaw -= dx * 0.008; this.cam.orbit = 0; }
          this.cam.pitch = Math.max(-0.15, Math.min(1.35, this.cam.pitch + dy * 0.006));
          if (Math.hypot(lp.x - d.x0, lp.y - d.y0) > RECENTER_PX) {
            this.cursor("recenter");
            this.mouse = { x: d.x0, y: d.y0 };   // the warp lands back at the press point
            return;
          }
        }
        this.mouse = { x: lp.x, y: lp.y };
      });
    root.children(this.paint());
    root.child(div().absolute().left(10).top(8).px(6).py(2).bg("#1E222AB3").text_size(11).text_color("#ECEFF4")
      .child(`${this.hint}   ·   ${this.stats.faces} faces / ${this.stats.paths} paths / ${this.stats.ms} ms`));
    return root;
  }
}
