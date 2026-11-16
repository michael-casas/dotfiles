// Dungeon: the shown space is a dungeon, the terminals in the shown tab are
// its party in pane order (1 tank, 2 healer, 3+ dps). An agent starting a turn
// spawns a boss; each tool call (a change in its status message) is a spell
// that flies to the boss and hits for > 20.
//
// Signals: terminals()[i].status / .turn / .report.msg. Claude Code reports a
// message per tool call; pi needs pi-tool-status.ts (see docs/dungeon.md).
import { View, div, image, svg } from "gpui-kit";
import { v_flex } from "gpui-base";
import { panes, focused, terminals, theme, spaces } from "herdr";
import { assignParty, dungeonFor, bossFor, damageRoll, spellFor, snapshot, diff } from "./game.js";

const ROOT = "mods/dungeon/";
const SPRITE = 48;           // 16 px sprites at 3x
const BOSS = 120;            // 32 px boss at ~4x
const FLY_MS = 380;
const FLOAT_MS = 950;
const POLL_MS = 250;
const SCHOOL_COLOR = {
  fire: "#FF8A3D", frost: "#8FD6FF", arcane: "#D29BFF", shadow: "#B79CFF",
  nature: "#B5E07A", holy: "#FFE680", physical: "#F2F2F2",
};

export default class Dungeon extends View {
  init(_props, cx) {
    this.size = { width: 900, height: 220 };
    this.prev = {};          // address -> snapshot
    this.fights = {};        // spaceId -> { boss, hp, max, shown, defeated }
    this.shots = {};         // address -> { n, flying, school }
    this.floats = [];        // { id, x, y, text, color, up }
    this.hits = 0;           // boss hit flash counter
    this.flash = false;
    this.log = "";
    this.seq = 0;
    this.poll(cx);
    cx.timer.every(POLL_MS, (cx) => this.poll(cx));
  }

  party() {
    const f = focused();
    if (!f) return { space: null, members: [] };
    const members = panes()
      .filter((p) => p.tab === f.tab && p.terminal)
      .map((p) => ({ address: p.terminal, title: p.title || p.terminal, status: p.status }));
    const party = assignParty(f.space, members);
    party.forEach((m, i) => { m.status = members[i].status; });
    return { space: f.space, members: party };
  }

  poll(cx) {
    const next = {};
    for (const t of terminals()) if (t && t.address) next[t.address] = snapshot(t);
    const events = diff(this.prev, next);
    this.prev = next;
    if (!events.length) return;
    const { space, members } = this.party();
    if (!space) return;
    const byAddr = Object.fromEntries(members.map((m) => [m.address, m]));
    let changed = false;
    for (const e of events) {
      const m = byAddr[e.address];
      if (!m) continue;
      if (e.type === "turn") { this.spawn(space, m, e.turn, cx); changed = true; }
      if (e.type === "cast") { this.cast(space, m, e.msg, cx); changed = true; }
    }
    if (changed) cx.notify();
  }

  spawn(space, m, turn, cx) {
    const f = this.fights[space];
    if (f && !f.defeated) return;                  // keep fighting the current boss
    const boss = bossFor(space, m.address, `${turn}|${Date.now()}`);
    this.fights[space] = { boss, hp: boss.hp, max: boss.hp, shown: false, defeated: false };
    this.log = `${boss.name} appears!`;
    cx.timer.after(30, (cx) => { const g = this.fights[space]; if (g) g.shown = true; cx.notify(); });
  }

  cast(space, m, msg, cx) {
    if (!this.fights[space] || this.fights[space].defeated) this.spawn(space, m, 0, cx);
    const fight = this.fights[space];
    const seed = `${m.address}|${msg}|${++this.seq}`;
    const dmg = damageRoll(seed, m.role);
    const spell = spellFor(m, seed);
    const shot = (this.shots[m.address] = { n: this.seq, flying: false, school: spell.school });
    this.log = `${m.className} (${m.spec}) casts ${spell.name}`;
    // Next frame: move the projectile to the boss so its `left` transitions.
    cx.timer.after(20, (cx) => { shot.flying = true; cx.notify(); });
    cx.timer.after(FLY_MS, (cx) => {
      if (this.shots[m.address] === shot) delete this.shots[m.address];
      fight.hp = Math.max(0, fight.hp - dmg);
      if (fight.hp === 0 && !fight.defeated) { fight.defeated = true; this.log = `${fight.boss.name} is defeated!`; }
      this.float(this.bossX() + BOSS / 2 - 20, this.groundY() - BOSS - 6, `-${dmg}`, SCHOOL_COLOR[spell.school], cx);
      this.flash = true;
      cx.timer.after(140, (cx) => { this.flash = false; cx.notify(); });
      cx.notify();
    });
  }

  float(x, y, text, color, cx) {
    const f = { id: `f${++this.seq}`, x, y, text, color, up: false };
    this.floats.push(f);
    cx.timer.after(20, (cx) => { f.up = true; cx.notify(); });
    cx.timer.after(FLOAT_MS + 50, (cx) => { this.floats = this.floats.filter((g) => g !== f); cx.notify(); });
  }

  groundY() { return Math.round(this.size.height * 0.74); }
  memberX(i) { return 28 + i * 84; }
  bossX() { return Math.max(this.memberX(5) + 40, this.size.width - BOSS - 48); }

