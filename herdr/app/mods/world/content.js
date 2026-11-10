// Quiet copper-roofed waystations among mint pines and warm sandstone.
export const PALETTE = {
  bark: 0x775747, pine: 0x467b69, mint: 0x6c9980,
  stone: 0x999584, wall: 0xd9bd89, roof: 0xb56f53,
  door: 0x594b43, water: 0x6ca8ae, rim: 0xb2ad92,
  flame: 0xe69a50, ember: 0xf2cf79, flower: 0xe5b1a6,
  skin: 0xe7c7a0, boots: 0x4f514c, cloak: 0x537f91,
};

function mulberry32(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value ^= value + Math.imul(value ^ (value >>> 7), 61 | value);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function mesh(THREE, parent, name, geometry, color, x, y, z) {
  const part = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ color }));
  part.name = name;
  part.position.set(x, y, z);
  parent.add(part);
  return part;
}

function box(THREE, parent, name, color, x, y, z, width, height, depth) {
  return mesh(THREE, parent, name, new THREE.BoxGeometry(width, height, depth), color, x, y, z);
}

function tree(THREE, world, random, x, z) {
  const height = 2.6 + random() * 1.3;
  mesh(THREE, world, 'pine trunk', new THREE.CylinderGeometry(0.24, 0.34, 1.6, 5), PALETTE.bark, x, 0.8, z);
  mesh(THREE, world, 'pine crown', new THREE.ConeGeometry(1.5, height, 5),
    random() < 0.5 ? PALETTE.pine : PALETTE.mint, x, 1.3 + height / 2, z);
  world.userData.colliders.push({ x, z, r: 0.36 });
}

function hut(THREE, world, x, z) {
  box(THREE, world, 'sandstone hut', PALETTE.wall, x, 1.1, z, 2.8, 2.2, 2.6);
  const roof = mesh(THREE, world, 'copper roof', new THREE.ConeGeometry(2.45, 1.3, 4), PALETTE.roof, x, 2.85, z);
  roof.rotation.y = Math.PI / 4;
  mesh(THREE, world, 'hut doorway', new THREE.PlaneGeometry(0.8, 1.45), PALETTE.door, x, 0.725, z + 1.31);
  world.userData.colliders.push({ x, z, r: 1.95 });
}

function pond(THREE, world) {
  const water = mesh(THREE, world, 'pond water decal', new THREE.CircleGeometry(2.1, 10), PALETTE.water, 13, 0.025, 7);
  water.rotation.x = -Math.PI / 2;
  water.scale.y = 0.72;
  for (let i = 0; i < 5; i++) {
    const angle = i * Math.PI * 2 / 5;
    const rim = box(THREE, world, 'pond rim', PALETTE.rim,
      13 + Math.cos(angle) * 2.15, 0.15, 7 + Math.sin(angle) * 1.6, 1.2, 0.3, 0.38);
    rim.rotation.y = -angle + Math.PI / 2;
  }
}

function campfire(THREE, world) {
  for (const angle of [-0.55, 0.55]) {
    const log = box(THREE, world, 'firewood', PALETTE.bark, -10, 0.18, 4, 1.65, 0.36, 0.32);
    log.rotation.y = angle;
  }
  mesh(THREE, world, 'amber flame', new THREE.ConeGeometry(0.5, 1.1, 5, 1, true), PALETTE.flame, -10, 0.85, 4);
  mesh(THREE, world, 'gold flame', new THREE.ConeGeometry(0.26, 0.75, 5, 1, true), PALETTE.ember, -9.85, 0.65, 4.12);
  world.userData.colliders.push({ x: -10, z: 4, r: 1 });
}

