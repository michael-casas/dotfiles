# World layout (3D spike)

`layouts/world.json` hides every sidebar and bar: the window is one `world`
mod, a small night camp seen in third person. The shown workspace is the
camp, and **each tab is an NPC** (its agent) standing around a central
campfire. Walk up to one and right-click it: the tab's terminal opens over the
world as a dialog. `ctrl-space` then `b` opens a workspace switcher.

## Controls

| Input | Does |
|---|---|
| Click the world | Give it the keyboard (needed after a dialog closes) |
| `W` / `S` | Forward / back |
| `A` / `D` | Turn (strafe while the right button is held) |
| `Q` / `E` | Strafe left / right |
| `Space` | Jump |
| Hold left + move | Orbit the camera 360° around the character, and tilt it |
| Hold right + move | Turn the character with the camera (the camera returns behind it) |
| Mouse wheel | Zoom (3–11 m) |
| Quick right-click on an NPC within 3.6 m | Talk: its terminal pops over (click beside it to leave; Esc goes to the terminal) |
| `ctrl-space` `b` | Workspace switcher (`mods/space-switch`): type to filter, ↑/↓, Enter, 1–9 |

While a mouse button is held the cursor is hidden and, when it drifts 140 px
from where you pressed, warped back, so turning never stops at a screen edge.
That is `bin/world-cursor` (below). The camera pulls in when a tree, rock or
the edge of the camp is behind you.

NPC nameplates show the tab name and program; `…` while the agent works
(with a talking gesture) and `!` when it is done or blocked. NPCs face the
fire, and turn to you when you come within 6 m.

## Visitors

Any terminal can stand in a workspace's camp without moving its tab:

```bash
hc label t5 world.visit=<space id> "world.name=REP (Claude)"   # appear
hc label t5 world.visit=                                       # leave
```

## The camp (`camp.js`)

Radius 14, a ring of pines and boulders closing it off, the campfire at the
centre (stone ring, logs, three flickering flame cones), three log seats, two
tents, a lean-to, crates, a woodpile, lantern posts on the open south approach,
mushrooms. 618 triangles. `npcSlots(n)` gives fixed spots on a 5 m ring, filled
widest-first (0°, ±50°, ±100°, ±140°, then between), so a few NPCs stand far
apart, arrivals never move the others, and the south stays open. Spawn (0, 7).

## Figures (`figures.js`)

Rigid-part figures (no skinning): a hooded hero (< 90 triangles) and seeded NPC
travellers (hat/hood/helmet, backpacks, 1.6–1.9 m, < 70 triangles).
`animate(figure, { moving, airborne, talking }, t)` swings arms and legs,
tucks for jumps, breathes when idle, and gestures while talking.

## How it draws (no WebGL)

gpui-shell has no canvas or WebGL, so three.js (0.170, vendored in
`mods/world/vendor/`, MIT) is used only for scene math: its `Projector`
projects and depth-sorts triangles, and the mod paints them with native
`window.paint_path(PathBuilder…)`, one path per run of same-colored faces.
Every three.js `Mesh` is still painted triangle by triangle, so the cost is
the number of visible **triangles**, not meshes. Sky and ground are a backdrop
split at the projected horizon.

Measured in the live app (2026-11-10, this Mac):

| Visible triangles | JS per frame | Frame |
|---|---|---|
| 250 | 4 ms | 8 ms |
| 1,000 | 14 ms | 15 ms (≈ 60 fps) |
| 2,000 | 27 ms | 29 ms (≈ 30 fps) |
| 4,000 | 50 ms | 56 ms |

About 13.5 µs per triangle plus ~30 µs per color run. Budget: ~1,000 visible
triangles for 60 fps, ~2,000 for 30 fps. Frames run at 30 fps while you move
and at 8 fps otherwise (fire, breathing), and only while the world has the
keyboard.

## Your own models (`tools/import.mjs`)

Convert glTF/GLB/OBJ offline into plain modules the mod can import:

```bash
cd herdr/app/mods/world/tools && npm install        # once: three@0.170.0 for Node
node import.mjs ~/models/tree.glb --name tree --max-tris 300
```

It bakes transforms, gives each triangle one color (material or averaged
vertex colors), simplifies or refuses above `--max-tris`, and writes
`models/<name>.js`; `models/load.js` `toMesh(THREE, model)` turns it into
meshes. Textures, lights and skeletal animation don't carry over. See
`mods/world/models/README.md` for Blender export settings and licensing (your
own or CC0-style assets only).

## `bin/world-cursor` (`tools/cursor/`)

A small Swift helper, built by `sync.sh` (`tools/cursor/build.sh`):
`hold` hides the cursor (private `SetsCursorInBackground` connection property,
looked up at runtime) and waits; `recenter` warps it back to the press point;
`release` warps back and shows it. Killing it any way shows the cursor again
(macOS restores it when the process dies), and it gives up after 120 s.

## Files

| File | What |
|---|---|
| `mods/world/main.js` | Engine: input, orbit camera, jump, collisions, NPCs, painting, nameplates, talk, cursor helper |
| `mods/world/camp.js` | The camp, colliders, flames, `npcSlots` |
| `mods/world/figures.js` | Hero and NPC figures, `animate` |
| `mods/world/content.js` | The first, larger clearing (unused now; kept for reference) |
| `mods/world/vendor/` | `three.module.min.js`, `Projector.js` |
| `mods/world/tools/` | `import.mjs` + fixtures, `cursor/` (Swift helper); never copied into the app |
| `mods/world/models/` | `load.js`, generated models |
| `mods/space-switch/` | The workspace dialog |
| `tests/world-*.test.mjs` | camp, figures, content, import |

## Limits

- Talk dialogs are terminal overlays: Esc goes to the agent; close by
  clicking beside the dialog.
- The player resets to the spawn when the mod reloads or the layout changes.
- `herdr-app check mods/world` sometimes reports "interrupted": loading
  three.js plus the first render is close to check's time limit. Run it again;
  the app itself is unaffected.

Built 2026-11-10 with two pi agents (first version), then one Claude Opus 5.5
agent (cursor helper) and three pi agents (`j5/gpt-6.1-sol`: camp, figures,
importer); tested with one pi agent ("Quartermaster") plus stand-in tabs.