  render(cx) {
    const t = theme();
    const { width: W, height: H } = this.size;
    const { space, members } = this.party();
    const root = div().id("root").size_full().relative().overflow_hidden().bg("#1E222A")
      .on_size_change((size, cx) => { this.size = size; cx.notify(); });
    if (!space) return root.child(div().p(12).text_color(t.muted).child("No space shown"));

    const dungeon = dungeonFor(space);
    const sp = spaces().find((s) => s.id === space);
    const fight = this.fights[space];
    const gy = this.groundY();
    const tileW = H * 3;                                   // maps are 192x64
    for (let x = 0; x < W; x += tileW) {
      root.child(div().absolute().left(x).top(0).w(tileW + 2).h(H).child(image(ROOT + dungeon.map).size_full()));
    }

    // Title plate.
    root.child(div().absolute().left(12).top(10).px(8).py(4).bg("#1E222ACC").border(1).border_color("#3B4252")
      .child(div().text_size(13).font_semibold().text_color("#ECEFF4").child(dungeon.name))
      .child(div().text_size(11).text_color("#8C95A8").child(`${sp ? sp.name : "space"} · party of ${members.length}`)));

    // Party.
    members.forEach((m, i) => {
      const x = this.memberX(i), working = m.status === "working";
      const body = div().absolute().left(x).top(gy - SPRITE).w(SPRITE).h(SPRITE)
        .child(image(ROOT + m.classSprite).size_full());
      root.child(working ? body.id(`bob-${m.address}`).loop("top", { from: gy - SPRITE, to: gy - SPRITE - 4, period: 700 }) : body);
      root.child(div().absolute().left(x + SPRITE / 2 - 9).top(gy - SPRITE - 24).w(18).h(18)
        .child(svg(ROOT + m.roleIcon).size_full().text_color(m.color)));
      root.child(div().absolute().left(x - 14).top(gy + 2).w(SPRITE + 28).child(v_flex().w_full().items_center()
        .child(div().px(3).bg("#1E222AD9").text_size(10).font_semibold().text_color(m.color).truncate().child(`${m.className}`))
        .child(div().px(3).bg("#1E222AD9").text_size(9).text_color("#D8DEE9").truncate().child(short(m.title)))));
      const shot = this.shots[m.address];
      if (shot) {
        const sx = shot.flying ? this.bossX() + 20 : x + SPRITE;
        root.child(div().id(`shot-${m.address}-${shot.n}`).absolute().left(sx).top(gy - SPRITE / 2 - 12).w(24).h(24)
          .transition("left", FLY_MS).child(image(ROOT + `assets/fx-${shot.school}.svg`).size_full()));
      }
    });

    // Boss.
    if (fight) {
      const bx = this.bossX(), dead = fight.defeated;
      root.child(div().id(`boss-${fight.boss.name}`).absolute().left(bx).top(gy - BOSS + 6).w(BOSS).h(BOSS)
        .opacity(dead ? 0.25 : fight.shown ? 1 : 0).transition("opacity", 450)
        .child(image(ROOT + fight.boss.sprite).size_full()));
      if (this.flash && !dead) root.child(div().absolute().left(bx + BOSS / 2 - 24).top(gy - BOSS / 2 - 24).w(48).h(48)
        .child(image(ROOT + "assets/hit.svg").size_full()));
      if (dead) root.child(div().absolute().left(bx + BOSS / 2 - 18).top(gy - BOSS / 2 - 18).w(36).h(36)
        .child(svg(ROOT + "assets/skull.svg").size_full().text_color("#ECEFF4")));
      const pct = fight.hp / fight.max;
      root.child(div().absolute().left(Math.max(12, bx - BOSS - 128)).top(10).w(BOSS + 108).px(8).py(4).bg("#1E222ACC").border(1).border_color("#3B4252")
        .child(div().text_size(12).font_semibold().text_color("#BF616A").truncate().child(fight.boss.name))
        .child(div().text_size(10).text_color("#8C95A8").truncate().child(fight.boss.title))
        .child(div().mt(4).h(8).w_full().bg("#2E3440").border(1).border_color("#4C566A")
          .child(div().id("hp").h_full().w(Math.round((BOSS + 90) * pct)).bg(pct > 0.3 ? "#A3BE8C" : "#BF616A").transition("width", 300)))
        .child(div().text_size(10).text_color("#D8DEE9").child(dead ? "Defeated" : `${fight.hp} / ${fight.max}`)));
    } else {
      root.child(div().absolute().left(this.memberX(Math.max(members.length, 1)) + 24).top(gy - 30).px(6).bg("#1E222ACC").text_size(11).text_color("#D8DEE9")
        .child("Camp: the party rests. Start a turn to pull a boss."));
    }

    // Damage numbers.
    for (const f of this.floats) {
      root.child(div().id(f.id).absolute().left(f.x).top(f.up ? f.y - 44 : f.y).opacity(f.up ? 0 : 1)
        .transition("top", FLOAT_MS).transition("opacity", FLOAT_MS)
        .text_size(18).font_semibold().text_color(f.color).child(f.text));
    }

    // Combat log.
    if (this.log) root.child(div().absolute().left(this.bossX() - 260).top(H - 22).w(BOSS + 250).px(6).bg("#1E222ACC").text_size(10).text_color("#ECEFF4").child(this.log));
    return root;
  }
}

function short(s) { const x = String(s || ""); return x.length > 14 ? x.slice(0, 13) + "…" : x; }