export function buildWorld(THREE, seed) {
  const world = new THREE.Group();
  world.name = 'Copperleaf clearing';
  world.userData.colliders = [];
  const random = mulberry32(seed);
  for (let i = 0; i < 7; i++) {
    const angle = (i + 0.3) * Math.PI * 2 / 7;
    const radius = 20 + random() * 2;
    tree(THREE, world, random, Math.cos(angle) * radius, Math.sin(angle) * radius);
  }
  hut(THREE, world, -11, -11);
  hut(THREE, world, 10, -13);
  pond(THREE, world);
  campfire(THREE, world);
  for (let i = 0; i < 4; i++) {
    const x = -17 + i * 2.1;
    const z = -2 + random() * 1.5;
    const rock = mesh(THREE, world, 'sandstone boulder', new THREE.IcosahedronGeometry(0.7, 0), PALETTE.stone, x, 0.5, z);
    rock.scale.set(1.1, 0.7, 0.85);
    rock.rotation.y = random() * Math.PI;
    world.userData.colliders.push({ x, z, r: 0.8 });
  }
  for (const x of [-15, -12]) {
    box(THREE, world, 'fence post', PALETTE.bark, x, 0.6, 12, 0.22, 1.2, 0.22);
  }
  for (const y of [0.4, 0.9]) {
    box(THREE, world, 'fence rail', PALETTE.wall, -13.5, y, 12, 3, 0.16, 0.14);
  }
  for (let i = 0; i < 6; i++) {
    mesh(THREE, world, 'bell flower', new THREE.ConeGeometry(0.22, 0.45, 5, 1, true),
      i % 2 ? PALETTE.flower : PALETTE.ember, 8 + random() * 2, 0.225, 7 + i * 0.6);
  }
  return world;
}

// Four-sided sleeves and trouser legs omit hidden end caps to save faces.
function openBox(THREE, width, height, depth) {
  const geometry = new THREE.BoxGeometry(width, height, depth);
  const sides = Array.from(geometry.index.array).slice(0, 12)
    .concat(Array.from(geometry.index.array).slice(24, 36));
  geometry.setIndex(sides);
  geometry.clearGroups();
  return geometry;
}

function character(THREE, color, accent, facing) {
  const person = new THREE.Group();
  const limb = (name, tint, x, y, z, w, h, d) =>
    mesh(THREE, person, name, openBox(THREE, w, h, d), tint, x, y, z);
  limb('left boot', PALETTE.boots, -0.17, 0.3, 0, 0.24, 0.6, 0.32);
  limb('right boot', PALETTE.boots, 0.17, 0.3, 0, 0.24, 0.6, 0.32);
  limb('tunic', color, 0, 0.93, 0, 0.64, 0.72, 0.4);
  limb('left arm', color, -0.43, 0.96, 0, 0.2, 0.62, 0.26);
  limb('right arm', color, 0.43, 0.96, 0, 0.2, 0.62, 0.26);
  limb('head', PALETTE.skin, 0, 1.53, 0, 0.46, 0.46, 0.42);
  mesh(THREE, person, 'cap', new THREE.ConeGeometry(0.39, 0.3, 5, 1, true), accent, 0, 1.84, 0);
  const face = mesh(THREE, person, 'face', new THREE.PlaneGeometry(0.18, 0.07), PALETTE.door, 0, 1.52, facing * 0.211);
  if (facing < 0) face.rotation.y = Math.PI;
  person.userData.head = 1.76;
  return person;
}

export function makeNpc(THREE, { color, accent }) {
  return character(THREE, color, accent, 1);
}

export function makeHero(THREE) {
  const hero = character(THREE, PALETTE.cloak, PALETTE.ember, -1);
  const cloak = mesh(THREE, hero, 'cloak', openBox(THREE, 0.85, 1, 0.16), PALETTE.cloak, 0, 0.79, 0.29);
  // A wider hem gives the traveller a distinct silhouette from the workers.
  const positions = cloak.geometry.attributes.position;
  for (let i = 0; i < positions.count; i++) {
    if (positions.getY(i) > 0) positions.setX(i, positions.getX(i) * 0.6);
  }
  positions.needsUpdate = true;
  cloak.geometry.computeVertexNormals();
  return hero;
}

export function countFaces(object3d) {
  let faces = 0;
  object3d.traverse((part) => {
    if (!part.isMesh) return;
    const geometry = part.geometry;
    faces += (geometry.index ? geometry.index.count : geometry.attributes.position.count) / 3;
  });
  return faces;
}
