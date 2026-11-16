#!/usr/bin/env node
// Offline conversion only: no Node dependencies reach the generated module.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { basename, dirname, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OBJLoader } from 'three/examples/jsm/loaders/OBJLoader.js';
import { MTLLoader } from 'three/examples/jsm/loaders/MTLLoader.js';

function options(args) {
  const input = args.shift();
  if (!input || input.startsWith('--')) throw new Error('Usage: node tools/import.mjs <in.glb|in.gltf|in.obj> [--name foo] [--scale 1] [--max-tris 800] [--out directory]');
  const values = { name: basename(input, extname(input)), scale: '1', 'max-tris': '800', out: fileURLToPath(new URL('../models/', import.meta.url)) };
  while (args.length) {
    const flag = args.shift();
    if (!['--name', '--scale', '--max-tris', '--out'].includes(flag)) throw new Error(`Unknown option: ${flag}`);
    const value = args.shift();
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${flag}`);
    values[flag.slice(2)] = value;
  }
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(values.name) || values.name === 'load') throw new Error('--name must be a safe basename (letters, digits, _ or -), not load');
  const scale = Number(values.scale), maxTris = Number(values['max-tris']);
  if (!Number.isFinite(scale) || scale <= 0) throw new Error('--scale must be finite and positive');
  if (!Number.isSafeInteger(maxTris) || maxTris <= 0) throw new Error('--max-tris must be a positive integer');
  return { input: resolve(input), name: values.name, scale, maxTris, out: resolve(values.out) };
}

function arrayBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}

function localPath(directory, uri) {
  if (/^[a-z][a-z\d+.-]*:|^\/\//i.test(uri)) throw new Error(`Only local asset references are supported: ${uri}`);
  return resolve(directory, decodeURIComponent(uri));
}

async function loadGltf(input, data) {
  const loader = new GLTFLoader();
  // Parser hooks avoid all image/DOM access and Node's lack of file: fetch.
  loader.register(parser => {
    const originalLoadBuffer = parser.loadBuffer.bind(parser);
    parser.loadBuffer = async index => {
      const uri = parser.json.buffers[index].uri;
      if (uri === undefined) return originalLoadBuffer(index); // GLB binary chunk
      if (uri.startsWith('data:')) {
        const match = /^data:[^,]*;base64,(.*)$/s.exec(uri);
        if (!match) throw new Error('Geometry data URIs must use base64');
        return arrayBuffer(Buffer.from(match[1], 'base64'));
      }
      return arrayBuffer(await readFile(localPath(dirname(input), uri)));
    };
    // Cover ordinary and extension texture paths without decoding any images.
    parser.loadTexture = () => Promise.resolve(null);
    parser.loadTextureImage = () => Promise.resolve(null);
    return { name: 'WORLD_OFFLINE', loadTexture: () => Promise.resolve(null) };
  });
  const result = await loader.parseAsync(arrayBuffer(data), '');
  return result.scene;
}

async function loadObj(input, data) {
  const text = data.toString('utf8');
  const loader = new OBJLoader();
  // OBJLoader reports mtllib declarations even before materials are supplied.
  const libraries = loader.parse(text).materialLibraries;
  const materials = {};
  for (const library of libraries) {
    const path = localPath(dirname(input), library);
    const mtl = await readFile(path, 'utf8');
    // Keep diffuse/material properties; never let MTLLoader create image loaders.
    const flat = mtl.split(/\r?\n/).filter(line => !/^\s*(?:map_\S+|bump|disp|decal|norm|refl)\s/i.test(line)).join('\n');
    const creator = new MTLLoader().parse(flat, '');
    creator.preload();
    Object.assign(materials, creator.materials);
  }
  if (libraries.length) loader.setMaterials({ create: name => materials[name] || new THREE.MeshBasicMaterial() });
  return loader.parse(text);
}

function triangleColor(geometry, indices, material) {
  const attribute = geometry.getAttribute('color');
  if (!attribute) return '#' + (material.color || new THREE.Color(0xffffff)).getHexString();
  const color = new THREE.Color(0, 0, 0);
  for (const index of indices) {
    color.r += attribute.getX(index) / 3;
    color.g += attribute.getY(index) / 3;
    color.b += attribute.getZ(index) / 3;
  }
  return '#' + color.getHexString();
}

function flatten(root, { name, scale, maxTris }) {
  const positions = [], colors = [], bounds = { min: [Infinity, Infinity, Infinity], max: [-Infinity, -Infinity, -Infinity] };
  const point = new THREE.Vector3();
  root.updateMatrixWorld(true);
  // One traversal owns transform baking, material-group selection and output order.
  root.traverseVisible(mesh => {
    if (!mesh.isMesh) return;
    if (mesh.isSkinnedMesh || mesh.isInstancedMesh) throw new Error('Skinning/instancing is unsupported; export static, realized meshes');
    const geometry = mesh.geometry, attribute = geometry.getAttribute('position');
    const count = geometry.index ? geometry.index.count : attribute.count;
    const start = geometry.drawRange.start, end = Math.min(count, start + geometry.drawRange.count);
    if (start % 3 || (end - start) % 3) throw new Error('Geometry is not a complete triangle list');
    for (let i = start; i < end; i += 3) {
      const group = geometry.groups.find(g => i >= g.start && i < g.start + g.count);
      const material = Array.isArray(mesh.material) ? mesh.material[group ? group.materialIndex : 0] : mesh.material;
      if (!material || !material.visible) continue;
      const indices = [0, 1, 2].map(offset => geometry.index ? geometry.index.getX(i + offset) : i + offset);
      if (mesh.matrixWorld.determinant() < 0) [indices[1], indices[2]] = [indices[2], indices[1]];
      for (const index of indices) {
        point.fromBufferAttribute(attribute, index).applyMatrix4(mesh.matrixWorld).multiplyScalar(scale);
        point.toArray().forEach((value, axis) => {
          const rounded = Math.round(value * 1000) / 1000;
          if (!Number.isFinite(rounded)) throw new Error('Geometry contains non-finite positions');
          positions.push(rounded);
          bounds.min[axis] = Math.min(bounds.min[axis], rounded);
          bounds.max[axis] = Math.max(bounds.max[axis], rounded);
        });
      }
      colors.push(triangleColor(geometry, indices, material));
    }
  });
  if (!colors.length) throw new Error('No triangles found; export static mesh geometry');
  if (colors.length > maxTris) throw new Error(`${colors.length} triangles exceeds --max-tris ${maxTris}. Decimate in Blender and re-export, or explicitly increase --max-tris.`);
  return { name, tris: colors.length, bounds, positions, colors };
}

async function main() {
  const config = options(process.argv.slice(2));
  const extension = extname(config.input).toLowerCase();
  if (!['.glb', '.gltf', '.obj'].includes(extension)) throw new Error('Expected .glb, .gltf or .obj input');
  const data = await readFile(config.input);
  const root = extension === '.obj' ? await loadObj(config.input, data) : await loadGltf(config.input, data);
  const model = flatten(root, config);
  await mkdir(config.out, { recursive: true });
  const source = basename(config.input).replace(/[\r\n\u2028\u2029]/g, ' ');
  const header = `// Source: ${source}; date: ${new Date().toISOString().slice(0, 10)}\n`;
  await writeFile(resolve(config.out, `${config.name}.js`), header + `export default ${JSON.stringify(model)};\n`);
  const palette = [...new Set(model.colors)].sort();
  console.log(`${config.name}: ${model.tris} triangles; bounds ${JSON.stringify(model.bounds)}; colors ${palette.length} (${palette.join(', ')})`);
}

main().catch(error => { console.error(`Model conversion failed: ${error.message}`); process.exitCode = 1; });
