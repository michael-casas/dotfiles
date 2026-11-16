# Bring your own low-poly models

The world mod runs in QuickJS, without a DOM or WebGL. Convert assets **offline
in Node**, then ship only the generated plain JavaScript model and `load.js`.
Nothing is loaded from the source asset at runtime.

## Prepare in Blender

- Use your own models or assets whose license permits this use and distribution
  (for example CC0 packs). **Never use assets ripped from games.** Keep attribution
  and license notices for assets that require them. Conversion does not grant rights.
- Use flat material base colors or vertex colors. Each triangle gets one color;
  vertex colors are averaged in linear RGB, then stored as an sRGB `#rrggbb` value.
  Vertex colors take precedence over the material base color.
- Keep each model under **800 triangles** by default, preferably far fewer when
  placing many copies. Use Blender's Decimate modifier, inspect the result, then
  apply it. The tool rejects models over the limit; it does not silently simplify.
- Apply transforms (`Ctrl+A` → Rotation & Scale), realize instances, convert objects
  to meshes, and triangulate. Scene/node transforms are also baked by the converter.
- Use **Y-up** in the exported file and **1 unit = 1 metre**. Blender's glTF exporter
  performs its normal Z-up → Y-up conversion. For OBJ, explicitly choose Y-up.
- Export glTF 2.0 **GLB** (recommended), glTF with embedded or local `.bin` buffers,
  or OBJ with an optional `mtllib` `.mtl` sidecar. Keep OBJ and MTL together.
- Export static meshes. Animations are not played, skinning/instancing is rejected,
  and morph animation is not baked. Apply poses/modifiers before exporting.
- Textures/images (including missing image files), lighting, transparency and PBR
  effects are ignored. Use material base colors instead. Compression requiring an
  external decoder (such as Draco) is not supported. Geometry must be local: no
  network buffer downloads. OBJ without an MTL uses the loader's default color;
  a declared but missing MTL is an error.

## Convert

From the dotfiles root:

```sh
node herdr/app/mods/world/tools/import.mjs path/to/cottage.glb --name cottage
node herdr/app/mods/world/tools/import.mjs path/to/tree.obj \
  --name tree --scale 0.5 --max-tris 300 --out /tmp/world-models
```

Options:

- `--name`: output basename and model name; defaults to the input stem. Use letters,
  digits, `_` and `-`, starting with a letter or digit. `load` is reserved.
- `--scale`: positive finite multiplier baked into all world-space coordinates;
  default `1`.
- `--max-tris`: positive integer; default `800`. Over-budget input fails clearly
  before writing a model. Decimate and retry or explicitly raise the limit.
- `--out`: output directory; default is this `models/` directory, independently of
  the current working directory. Successful conversion replaces `<name>.js` there.

The summary prints triangle count, bounds and the distinct colors used. Output is:

```js
// Source: cottage.glb; date: YYYY-MM-DD
export default {
  name: 'cottage',
  tris: 1,
  bounds: { min: [0, 0, 0], max: [1, 1, 0] },
  positions: [0, 0, 0, 1, 0, 0, 0, 1, 0],
  colors: ['#cc6633']
};
```

Positions are unindexed triangle vertices, rounded to three decimals. Bounds are
computed from those stored coordinates, after transforms and scale. Extremely small
triangles may collapse at that precision. Mirrored transforms have winding corrected.

### Offline dependency

The converter, the fixture generator and the tests need three@0.170.0 in Node.
It is pinned in `mods/world/tools/package.json`; install it once:

```bash
cd herdr/app/mods/world/tools && npm install
```

`tools/` and `node_modules/` are never copied into the app. Generated models
in `models/` have no dependencies.

## Use in the mod

In a world content module (example only; the converter does not modify the scene):

```js
import * as THREE from '../vendor/three.module.min.js';
import cottage from './cottage.js';
import { toMesh } from './load.js';

const building = toMesh(THREE, cottage, { scale: 1 });
building.position.set(10, 0, -8);
scene.add(building);
```

Those paths assume the consuming module is in `models/`; adjust relative paths
for another location. If the content builder already receives `THREE`, use that
namespace instead. `toMesh` itself has no dependencies or host calls: it returns a
`THREE.Group` with one nonindexed `BufferGeometry` / `MeshBasicMaterial` mesh per
color. Runtime `scale` scales the group, separately from baked CLI scale. Normals
are computed for the world's face projector. Scene placement and colliders remain
the caller's responsibility. Dispose each child's geometry/material when no longer
needed. The current world painter may apply its own normal-based color shading.

## Verify

```sh
node --test herdr/app/tests/world-import.test.mjs
# Optional: regenerate our own CC0, texture-free GLB and glTF fixtures:
node herdr/app/mods/world/tools/fixtures/make-scene.mjs
```

Fixtures cover a nested, translated colored box plus a vertex-colored triangle,
and a two-material OBJ with a deliberately missing texture. Tests also exercise
local external buffers, baked scale, budget rejection, dependency-free generated
modules, and runtime grouping/triangle counts. No asset downloads are needed.
