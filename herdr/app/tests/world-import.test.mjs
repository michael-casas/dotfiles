import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import * as THREE from '../mods/world/tools/three.mjs';

const world = new URL('../mods/world/', import.meta.url);
const cli = fileURLToPath(new URL('tools/import.mjs', world));
const fixture = name => fileURLToPath(new URL(`tools/fixtures/${name}`, world));
async function temporary(t) {
  const dir = await mkdtemp(join(tmpdir(), 'world-model-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}
async function convert(t, input, options = []) {
  const out = await temporary(t);
  const summary = execFileSync(process.execPath, [cli, input, '--name', 'sample', '--out', out, ...options], { encoding: 'utf8' });
  const path = join(out, 'sample.js');
  const source = await readFile(path, 'utf8');
  assert.doesNotMatch(source, /\bimport\b|\brequire\b/);
  assert.match(source.split('\n')[0], /^\/\/ Source: .+; date: \d{4}-\d{2}-\d{2}$/);
  const { default: model } = await import(pathToFileURL(path));
  assert.equal(model.name, 'sample');
  assert.equal(model.tris, model.positions.length / 9);
  assert.equal(model.tris, model.colors.length);
  assert.ok(model.positions.every(n => Number.isFinite(n) && Math.abs(n * 1000 - Math.round(n * 1000)) < 1e-8));
  assert.ok(model.colors.every(color => /^#[0-9a-f]{6}$/.test(color)));
  assert.match(summary, /triangles.*bounds.*colors/s);
  t.diagnostic(summary.trim());
  return model;
}
for (const extension of ['glb', 'gltf']) {
  test(`${extension}: bakes nested transforms, indexed triangles and vertex colors`, async t => {
    const model = await convert(t, fixture(`scene.${extension}`));
    assert.equal(model.tris, 13);
    assert.deepEqual(model.bounds, { min: [0, 0, -3], max: [5, 2, 0] });
    assert.equal(model.colors.filter(c => c === '#cc6633').length, 12);
    assert.equal(model.colors.at(-1), '#9c9c9c');
    assert.ok(model.positions.includes(5));
  });
}
test('OBJ reads MTL diffuse colors without loading textures; scale is baked', async t => {
  const model = await convert(t, fixture('house.obj'), ['--scale', '0.5']);
  assert.deepEqual(model.bounds, { min: [0, 0, 0], max: [1, 1, 1] });
  assert.deepEqual(model.colors, ['#ff0000', '#00ff00']);
});
test('triangle budget rejects before writing a module', async t => {
  const out = await temporary(t);
  const result = spawnSync(process.execPath, [cli, fixture('scene.glb'), '--max-tris', '2', '--out', out], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /13 triangles.*--max-tris 2.*[Dd]ecimat/s);
  await assert.rejects(readFile(join(out, 'scene.js')), { code: 'ENOENT' });
});
test('runtime loader groups by color, preserves triangles and applies runtime scale', async t => {
  const source = await readFile(new URL('models/load.js', world), 'utf8');
  assert.doesNotMatch(source, /\bimport\b|\brequire\b/);
  const { toMesh } = await import(new URL('models/load.js', world));
  const model = await convert(t, fixture('scene.glb'));
  const group = toMesh(THREE, model, { scale: 2 });
  assert.ok(group instanceof THREE.Group);
  assert.equal(group.children.length, new Set(model.colors).size);
  assert.equal(group.children.reduce((n, mesh) => n + mesh.geometry.attributes.position.count / 3, 0), model.tris);
  for (const mesh of group.children) {
    assert.ok(mesh.material instanceof THREE.MeshBasicMaterial);
    assert.equal(mesh.material.map, null);
    assert.ok(model.colors.includes('#' + mesh.material.color.getHexString()));
  }
  const bounds = new THREE.Box3().setFromObject(group);
  assert.deepEqual(bounds.min.toArray(), [0, 0, -6]);
  assert.deepEqual(bounds.max.toArray(), [10, 4, 0]);
  assert.deepEqual(toMesh(THREE, model).scale.toArray(), [1, 1, 1]);
});
test('glTF external local buffers work and missing textures are ignored', async t => {
  const dir = await temporary(t);
  const json = JSON.parse(await readFile(fixture('scene.gltf'), 'utf8'));
  const data = Buffer.from(json.buffers[0].uri.split(',')[1], 'base64');
  await writeFile(join(dir, 'mesh.bin'), data);
  json.buffers[0].uri = 'mesh.bin';
  json.images = [{ uri: 'missing.png' }];
  json.textures = [{ source: 0 }];
  json.materials[0].pbrMetallicRoughness.baseColorTexture = { index: 0 };
  await writeFile(join(dir, 'external.gltf'), JSON.stringify(json));
  const model = await convert(t, join(dir, 'external.gltf'));
  assert.equal(model.tris, 13);
});
test('invalid CLI options and empty meshes fail clearly', async t => {
  const out = await temporary(t);
  for (const args of [['--scale', 'NaN'], ['--max-tris', '0'], ['--name', '../escape'], ['--wat', '1']]) {
    const result = spawnSync(process.execPath, [cli, fixture('house.obj'), '--out', out, ...args], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /scale|max-tris|name|Unknown/);
  }
  const empty = join(out, 'empty.obj');
  await writeFile(empty, '# empty\n');
  const result = spawnSync(process.execPath, [cli, empty, '--out', out], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /[Nn]o triangles/);
});
