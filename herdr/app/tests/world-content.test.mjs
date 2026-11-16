import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as THREE from '../mods/world/vendor/three.module.min.js';
import * as content from '../mods/world/content.js';

function signature(root) {
  root.updateMatrixWorld(true);
  const meshes = [];
  root.traverse((mesh) => {
    if (!mesh.isMesh) return;
    meshes.push({ name: mesh.name, matrix: mesh.matrixWorld.toArray(),
      positions: Array.from(mesh.geometry.attributes.position.array),
      indices: mesh.geometry.index ? Array.from(mesh.geometry.index.array) : null,
      color: mesh.material.color.getHex() });
  });
  return { meshes, colliders: root.userData.colliders };
}

function assertMaterials(root) {
  root.traverse((node) => {
    assert.ok(node.isGroup || node.isMesh, `unexpected object: ${node.type}`);
    if (!node.isMesh) return;
    assert.ok(node.material instanceof THREE.MeshBasicMaterial);
    assert.equal(node.material.transparent, false);
    assert.equal(node.material.opacity, 1);
    assert.equal(node.material.map, null);
  });
}

test('exports exactly the content contract and uses no ambient dependencies', async () => {
  assert.deepEqual(Object.keys(content).sort(), ['PALETTE', 'buildWorld', 'countFaces', 'makeHero', 'makeNpc'].sort());
  const source = await readFile(new URL('../mods/world/content.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /\bimport\b|\brequire\b|Math\s*\.\s*random/);
  assert.ok(Object.keys(content.PALETTE).length > 0);
});

test('world is repeatable without relying on three-generated UUIDs', () => {
  assert.deepEqual(signature(content.buildWorld(THREE, 42)), signature(content.buildWorld(THREE, 42)));
  assert.notDeepEqual(signature(content.buildWorld(THREE, 42)), signature(content.buildWorld(THREE, 43)));
});

test('world stays within geometry, material, clearance and collider budgets across seeds', () => {
  for (const seed of [0, 1, 42, 43, 999, 0xffffffff]) {
    const world = content.buildWorld(THREE, seed);
    assert.ok(world instanceof THREE.Group);
    assert.ok(content.countFaces(world) > 0);
    assert.ok(content.countFaces(world) < 700);
    assertMaterials(world);
    world.updateMatrixWorld(true);
    world.traverse((mesh) => {
      if (!mesh.isMesh) return;
      const box = new THREE.Box3().setFromObject(mesh);
      for (const x of [box.min.x, box.max.x]) {
        for (const z of [box.min.z, box.max.z]) assert.ok(Math.hypot(x, z) <= 28, mesh.name);
      }
      assert.ok(box.min.y >= -1e-6, `${mesh.name} below ground`);
      if (box.max.y < 0.1) {
        assert.ok(box.min.y >= 0.02 - 1e-6, 'raised decal');
        return;
      }
      const distance = (x, z) => Math.hypot(
        Math.max(box.min.x - x, 0, x - box.max.x),
        Math.max(box.min.z - z, 0, z - box.max.z));
      assert.ok(distance(0, 0) >= 7, `${mesh.name} enters clearing`);
      assert.ok(distance(0, 10) >= 2, `${mesh.name} enters spawn`);
    });
    assert.ok(world.userData.colliders.length > 0);
    for (const { x, z, r } of world.userData.colliders) {
      assert.ok([x, z, r].every(Number.isFinite));
      assert.ok(r > 0);
      assert.ok(Math.hypot(x, z) + r <= 28);
      assert.ok(Math.hypot(x, z) - r >= 7);
      assert.ok(Math.hypot(x, z - 10) - r >= 2);
    }
  }
});

test('characters stand on their feet, have head anchors and stay lightweight', () => {
  const npc = content.makeNpc(THREE, { color: 0x557799, accent: 0xddaa66 });
  const hero = content.makeHero(THREE);
  for (const [character, budget] of [[npc, 60], [hero, 80]]) {
    assert.ok(character instanceof THREE.Group);
    assert.ok(content.countFaces(character) < budget);
    assertMaterials(character);
    const box = new THREE.Box3().setFromObject(character);
    assert.ok(Math.abs(box.min.y) < 1e-6);
    assert.ok(box.max.y >= 1.5 && box.max.y <= 2.2);
    assert.ok(character.userData.head >= 1.5 && character.userData.head <= 2.2);
  }
  assert.ok(npc.getObjectByName('face').position.z > 0);
  assert.ok(hero.getObjectByName('face').position.z < 0);
  assert.ok(hero.getObjectByName('cloak'));
  assert.ok(npc.getObjectByName('tunic').material.color.equals(new THREE.Color(0x557799)));
  assert.ok(npc.getObjectByName('cap').material.color.equals(new THREE.Color(0xddaa66)));
});

test('face counter handles nested indexed and non-indexed geometry', () => {
  const root = new THREE.Group();
  const child = new THREE.Group();
  root.add(child);
  child.add(new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshBasicMaterial()));
  child.add(new THREE.Mesh(new THREE.PlaneGeometry().toNonIndexed(), new THREE.MeshBasicMaterial()));
  assert.equal(content.countFaces(root), 14);
  assert.equal(content.countFaces(new THREE.Group()), 0);
});
