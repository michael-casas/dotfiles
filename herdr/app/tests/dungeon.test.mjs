import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as game from '../mods/dungeon/game.js';
const { CLASSES, hash, rng, roleForSlot, assignParty, dungeonFor, bossFor,
  damageRoll, spellFor, snapshot, diff } = game;
const members = Array.from({ length: 15 }, (_, i) => ({ address: `t${i}`, title: `Agent ${i}` }));

test('exports exactly the charter API', () => {
  assert.deepEqual(Object.keys(game).sort(), ['CLASSES', 'hash', 'rng', 'roleForSlot', 'assignParty',
    'dungeonFor', 'bossFor', 'damageRoll', 'spellFor', 'snapshot', 'diff'].sort());
});
test('all nine classes have valid specs and original spell lists', () => {
  assert.equal(CLASSES.length, 9);
  assert.equal(new Set(CLASSES.map(c => c.id)).size, 9);
  for (const c of CLASSES) {
    assert.match(c.color, /^#[0-9A-F]{6}$/);
    assert.ok(c.name && c.specs.length);
    for (const s of c.specs) {
      assert.ok(['tank', 'healer', 'dps'].includes(s.role));
      assert.ok(['fire', 'frost', 'arcane', 'shadow', 'nature', 'holy', 'physical'].includes(s.school));
      assert.ok(s.name && s.spells.length >= 2 && s.spells.length <= 3);
      assert.ok(s.spells.every(n => typeof n === 'string' && n.length > 0));
    }
  }
});
test('FNV-1a known vectors including UTF-8 and unsigned results', () => {
  for (const value of ['', 'hello', 'é', '🦉']) {
    let expected = 2166136261;
    for (const byte of Buffer.from(value)) expected = Math.imul(expected ^ byte, 16777619) >>> 0;
    assert.equal(hash(value), expected);
  }
  assert.equal(hash('hello'), 0x4f9f2cab);
});
test('mulberry32 is deterministic and bounded', () => {
  const a = rng(1), b = rng(1);
  assert.equal(a(), 0.6270739405881613);
  b();
  for (let i = 0; i < 2000; i++) {
    const v = a();
    assert.equal(v, b());
    assert.ok(v >= 0 && v < 1);
  }
});
test('roles follow pane order, including large parties', () => {
  assert.deepEqual([0, 1, 2, 4, 20].map(roleForSlot), ['tank', 'healer', 'dps', 'dps', 'dps']);
  assert.deepEqual(assignParty('s', []), []);
  const party = assignParty('s', members);
  assert.equal(party.length, members.length);
  assert.deepEqual(party, assignParty('s', members));
  assert.deepEqual(party.slice(0, 5), assignParty('s', members.slice(0, 5)));
  for (const [i, m] of party.entries()) {
    assert.equal(m.slot, i);
    assert.equal(m.role, roleForSlot(i));
    assert.equal(m.address, members[i].address);
    assert.equal(m.title, members[i].title);
    const c = CLASSES.find(c => c.id === m.classId);
    assert.ok(c.specs.some(s => s.name === m.spec && s.role === m.role && s.school === m.school));
    assert.equal(m.className, c.name);
    assert.equal(m.color, c.color);
    assert.equal(m.classSprite, `assets/class-${c.id}.svg`);
    assert.equal(m.roleIcon, `assets/role-${m.role}.svg`);
  }
  assert.equal(new Set(party.slice(0, 9).map(m => m.classId)).size, 9);
});
test('dungeon and boss catalogs are stable, varied and in range', () => {
  const dungeons = new Set(), bosses = new Set();
  for (let i = 0; i < 2000; i++) {
    const d = dungeonFor(`s${i}`), b = bossFor('s', `t${i}`, i);
    assert.deepEqual(d, dungeonFor(`s${i}`));
    assert.deepEqual(b, bossFor('s', `t${i}`, i));
    assert.match(d.map, /^assets\/map-[1-5]\.svg$/);
    assert.match(b.sprite, /^assets\/boss-[1-6]\.svg$/);
    assert.ok(b.title && Number.isInteger(b.hp) && b.hp >= 1500 && b.hp <= 6000);
    dungeons.add(d.name); bosses.add(b.name);
  }
  assert.ok(dungeons.size >= 12);
  assert.ok(bosses.size >= 18);
});
for (const [role, min, max] of [['dps', 120, 980], ['tank', 40, 420], ['healer', 21, 260]]) {
  test(`${role} damage: 2000 deterministic integer rolls always exceed 20`, () => {
    for (let i = 0; i < 2000; i++) {
      const n = damageRoll(String(i), role);
      assert.equal(n, damageRoll(String(i), role));
      assert.ok(Number.isInteger(n) && n > 20 && n >= min && n <= max);
    }
  });
}
test('spells resolve every class/spec/role combination, including both Feral roles', () => {
  for (const c of CLASSES) for (const s of c.specs) {
    const m = { classId: c.id, spec: s.name, role: s.role };
    for (let i = 0; i < 10; i++) {
      const spell = spellFor(m, String(i));
      assert.deepEqual(spell, spellFor(m, String(i)));
      assert.equal(spell.school, s.school);
      assert.ok(s.spells.includes(spell.name));
    }
  }
});
test('snapshot tolerates missing fields and respects status/timestamp precedence', () => {
  assert.deepEqual(snapshot({}), { address: undefined, state: '', turn: 0, msg: '', at: 0 });
  assert.deepEqual(snapshot(), snapshot({}));
  assert.deepEqual(snapshot({ address: 't', status: 'working', turn: 3, status_ms: 0,
    report_ms: 8, report: { state: 'idle', msg: 'tool' } }),
  { address: 't', state: 'working', turn: 3, msg: 'tool', at: 0 });
  assert.equal(snapshot({ status: {}, turn: '3', report: { state: 'done' }, report_ms: 8 }).state, 'done');
  assert.equal(snapshot({ turn: '3' }).turn, 0);
  assert.equal(snapshot({ report_ms: 8 }).at, 8);
});
const base = { address: 't', state: 'idle', turn: 1, msg: '', at: 0 };
function events(before, after) { return diff({ t: { ...base, ...before } }, { t: { ...base, ...after } }); }
const turn = { type: 'turn', address: 't', turn: 2 };
const cast = { type: 'cast', address: 't', msg: 'tool' };
test('diff emits new turn', () => assert.deepEqual(events({}, { turn: 2 }), [turn]));
test('diff emits working transition', () => assert.deepEqual(events({}, { state: 'working' }), [{ ...turn, turn: 1 }]));
test('diff emits cast on changed message', () => assert.deepEqual(events({ state: 'working' }, { state: 'working', msg: 'tool' }), [cast]));
test('diff emits repeated message at a new timestamp', () => assert.deepEqual(events({ state: 'working', msg: 'tool' }, { state: 'working', msg: 'tool', at: 1 }), [cast]));
test('diff emits at most one turn before cast', () => assert.deepEqual(events({}, { state: 'working', turn: 2, msg: 'tool' }), [turn, cast]));
test('diff emits rest for each leaving state', () => {
  for (const state of ['idle', 'done', 'blocked']) assert.deepEqual(events({ state: 'working' }, { state }), [{ type: 'rest', address: 't' }]);
});
test('diff ignores first sightings, vanished addresses, inherited keys and unchanged polls', () => {
  assert.deepEqual(diff({}, { t: { ...base, state: 'working', turn: 2, msg: 'tool' } }), []);
  assert.deepEqual(diff({ t: base }, {}), []);
  assert.deepEqual(events({ state: 'working', msg: 'tool' }, { state: 'working', msg: 'tool' }), []);
  assert.deepEqual(diff({}, { toString: { ...base, state: 'working' } }), []);
  assert.deepEqual(events({}, { msg: 'tool' }), []);
});
test('runtime source has no imports, require or unseeded randomness', () => {
  const source = readFileSync(new URL('../mods/dungeon/game.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /\bimport\b|Math\.random|\brequire\s*\(/);
});
