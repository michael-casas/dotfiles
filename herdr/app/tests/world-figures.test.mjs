import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as THREE from '../mods/world/vendor/three.module.min.js';

// A missing module is reported by the contract test, not an ESM loader failure.
const url = new URL('../mods/world/figures.js', import.meta.url);
const figures = await import(url.href).catch((error) => {
  if (error.code === 'ERR_MODULE_NOT_FOUND' && error.url === url.href) return null;
  throw error;
});
const rest = { moving: false, speed: 0, airborne: false, talking: false };
const walk = { ...rest, moving: true, speed: 1 };
function pose(root) {
  const result = [];
  root.traverse((node) => result.push([node.name, node.position.toArray(), node.rotation.toArray(), node.scale.toArray()]));
  return result;
}
function build(root) {
  const meshes = [];
  root.traverse((node) => {
    if (node.isMesh) meshes.push([node.name, Array.from(node.geometry.attributes.position.array), node.material.color.getHex()]);
  });
  return [root.scale.toArray(), meshes];
}

test('figures expose exactly the dependency-free charter API', async () => {
  assert.ok(figures, 'animated figures module must exist');
  assert.deepEqual(Object.keys(figures).sort(), ['animate', 'countFaces', 'makeHero', 'makeNpc']);
  const source = await readFile(url, 'utf8');
  assert.doesNotMatch(source, /\bimport\b|\brequire\b|Math\s*\.\s*random/);
});

test('rigs obey face, material, joint, facing and grounded-foot contracts', () => {
  assert.ok(figures, 'animated figures module must exist');
  const hero = figures.makeHero(THREE);
  for (const [root, budget, direction] of [[hero, 90, -1], ...Array.from({ length: 32 }, (_, seed) =>
    [figures.makeNpc(THREE, { color: 0x537f91, accent: 0xe5ac69, seed }), 70, 1])]) {
    assert.ok(root instanceof THREE.Group);
    assert.ok(figures.countFaces(root) > 0 && figures.countFaces(root) < budget);
    assert.deepEqual(Object.keys(root.userData).sort(), ['head', 'parts']);
    assert.deepEqual(Object.keys(root.userData.parts).sort(), ['armL', 'armR', 'body', 'head', 'legL', 'legR']);
    for (const part of Object.values(root.userData.parts)) assert.ok(part instanceof THREE.Group);
    const bounds = new THREE.Box3().setFromObject(root);
    assert.ok(Math.abs(bounds.min.y) < 0.05);
    assert.ok(root.userData.head >= 1.5 && root.userData.head <= 2.2);
    assert.ok(Math.abs(bounds.max.y - root.userData.head) < 1e-5);
    if (direction === 1) assert.ok(bounds.max.y >= 1.6 - 1e-6 && bounds.max.y <= 1.9 + 1e-6);
    assert.equal(Math.sign(root.getObjectByName('eyeL').position.z), direction);
    let actualFaces = 0;
    root.traverse((node) => {
      assert.ok(node.isGroup || node.isMesh);
      if (!node.isMesh) return;
      actualFaces += (node.geometry.index?.count ?? node.geometry.attributes.position.count) / 3;
      assert.ok(node.material instanceof THREE.MeshBasicMaterial);
      assert.equal(node.material.transparent, false);
      assert.equal(node.material.opacity, 1);
      assert.equal(node.material.map, null);
      assert.equal(node.isSkinnedMesh, undefined);
    });
    assert.equal(figures.countFaces(root), actualFaces);
  }
  assert.ok(hero.getObjectByName('hood'));
  assert.ok(hero.getObjectByName('cloak'));
});

test('animation is history-independent, opposite-phase and restores rest', () => {
  assert.ok(figures, 'animated figures module must exist');
  for (const root of [figures.makeHero(THREE), figures.makeNpc(THREE, { seed: 3 })]) {
    root.position.set(3, 4, 5);
    root.rotation.y = 0.7;
    const { legL, legR, armL, body, head } = root.userData.parts;
    figures.animate(root, walk, 0.1);
    const first = pose(root);
    assert.ok(Math.abs(legL.rotation.x) > 0.1);
    assert.ok(Math.abs(legL.rotation.x + legR.rotation.x) < 1e-12);
    assert.ok(armL.rotation.x * legL.rotation.x < 0);
    const angle = legL.rotation.x;
    figures.animate(root, walk, 0.4);
    assert.ok(angle * legL.rotation.x < 0);
    figures.animate(root, walk, 0.7);
    assert.ok(Math.abs(angle - legL.rotation.x) < 1e-12);
    figures.animate(root, { ...walk, airborne: true, talking: true }, 9);
    figures.animate(root, walk, 0.1);
    assert.deepEqual(pose(root), first);
    figures.animate(root, rest, 0.1);
    const cleanRest = pose(root);
    assert.equal(legL.rotation.x, 0);
    assert.equal(legR.rotation.x, 0);
    assert.equal(armL.rotation.x, 0);
    assert.ok(Math.abs(body.scale.y - 1) <= 0.015);
    figures.animate(root, rest, 1.2);
    assert.notEqual(head.rotation.y, cleanRest.find(([name]) => name === 'head')[2][1]);
    figures.animate(root, { ...rest, airborne: true }, 0.1);
    assert.ok(Math.abs(legL.rotation.x) > 0.2 && Math.abs(legR.rotation.x) > 0.2);
    assert.ok(Math.abs(armL.rotation.x) > 0.2);
    figures.animate(root, { ...rest, talking: true }, 0.1);
    assert.ok(Math.abs(root.userData.parts.armR.rotation.z) > 0.1);
    assert.ok(Math.abs(head.rotation.x) > 0.01);
    figures.animate(root, rest, 0.1);
    assert.deepEqual(pose(root), cleanRest);
    assert.deepEqual(root.position.toArray(), [3, 4, 5]);
    assert.equal(root.rotation.y, 0.7);
  }
});

test('seeded NPC builds are repeatable and include all headwear and pack variants', () => {
  assert.ok(figures, 'animated figures module must exist');
  const variants = new Set();
  const heights = new Set();
  const packs = new Set();
  for (let seed = 0; seed < 32; seed++) {
    const options = { color: 0x537f91, accent: 0xe5ac69, seed };
    const npc = figures.makeNpc(THREE, options);
    assert.deepEqual(build(npc), build(figures.makeNpc(THREE, options)));
    variants.add(['hat', 'hood', 'helmet'].find((name) => npc.getObjectByName(name)) ?? 'none');
    packs.add(Boolean(npc.getObjectByName('backpack')));
    heights.add(npc.userData.head);
  }
  assert.equal(variants.size, 4);
  assert.equal(packs.size, 2);
  assert.ok(heights.size > 4);
  assert.notDeepEqual(build(figures.makeNpc(THREE, { seed: 0 })), build(figures.makeNpc(THREE, { seed: 1 })));
});

test('face counter handles nested indexed and non-indexed geometry', () => {
  assert.ok(figures, 'animated figures module must exist');
  const root = new THREE.Group();
  const child = new THREE.Group();
  root.add(child);
  child.add(new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshBasicMaterial()));
  child.add(new THREE.Mesh(new THREE.PlaneGeometry().toNonIndexed(), new THREE.MeshBasicMaterial()));
  assert.equal(figures.countFaces(root), 14);
  assert.equal(figures.countFaces(new THREE.Group()), 0);
});
