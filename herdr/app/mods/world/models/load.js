// Pure QuickJS adapter: the caller supplies its three.js namespace.
export function toMesh(THREE, model, { scale = 1 } = {}) {
  if (!Number.isFinite(scale) || scale <= 0) throw new Error('scale must be finite and positive');
  if (!model || !Number.isInteger(model.tris) || model.tris < 0 ||
      !Array.isArray(model.positions) || model.positions.length !== model.tris * 9 ||
      !Array.isArray(model.colors) || model.colors.length !== model.tris ||
      !model.positions.every(Number.isFinite) ||
      !model.colors.every(color => typeof color === 'string' && /^#[0-9a-fA-F]{6}$/.test(color))) {
    throw new Error('Invalid triangle model');
  }
  const buckets = new Map();
  for (let triangle = 0; triangle < model.tris; triangle++) {
    const color = model.colors[triangle];
    if (!buckets.has(color)) buckets.set(color, []);
    const positions = buckets.get(color);
    for (let i = triangle * 9; i < triangle * 9 + 9; i++) positions.push(model.positions[i]);
  }
  const group = new THREE.Group();
  group.name = model.name;
  group.scale.setScalar(scale);
  for (const [color, positions] of buckets) {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    geometry.computeVertexNormals();
    group.add(new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ color })));
  }
  return group;
}
