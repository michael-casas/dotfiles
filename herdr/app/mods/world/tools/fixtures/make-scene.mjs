// Own, CC0 test geometry. Regenerate: node tools/fixtures/make-scene.mjs
import { writeFile } from 'node:fs/promises';
import * as THREE from 'three';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';

// GLTFExporter uses only these FileReader operations for texture-free scenes.
globalThis.FileReader = class {
  readAsArrayBuffer(blob) { blob.arrayBuffer().then(value => { this.result = value; this.onloadend?.(); }); }
  readAsDataURL(blob) { blob.arrayBuffer().then(value => {
    this.result = `data:${blob.type};base64,${Buffer.from(value).toString('base64')}`;
    this.onloadend?.();
  }); }
};
const scene = new THREE.Scene();
const parent = new THREE.Group();
parent.position.set(3, 0, -2);
scene.add(parent);
const box = new THREE.Mesh(new THREE.BoxGeometry(2, 2, 2), new THREE.MeshStandardMaterial({ color: 0xcc6633 }));
box.position.set(1, 1, 0);
parent.add(box);
const geometry = new THREE.BufferGeometry();
geometry.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3));
geometry.setAttribute('color', new THREE.Float32BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1], 3));
scene.add(new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ vertexColors: true })));
for (const binary of [true, false]) {
  const result = await new GLTFExporter().parseAsync(scene, { binary });
  await writeFile(new URL(binary ? 'scene.glb' : 'scene.gltf', import.meta.url),
    binary ? Buffer.from(result) : JSON.stringify(result, null, 2) + '\n');
}
