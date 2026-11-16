# Dungeon layout (mockup)

`layouts/dungeon.json` is the `tui` layout with a 220px `dungeon` mod strip
above the panes. The shown space is a dungeon, and the terminals in the shown
tab are its party, in pane order:

| Pane | Role | Icon |
|---|---|---|
| 1 | Tank | shield |
| 2 | Healer | cross |
| 3+ | Damage | sword |

Each member gets a class and spec at random, stable per space, terminal and
slot, from classic fantasy archetypes that can fill the role (Warrior,
Paladin, Druid tank; Priest, Paladin, Druid, Shaman heal; any class for
damage). Dungeon, boss and spell names and all art are original.

## What drives it

| Agent signal (herdr-core) | In the dungeon |
|---|---|
| Status turns `working`, or `turn` goes up | A boss spawns if none is alive (fades in, HP bar) |
| Status `msg` changes while working (one per tool call) | The member casts: a projectile flies to the boss, a hit flashes, damage floats up (> 20; tank 40–420, healer 21–260, dps 120–980) |
| Boss HP reaches 0 | Skull, "defeated"; the next turn or cast spawns a new boss |
| Working | The sprite bobs |

Claude Code reports a message per tool call by itself. pi only reports its
session name, so load the bundled extension to get one per tool call:

```bash
pi -e ~/.dotfiles/herdr/app/mods/dungeon/pi-tool-status.ts --model j5/gpt-6.1-sol
```

It writes `OSC 7501 state=working:app=pi:msg=<tool> #<n>` on every
`tool_execution_start`. To make it permanent, copy it into
`~/.pi/agent/extensions/` (not done: it would affect every pi session).

## Files

| File | What |
|---|---|
| `mods/dungeon/main.js` | The scene: map tiles, party, boss, projectiles, floaters, log. Polls `terminals()` every 250 ms and only redraws on events; motion uses native `transition`/`loop` |
| `mods/dungeon/game.js` | Pure, seeded logic: classes and specs, party, dungeon/boss picks, damage, spells, `snapshot`/`diff` of terminal records into `turn`/`cast`/`rest` events |
| `mods/dungeon/assets/` | 32 pixel-art SVGs: role icons, 9 class sprites, 6 bosses, 5 maps, 7 spell projectiles, hit, skull |
| `mods/dungeon/pi-tool-status.ts` | The pi extension above |
| `tests/dungeon.test.mjs` | `node --test herdr/app/tests/dungeon.test.mjs` (19 tests) |

Fights live in memory: they reset when the mod reloads or the layout
changes. Only the shown tab's party fights; other spaces wait.

## Try it

```bash
bash herdr/app/sync.sh
herdr-app do layout.switch '{"name":"dungeon"}'
herdr/app/view.sh load omarchy        # back to the saved Omarchy view
```

Built 2026-11-10: art and `game.js` by two pi agents (`j5/gpt-6.1-sol`),
tested with a party of 3 pi and 2 Claude Code agents.
