// Emberglade: ink-green pines, weathered canvas and a copper-hearted fire.
export const CAMP = { radius: 14, spawn: { x: 0, z: 7, yaw: 0 }, fire: { x: 0, z: 0 } };

const COLORS = {
  bark: 0x51423d, cut: 0xb38c60, pine: 0x223f40, needles: 0x305650,
  rock: 0x666b72, stone: 0x92908a, canvas: 0x9d7957, moss: 0x586b58,
  shadow: 0x352f38, ember: 0xcb5635, flame: 0xf59c47, gold: 0xffdb83,
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

function box(THREE, parent, name, color, x, y, z, w, h, d) {
  return mesh(THREE, parent, name, new THREE.BoxGeometry(w, h, d), color, x, y, z);
}

// Independent small triangles keep the painter's depth sorting local.
function triangles(THREE, parent, name, color, vertices) {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
  geometry.computeVertexNormals();
  return mesh(THREE, parent, name, geometry, color, 0, 0, 0);
}

function perimeter(THREE, camp, random) {
  for (let i = 0; i < 24; i++) {
    const angle = i * Math.PI / 12;
    const x = Math.sin(angle) * 13.5, z = Math.cos(angle) * 13.5;
    if (i % 2 === 0) {
      mesh(THREE, camp, `pine-trunk-${i}`, new THREE.CylinderGeometry(0.21, 0.3, 1.2, 4, 1, true),
        COLORS.bark, x, 0.6, z);
      const height = 2.8 + random() * 1.2;
      const crown = mesh(THREE, camp, `pine-crown-${i}`,
        new THREE.ConeGeometry(1.35, height, 4, 1, true),
        i % 4 ? COLORS.pine : COLORS.needles, x, 1 + height / 2, z);
      crown.rotation.y = random() * Math.PI;
    } else {
      const rock = mesh(THREE, camp, `boundary-rock-${i}`, new THREE.TetrahedronGeometry(1, 0),
        COLORS.rock, x, 0.75, z);
      rock.scale.set(1.35, 0.8, 1.35);
      rock.rotation.y = random() * Math.PI;
    }
    // Dense root/rock envelopes form a continuous player-sized barrier.
    camp.userData.colliders.push({ x, z, r: 1.4 });
  }
}

function fire(THREE, camp) {
  for (let i = 0; i < 8; i++) {
    const angle = i * Math.PI / 4;
    const stone = mesh(THREE, camp, `hearth-stone-${i}`, new THREE.TetrahedronGeometry(0.3, 0),
      COLORS.stone, Math.sin(angle) * 0.82, 0.22, Math.cos(angle) * 0.82);
    stone.scale.y = 0.8;
    stone.rotation.y = angle;
  }
  for (const angle of [-0.65, 0.65]) {
    const log = box(THREE, camp, 'charred-log', COLORS.bark, 0, 0.17, 0, 1.25, 0.24, 0.24);
    log.rotation.y = angle;
  }
  const layers = [
    [0, 0.62, 0, 0.52, 1.12, COLORS.ember],
    [-0.19, 0.76, 0.12, 0.28, 1.15, COLORS.flame],
    [0.22, 0.54, 0.26, 0.22, 0.68, COLORS.gold],
  ];
  layers.forEach(([x, y, z, radius, height, color], i) => {
    const flame = mesh(THREE, camp, `flame-${i}`, new THREE.ConeGeometry(radius, height, 4, 1, true), color, x, y, z);
    camp.userData.flames.push(flame);
  });
  camp.userData.colliders.push({ x: 0, z: 0, r: 1.1 });
}

function seats(THREE, camp) {
  for (const [i, angle] of [Math.PI / 2, -Math.PI / 2, 11 * Math.PI / 12].entries()) {
    const x = Math.sin(angle) * 3.5, z = -Math.cos(angle) * 3.5;
    mesh(THREE, camp, `seat-stump-${i}`, new THREE.CylinderGeometry(0.38, 0.42, 0.55, 4),
      COLORS.cut, x, 0.275, z);
    camp.userData.colliders.push({ x, z, r: 0.42, kind: 'seat' });
  }
}

function tent(THREE, camp, x, z, color, name) {
  const shelter = new THREE.Group();
  shelter.name = name;
  shelter.position.set(x, 0, z);
  // Each roof slope is split at its midpoint; the front remains open.
  for (const side of [-1, 1]) {
    for (const [back, front] of [[-1.2, 0], [0, 1.2]]) {
      const vertices = [0, 1.65, back, side, 0.04, back, side, 0.04, front,
        0, 1.65, back, side, 0.04, front, 0, 1.65, front];
      if (side < 0) {
        for (let i = 0; i < vertices.length; i += 9) {
          const second = vertices.slice(i + 3, i + 6);
          vertices.splice(i + 3, 3, ...vertices.slice(i + 6, i + 9));
          vertices.splice(i + 6, 3, ...second);
        }
      }
      triangles(THREE, shelter, 'canvas-slope', color, vertices);
    }
  }
  triangles(THREE, shelter, 'tent-back', COLORS.shadow, [-1, 0.04, -1.2, 0, 1.65, -1.2, 1, 0.04, -1.2]);
  box(THREE, shelter, 'ridge-pole', COLORS.cut, 0, 1.69, 0, 0.1, 0.1, 2.6);
  camp.add(shelter);
  camp.userData.colliders.push({ x, z, r: 1.7 });
}

function supplies(THREE, camp) {
  const lean = box(THREE, camp, 'lean-to-roof', COLORS.moss, 8.5, 1.65, -1, 2.4, 0.12, 1.8);
  lean.rotation.z = -0.22;
  for (const z of [-1.7, -0.3]) box(THREE, camp, 'lean-to-post', COLORS.bark, 9.5, 0.78, z, 0.14, 1.56, 0.14);
  camp.userData.colliders.push({ x: 8.5, z: -1, r: 1.6 });
  box(THREE, camp, 'supply-crate', COLORS.cut, -7.5, 0.45, 0.5, 0.85, 0.9, 0.85);
  box(THREE, camp, 'crate-strap', COLORS.shadow, -7.5, 0.45, 0.94, 0.16, 0.88, 0.04);
  mesh(THREE, camp, 'water-barrel', new THREE.CylinderGeometry(0.44, 0.4, 0.9, 5), COLORS.bark, -8.5, 0.45, 1.3);
  camp.userData.colliders.push({ x: -7.9, z: 0.9, r: 1.1 });
  for (let i = 0; i < 3; i++) {
    box(THREE, camp, 'stacked-firewood', COLORS.cut, 7.5 + i * 0.3, 0.15, 2.1, 0.23, 0.3, 1.25);
  }
  camp.userData.colliders.push({ x: 7.8, z: 2.1, r: 0.85 });
  for (const x of [-5.5, 5.5]) {
    box(THREE, camp, 'lantern-post', COLORS.bark, x, 1, 6.6, 0.14, 2, 0.14);
    box(THREE, camp, 'lantern-arm', COLORS.bark, x + 0.2, 2, 6.6, 0.55, 0.12, 0.12);
    box(THREE, camp, 'lantern-glow', COLORS.gold, x + 0.4, 1.7, 6.6, 0.22, 0.36, 0.22);
    camp.userData.colliders.push({ x, z: 6.6, r: 0.45 });
  }
}

export function buildCamp(THREE, seed) {
  const camp = new THREE.Group();
  camp.name = 'Emberglade camp';
  camp.userData.colliders = [];
  camp.userData.flames = [];
  const random = mulberry32(seed);
  perimeter(THREE, camp, random);
  fire(THREE, camp);
  seats(THREE, camp);
  tent(THREE, camp, -7, -6.5, COLORS.canvas, 'ochre-tent');
  tent(THREE, camp, 5.8, -8, COLORS.moss, 'sage-tent');
  supplies(THREE, camp);
  for (let i = 0; i < 5; i++) {
    const x = -7.5 + random() * 1.5, z = 4 + random() * 1.5;
    box(THREE, camp, 'mushroom-stem', COLORS.cut, x, 0.12, z, 0.07, 0.24, 0.07);
    mesh(THREE, camp, 'mushroom-cap', new THREE.ConeGeometry(0.19, 0.16, 4, 1, true),
      i % 2 ? COLORS.ember : COLORS.gold, x, 0.3, z);
  }
  return camp;
}

export function npcSlots(n) {
  // Stable slots avoid re-seating existing NPCs as visitors arrive. One ring
  // outside the log seats, filled widest-first so a few NPCs stand well apart;
  // the south (±140°..180°) stays open for the player. Past 12, a wider ring.
  const order = [0, -50, 50, -100, 100, -140, 140, -25, 25, -75, 75, -120, 120];
  return Array.from({ length: n }, (_, i) => [order[i % order.length], i < 12 ? 5 : 6.8])
    .map(([degree, radius]) => {
      const angle = degree * Math.PI / 180;
      const x = Math.sin(angle) * radius, z = -Math.cos(angle) * radius;
      return { x, z, yaw: Math.atan2(-x, -z) };
    });
}

export function countFaces(object3d) {
  let faces = 0;
  object3d.traverse((part) => {
    if (!part.isMesh) return;
    faces += (part.geometry.index ? part.geometry.index.count : part.geometry.attributes.position.count) / 3;
  });
  return faces;
}
