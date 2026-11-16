// Copperleaf wayfarers: rigid cloth panels and broad, friendly silhouettes.
function addMesh(THREE, parent, name, geometry, color, x, y, z) {
  const mesh = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ color }));
  mesh.name = name;
  mesh.position.set(x, y, z);
  parent.add(mesh);
  return mesh;
}

// Sleeves and tunics have open ends; hidden caps would waste painted faces.
function panelBox(THREE, width, height, depth) {
  const geometry = new THREE.BoxGeometry(width, height, depth);
  const indices = Array.from(geometry.index.array);
  geometry.setIndex(indices.slice(0, 12).concat(indices.slice(24, 36)));
  geometry.clearGroups();
  return geometry;
}

function joint(THREE, parent, name, x, y) {
  const group = new THREE.Group();
  group.name = name;
  group.position.set(x, y, 0);
  parent.add(group);
  return group;
}

function makeRig(THREE, color, facing) {
  const figure = new THREE.Group();
  const body = joint(THREE, figure, 'body', 0, 0.64);
  body.userData.facing = facing;
  const head = joint(THREE, body, 'head', 0, 0.66);
  const armL = joint(THREE, body, 'armL', -0.43, 0.54);
  const armR = joint(THREE, body, 'armR', 0.43, 0.54);
  const legL = joint(THREE, body, 'legL', -0.17, 0);
  const legR = joint(THREE, body, 'legR', 0.17, 0);
  addMesh(THREE, body, 'tunic', panelBox(THREE, 0.64, 0.66, 0.4), color, 0, 0.33, 0);
  for (const arm of [armL, armR]) {
    addMesh(THREE, arm, 'sleeve', panelBox(THREE, 0.2, 0.57, 0.25), color, 0, -0.285, 0);
  }
  for (const leg of [legL, legR]) {
    addMesh(THREE, leg, 'boot', panelBox(THREE, 0.25, 0.64, 0.32), 0x53504c, 0, -0.32, facing * 0.025);
  }
  addMesh(THREE, head, 'face', new THREE.BoxGeometry(0.46, 0.46, 0.44), 0xe9bf99, 0, 0.23, facing * 0.025);
  for (const [name, x] of [['eyeL', -0.09], ['eyeR', 0.09]]) {
    const eye = addMesh(THREE, head, name, new THREE.PlaneGeometry(0.045, 0.055), 0x414344, x, 0.27, facing * 0.247);
    if (facing < 0) eye.rotation.y = Math.PI;
  }
  figure.userData = { head: 1.76, parts: { body, head, armL, armR, legL, legR } };
  return figure;
}

function headwear(THREE, head, style, color, facing) {
  if (style === 0) {
    addMesh(THREE, head, 'hat', new THREE.ConeGeometry(0.36, 0.24, 4, 1, true), color, 0, 0.55, 0);
    const brim = addMesh(THREE, head, 'brim', new THREE.PlaneGeometry(0.74, 0.65), color, 0, 0.43, 0);
    // The upward-facing brim reads clearly from the elevated world camera.
    brim.rotation.x = -Math.PI / 2;
  } else if (style === 1) {
    // Keep top and sides; omit the face opening and underside.
    const hood = new THREE.BoxGeometry(0.57, 0.55, 0.49);
    const indices = Array.from(hood.index.array);
    hood.setIndex(indices.slice(0, 18).concat(indices.slice(facing > 0 ? 30 : 24, facing > 0 ? 36 : 30)));
    hood.clearGroups();
    addMesh(THREE, head, 'hood', hood, color, 0, 0.28, -facing * 0.025);
  } else if (style === 2) {
    addMesh(THREE, head, 'helmet', new THREE.CylinderGeometry(0.23, 0.34, 0.19, 4, 1, true), color, 0, 0.46, 0);
  }
}

function fitHeight(THREE, figure, height) {
  const top = new THREE.Box3().setFromObject(figure).max.y;
  figure.scale.setScalar(height / top);
  figure.userData.head = height;
  return figure;
}

export function makeHero(THREE) {
  const hero = makeRig(THREE, 0x658c8b, -1);
  hero.name = 'Copperleaf trailkeeper';
  headwear(THREE, hero.userData.parts.head, 1, 0x426778, -1);
  const cloak = addMesh(THREE, hero.userData.parts.body, 'cloak',
    panelBox(THREE, 0.75, 0.87, 0.09), 0x426778, 0, 0.19, 0.28);
  cloak.rotation.x = -0.13;
  return fitHeight(THREE, hero, 1.88);
}

export function makeNpc(THREE, { color = 0xb77e64, accent = 0xd4b66e, seed = 0 } = {}) {
  const variant = seed >>> 0;
  const npc = makeRig(THREE, color, 1);
  npc.name = 'Copperleaf traveler';
  headwear(THREE, npc.userData.parts.head, variant % 4, accent, 1);
  if ((variant >>> 2) % 2) {
    const pack = addMesh(THREE, npc.userData.parts.body, 'backpack',
      new THREE.TetrahedronGeometry(1, 0), accent, 0, 0.33, -0.31);
    pack.scale.set(0.4, 0.42, 0.28);
  }
  // Integer mixing provides repeatable stature without an ambient generator.
  const stature = (Math.imul(variant, 1664525) + 1013904223) >>> 0;
  return fitHeight(THREE, npc, 1.6 + (stature % 301) / 1000);
}

export function animate(figure, state, t) {
  const { body, head, armL, armR, legL, legR } = figure.userData.parts;
  const speed = state.moving ? state.speed : 0;
  const stride = speed > 0 ? Math.sin(t * Math.PI * 2 / 0.6 * (0.4 + 0.6 * speed)) * 0.62 * speed : 0;
  const oppositeStride = stride === 0 ? 0 : -stride;
  const facing = body.userData.facing;
  body.position.y = 0.64 + (state.moving && !state.airborne ? Math.abs(stride) * 0.035 : 0);
  body.rotation.set(0, 0, 0);
  body.scale.set(1, !state.moving && !state.airborne ? 1 + 0.012 * Math.sin(t * 2.1) : 1, 1);
  head.rotation.set(0, 0.045 * Math.sin(t * 0.9), 0);
  armL.rotation.set(oppositeStride, 0, 0);
  armR.rotation.set(stride, 0, 0);
  legL.rotation.set(stride, 0, 0);
  legR.rotation.set(oppositeStride, 0, 0);
  if (state.airborne) {
    legL.rotation.x = -facing * 0.75;
    legR.rotation.x = -facing * 0.55;
    armL.rotation.x = facing * 0.85;
    armR.rotation.x = facing * 0.85;
    armL.rotation.z = -0.22;
    armR.rotation.z = 0.22;
  }
  if (state.talking) {
    armR.rotation.x = facing * (0.65 + 0.16 * Math.sin(t * 7));
    armR.rotation.z = 0.3 + 0.1 * Math.sin(t * 5);
    head.rotation.x = 0.085 * Math.sin(t * 6);
  }
}

export function countFaces(object3d) {
  let faces = 0;
  object3d.traverse((node) => {
    if (node.isMesh) faces += (node.geometry.index ? node.geometry.index.count : node.geometry.attributes.position.count) / 3;
  });
  return faces;
}
