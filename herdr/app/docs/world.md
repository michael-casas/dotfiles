# World layout (3D spike)

`layouts/world.json` hides every sidebar and bar: the window is one `world`
mod, a small low-poly clearing seen in third person. The shown workspace is
the world, and **each tab is an NPC** (its agent). Walk up to one and
right-click it: the tab's terminal opens over the world as a dialog, like
talking to a character. `ctrl-space` then `b` opens a workspace switcher.

## Controls

| Input | Does |
|---|---|
| Click the world | Give it the keyboard (needed after a dialog closes) |
| `W` / `S` | Forward / back |
| `A` / `D` | Turn (strafe while the right button is held) |
| `Q` / `E` | Strafe left / right |
| Hold right button + move | Turn character and camera together |
| Quick right-click on an NPC within reach (4.2 m) | Talk: its terminal pops over (click outside to leave; Esc goes to the terminal) |
| `ctrl-space` `b` | Workspace switcher (`mods/space-switch`): type to filter, ↑/↓, Enter, 1–9 |

NPC nameplates show the tab name and program; `…` while the agent works and
`!` when it is done or blocked. NPCs turn to face you when you are close.

## How it draws (no WebGL)

gpui-shell has no canvas or WebGL, so three.js (0.170, vendored in
`mods/world/vendor/`, MIT) is used only for scene math: its `Projector`
projects and depth-sorts the triangles, and the mod paints them with native
`window.paint_path(PathBuilder…)`, one path per run of same-colored faces.
Sky and ground are a backdrop split at the projected horizon; faces crossing
the near plane are dropped. About 160–250 faces in 6–8 ms per frame on this
Mac. Frames run (30 fps timer) only while a key or the right button is held.

## Files

| File | What |
|---|---|
| `mods/world/main.js` | Engine: input, camera, collisions, NPCs from tabs, painting, nameplates, talk |
| `mods/world/content.js` | Scene: pines, huts, campfire, pond, fences, rocks, flowers; `makeNpc`, `makeHero` (516 / 55 / 63 triangles) |
| `mods/world/vendor/` | `three.module.min.js` and `Projector.js` (import path rewritten) |
| `mods/space-switch/` | The workspace dialog |
| `tests/world-content.test.mjs` | `node --test herdr/app/tests/world-content.test.mjs` |

## Limits of the spike

- No pointer lock: turning stops when the pointer leaves the window.
- Talk dialogs are plain terminal overlays; Esc goes to the agent, so close
  by clicking beside the dialog.
- Player position resets when the mod reloads or the layout changes.
- NPCs stand on a fixed ring (one NPC stands in the middle).

Built 2026-11-10: `content.js` and `space-switch` by two pi agents
(`j5/gpt-6.1-sol`), tested with one pi agent as the NPC "Quartermaster".
