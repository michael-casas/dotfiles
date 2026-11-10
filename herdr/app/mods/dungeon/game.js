export const CLASSES = [
  { id: 'warrior', name: 'Warrior', color: '#C79C6E', specs: [
    { name: 'Protection', role: 'tank', school: 'physical', spells: ['Ironwake Bash', 'Rampart Crash'] },
    { name: 'Arms', role: 'dps', school: 'physical', spells: ['Anvil Cleave', 'Steel Tempest'] },
    { name: 'Fury', role: 'dps', school: 'physical', spells: ['Ragewheel', 'Twinblade Surge'] },
  ] },
  { id: 'paladin', name: 'Paladin', color: '#F58CBA', specs: [
    { name: 'Protection', role: 'tank', school: 'holy', spells: ['Dawnward Shield', 'Gilded Rebuff'] },
    { name: 'Holy', role: 'healer', school: 'holy', spells: ['Mercy Lantern', 'Sunlit Salve'] },
    { name: 'Retribution', role: 'dps', school: 'holy', spells: ['Oathfire Verdict', 'Radiant Reckoning'] },
  ] },
  { id: 'druid', name: 'Druid', color: '#FF7D0A', specs: [
    { name: 'Feral', role: 'tank', school: 'physical', spells: ['Briarhide Slam', 'Rootbound Maul'] },
    { name: 'Restoration', role: 'healer', school: 'nature', spells: ['Mossheart Mending', 'Dewfall Grace'] },
    { name: 'Balance', role: 'dps', school: 'nature', spells: ['Thornstar', 'Canopy Flare'] },
    { name: 'Feral', role: 'dps', school: 'physical', spells: ['Thistleclaw', 'Wildwood Rend'] },
  ] },
  { id: 'priest', name: 'Priest', color: '#FFFFFF', specs: [
    { name: 'Holy', role: 'healer', school: 'holy', spells: ['Candlelight Balm', 'Kindled Benediction'] },
    { name: 'Discipline', role: 'healer', school: 'holy', spells: ['Vowbound Aegis', 'Quiet Absolution'] },
    { name: 'Shadow', role: 'dps', school: 'shadow', spells: ['Gloam Needle', 'Whispering Eclipse'] },
  ] },
  { id: 'shaman', name: 'Shaman', color: '#0070DE', specs: [
    { name: 'Restoration', role: 'healer', school: 'nature', spells: ['Rainwoven Remedy', 'Riverpulse'] },
    { name: 'Elemental', role: 'dps', school: 'nature', spells: ['Thunderseed', 'Stormroot Burst'] },
    { name: 'Enhancement', role: 'dps', school: 'nature', spells: ['Galehammer', 'Tempest Knuckle'] },
  ] },
  { id: 'mage', name: 'Mage', color: '#69CCF0', specs: [
    { name: 'Arcane', role: 'dps', school: 'arcane', spells: ['Prism Spiral', 'Aether Stitch'] },
    { name: 'Fire', role: 'dps', school: 'fire', spells: ['Cinder Helix', 'Emberglass Spear'] },
    { name: 'Frost', role: 'dps', school: 'frost', spells: ['Rime Petal', 'Hailwoven Dart'] },
  ] },
  { id: 'warlock', name: 'Warlock', color: '#9482C9', specs: [
    { name: 'Affliction', role: 'dps', school: 'shadow', spells: ['Sorrow Thread', 'Withering Murmur'] },
    { name: 'Demonology', role: 'dps', school: 'shadow', spells: ['Impish Covenant', 'Horned Reverberation'] },
    { name: 'Destruction', role: 'dps', school: 'fire', spells: ['Ashen Rupture', 'Brimstone Blossom'] },
  ] },
  { id: 'rogue', name: 'Rogue', color: '#FFF569', specs: [
    { name: 'Assassination', role: 'dps', school: 'physical', spells: ['Widowedge', 'Silent Puncture'] },
    { name: 'Combat', role: 'dps', school: 'physical', spells: ['Cutlass Cadence', 'Knuckle Feint'] },
    { name: 'Subtlety', role: 'dps', school: 'physical', spells: ['Veiled Incision', 'Duskwoven Ambush'] },
  ] },
  { id: 'hunter', name: 'Hunter', color: '#ABD473', specs: [
    { name: 'Beast Mastery', role: 'dps', school: 'physical', spells: ['Packfang Rush', 'Talon Signal'] },
    { name: 'Marksmanship', role: 'dps', school: 'physical', spells: ['Horizon Piercer', 'Kestrel Volley'] },
    { name: 'Survival', role: 'dps', school: 'physical', spells: ['Bramble Snare', 'Flintedge Strike'] },
  ] },
];

