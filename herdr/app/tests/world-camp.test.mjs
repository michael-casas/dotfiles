import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as THREE from '../mods/world/vendor/three.module.min.js';

// A missing camp is an observable failure, not a test-loader failure.
let camp;
try { camp = await import('../mods/world/camp.js'); }
catch (error) { if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error; }

function signature(root) {
  root.updateMatrixWorld(true);
  const meshes = [];
  root.traverse((node) => {
    if (node.isMesh) meshes.push({ name: node.name, matrix: node.matrixWorld.toArray(),
      positions: [...node.geometry.attributes.position.array],
      indices: node.geometry.index ? [...node.geometry.index.array] : null,
      color: node.material.color.getHex() });
  });
  return { meshes, colliders: root.userData.colliders };
}

const seeds = [0, 1, 7, 42, 999, 0xffffffff];

test('camp exposes only the portable charter API', async () => {
  assert.ok(camp, 'camp implementation must exist');
  assert.deepEqual(Object.keys(camp).sort(), ['CAMP', 'buildCamp', 'countFaces', 'npcSlots'].sort());
  assert.deepEqual(camp.CAMP, { radius: 14, spawn: { x: 0, z: 7, yaw: 0 }, fire: { x: 0, z: 0 } });
  const source = await readFile(new URL('../mods/world/camp.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /\bimport\b|\brequire\b|Math\s*\.\s*random/);
});

test('camp is repeatable per seed and varies between seeds', () => {
  assert.ok(camp, 'camp implementation must exist');
  for (const seed of seeds) assert.deepEqual(signature(camp.buildCamp(THREE, seed)), signature(camp.buildCamp(THREE, seed)));
  assert.notDeepEqual(signature(camp.buildCamp(THREE, 7)), signature(camp.buildCamp(THREE, 42)));
});

test('camp meets geometry, fire, seat, boundary and spawn constraints', () => {
  assert.ok(camp, 'camp implementation must exist');
  for (const seed of seeds) {
    const root = camp.buildCamp(THREE, seed);
    assert.ok(root instanceof THREE.Group);
    assert.ok(camp.countFaces(root) > 0 && camp.countFaces(root) < 650);
    root.updateMatrixWorld(true);
    root.traverse((node) => {
      assert.ok(node.isMesh || node.isGroup, node.type);
      if (!node.isMesh) return;
      assert.ok(node.material instanceof THREE.MeshBasicMaterial);
      assert.equal(node.material.transparent, false);
      assert.equal(node.material.opacity, 1);
      assert.equal(node.material.map, null);
      const positions = node.geometry.attributes.position;
      for (let i = 0; i < positions.count; i++) {
        const p = new THREE.Vector3().fromBufferAttribute(positions, i).applyMatrix4(node.matrixWorld);
        assert.ok(Math.hypot(p.x, p.z) <= 15.5, node.name);
        assert.ok(p.y >= -1e-6, `${node.name} below ground`);
      }
    });
    const { colliders, flames } = root.userData;
    assert.ok(colliders.length > 0);
    assert.ok(flames.length >= 2);
    for (const flame of flames) {
      assert.ok(flame.isMesh && flame.name.startsWith('flame-'));
      assert.equal(root.getObjectByName(flame.name), flame);
    }
    assert.ok(colliders.some((c) => c.x === 0 && c.z === 0 && Math.abs(c.r - 1.1) < 0.1));
    const seats = colliders.filter((c) => c.kind === 'seat');
    assert.ok(seats.length >= 3 && seats.length <= 4);
    for (const seat of seats) assert.ok(Math.hypot(seat.x, seat.z) >= 3.2 && Math.hypot(seat.x, seat.z) <= 3.6);
    for (const c of colliders) {
      assert.ok([c.x, c.z, c.r].every(Number.isFinite) && c.r > 0);
      assert.ok(Math.hypot(c.x, c.z) + c.r <= 15.5);
      assert.ok(Math.hypot(c.x, c.z - camp.CAMP.spawn.z) >= c.r + 0.4, 'spawn clearance');
    }
    // A player-sized collision envelope closes the boundary at every heading.
    for (let degree = 0; degree < 360; degree++) {
      const angle = degree * Math.PI / 180;
      assert.ok(colliders.some((c) => Math.hypot(13.5 * Math.sin(angle) - c.x,
        13.5 * Math.cos(angle) - c.z) <= c.r + 0.4), `boundary gap at ${degree}`);
    }
    for (let z = 1.6; z <= 9; z += 0.2) {
      assert.ok(colliders.every((c) => Math.hypot(c.x, c.z - z) >= c.r + 0.4), 'south approach');
    }
  }
});

test('one through twelve NPCs face the fire with clear, separated standing slots', () => {
  assert.ok(camp, 'camp implementation must exist');
  for (let n = 1; n <= 12; n++) {
    const slots = camp.npcSlots(n);
    assert.equal(slots.length, n);
    assert.deepEqual(slots, camp.npcSlots(n));
    for (const [i, slot] of slots.entries()) {
      const r = Math.hypot(slot.x, slot.z);
      assert.ok(r >= 2.6 - 1e-9 && r <= 5.5);
      assert.ok(Math.abs(Math.atan2(slot.x, slot.z)) >= 35 * Math.PI / 180);
      assert.ok(Math.abs(slot.yaw - Math.atan2(-slot.x, -slot.z)) <= 1e-6);
      for (const other of slots.slice(0, i)) assert.ok(Math.hypot(slot.x - other.x, slot.z - other.z) >= 1.5);
      for (const seed of seeds) {
        for (const c of camp.buildCamp(THREE, seed).userData.colliders) {
          const clearance = Math.hypot(slot.x - c.x, slot.z - c.z) - c.r;
          assert.ok(clearance >= (c.kind === 'seat' ? 1.2 : 0.4), 'NPC collider clearance');
        }
      }
    }
  }
  const [north] = camp.npcSlots(1);
  assert.equal(north.x, 0);
  assert.ok(north.z < 0);
  assert.deepEqual(camp.npcSlots(0), []);
});

test('face counter handles nested indexed and non-indexed geometry', () => {
  assert.ok(camp, 'camp implementation must exist');
  const root = new THREE.Group();
  const nested = new THREE.Group();
  root.add(nested);
  nested.add(new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshBasicMaterial()));
  nested.add(new THREE.Mesh(new THREE.PlaneGeometry().toNonIndexed(), new THREE.MeshBasicMaterial()));
  assert.equal(camp.countFaces(root), 14);
  assert.equal(camp.countFaces(new THREE.Group()), 0);
});