const DUNGEONS = [
  { name: 'The Brassroot Ossuary', map: 1 },
  { name: 'The Hollow Lanternworks', map: 2 },
  { name: 'The Saltvein Cloister', map: 3 },
  { name: 'The Rainlocked Foundry', map: 4 },
  { name: 'The Amberjaw Cistern', map: 5 },
  { name: 'The Sable Loomvault', map: 1 },
  { name: 'The Copperbloom Catacombs', map: 2 },
  { name: 'The Glassmoth Reliquary', map: 3 },
  { name: 'The Thornbell Aqueduct', map: 4 },
  { name: 'The Pale Ember Archive', map: 5 },
  { name: 'The Wickerstone Labyrinth', map: 1 },
  { name: 'The Violet Silt Crucible', map: 2 },
];
const BOSSES = [
  { name: 'Orravel the Bell-Eater', title: 'Keeper of Broken Chimes', sprite: 1 },
  { name: 'Murkessa Coilhand', title: 'Cistern Matriarch', sprite: 2 },
  { name: 'Brondel Ashmantle', title: 'The Furnace Steward', sprite: 3 },
  { name: 'Ithrune Glasswing', title: 'Oracle of Shattered Light', sprite: 4 },
  { name: 'Velmora Rootjaw', title: 'The Buried Gardener', sprite: 5 },
  { name: 'Craskel Ninehooks', title: 'Dredger of Lost Oaths', sprite: 6 },
  { name: 'Nimbrath Waxheart', title: 'The Candle Tyrant', sprite: 1 },
  { name: 'Sorella Siltveil', title: 'Abbess of the Low Tide', sprite: 2 },
  { name: 'Grendusk Coppertooth', title: 'The Gear Gnawer', sprite: 3 },
  { name: 'Pelthira Mothcrown', title: 'Weaver of Last Dreams', sprite: 4 },
  { name: 'Vorrusk Thistleback', title: 'Guardian of the Tangled Gate', sprite: 5 },
  { name: 'Algrin Hollowtusk', title: 'The Vault Breaker', sprite: 6 },
  { name: 'Drelmira Brineeye', title: 'Reader of Drowned Pages', sprite: 1 },
  { name: 'Kessovar Reedbone', title: 'The Marsh Cantor', sprite: 2 },
  { name: 'Ulmetha Cinderbraid', title: 'Mistress of the Coal Choir', sprite: 3 },
  { name: 'Tarnovel Prismhide', title: 'The Fractured Warden', sprite: 4 },
  { name: 'Zelmora Sapfang', title: 'The Bitter Harvest', sprite: 5 },
  { name: 'Fendrusk Ironlatch', title: 'Gaoler of the Final Door', sprite: 6 },
];

// FNV-1a over UTF-8 bytes, including replacement for unpaired surrogates.
export function hash(str) {
  let value = 2166136261;
  const byte = n => { value = Math.imul(value ^ n, 16777619) >>> 0; };
  for (const char of str) {
    let c = char.codePointAt(0);
    if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
    if (c < 0x80) byte(c);
    else if (c < 0x800) {
      byte(0xc0 | (c >> 6)); byte(0x80 | (c & 63));
    } else if (c < 0x10000) {
      byte(0xe0 | (c >> 12)); byte(0x80 | ((c >> 6) & 63)); byte(0x80 | (c & 63));
    } else {
      byte(0xf0 | (c >> 18)); byte(0x80 | ((c >> 12) & 63));
      byte(0x80 | ((c >> 6) & 63)); byte(0x80 | (c & 63));
    }
  }
  return value;
}

export function rng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), state | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pick(items, random) { return items[Math.floor(random() * items.length)]; }
function integer(random, min, max) { return min + Math.floor(random() * (max - min + 1)); }

export function roleForSlot(i) { return i === 0 ? 'tank' : i === 1 ? 'healer' : 'dps'; }

export function assignParty(spaceId, members) {
  const used = new Set();
  return members.map(({ address, title }, slot) => {
    const role = roleForSlot(slot);
    const random = rng(hash(`${spaceId}|${address}|${slot}`));
    const capable = CLASSES.filter(c => c.specs.some(s => s.role === role));
    const unused = capable.filter(c => !used.has(c.id));
    const c = pick(unused.length ? unused : capable, random);
    const s = pick(c.specs.filter(s => s.role === role), random);
    used.add(c.id);
    return { address, title, slot, role, classId: c.id, className: c.name,
      spec: s.name, color: c.color, school: s.school,
      classSprite: `assets/class-${c.id}.svg`, roleIcon: `assets/role-${role}.svg` };
  });
}

export function dungeonFor(spaceId) {
  const d = pick(DUNGEONS, rng(hash(`dungeon|${spaceId}`)));
  return { name: d.name, map: `assets/map-${d.map}.svg` };
}

export function bossFor(spaceId, address, turn) {
  const random = rng(hash(`boss|${spaceId}|${address}|${turn}`));
  const b = pick(BOSSES, random);
  return { name: b.name, title: b.title, sprite: `assets/boss-${b.sprite}.svg`,
    hp: integer(random, 1500, 6000) };
}

export function damageRoll(seedStr, role) {
  const ranges = { dps: [120, 980], tank: [40, 420], healer: [21, 260] };
  const range = ranges[role];
  if (!range) throw new Error(`Unknown role: ${role}`);
  return integer(rng(hash(seedStr)), range[0], range[1]);
}

export function spellFor(member, seedStr) {
  const c = CLASSES.find(c => c.id === member.classId);
  const s = c && c.specs.find(s => s.name === member.spec && s.role === member.role);
  if (!s) throw new Error('Unknown party specialization');
  return { name: pick(s.spells, rng(hash(seedStr))), school: s.school };
}

export function snapshot(terminal = {}) {
  const t = terminal ?? {};
  return { address: t.address,
    state: typeof t.status === 'string' ? t.status : t.report?.state ?? '',
    turn: typeof t.turn === 'number' && Number.isFinite(t.turn) ? t.turn : 0,
    msg: t.report?.msg ?? '', at: t.status_ms ?? t.report_ms ?? 0 };
}

export function diff(prev, next) {
  const events = [];
  for (const address of Object.keys(next)) {
    if (!Object.prototype.hasOwnProperty.call(prev, address)) continue;
    const before = prev[address], after = next[address];
    if (after.turn > before.turn || (after.state === 'working' && before.state !== 'working')) {
      events.push({ type: 'turn', address, turn: after.turn });
    }
    if (after.state === 'working' && after.msg && (after.msg !== before.msg || after.at !== before.at)) {
      events.push({ type: 'cast', address, msg: after.msg });
    }
    if (before.state === 'working' && after.state !== 'working') events.push({ type: 'rest', address });
  }
  return events;
}
