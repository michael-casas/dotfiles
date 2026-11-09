# Layouts: `layouts/<name>.json`

A layout is the window: a tree of nodes that places blocks (mods, terminals,
the active tab) and sets the look. Each file is one layout. Switch layouts
with `ctrl-shift-l` or `layout.switch {name}`.

## Ownership

- `main`, `terminals` and `win98` are shipped. They are replaced on every
  start. If you edit one in place, the next start moves your file to
  `<name>-edited` and restores Herdr's version.
- Your own layouts are files with any other name. Herdr never updates them.

### Cloning

```sh
herdr-app do layout.clone '{"name":"main","as":"my-layout"}'   # then switches to it
```

A clone records `cloned_from` and keeps references to the shipped mods. To
change the code of one of those mods, clone the mod too
(`mod.clone`) and point the layout's `content.mod` at the clone.

Writing a new file by hand also works. That is how `tui.json` in this repo
was made: from `main.json`, with the look changed.

## Node types

| `type` | Shows |
|---|---|
| `block` | `content`: `{ "mod": "<folder>", "props": {} }`, `{ "terminal": "t7" }`, `{ "tab": "active", "pane": {…} }`, or `{ "agent": "focused" }` |
| `row` / `column` | `children` side by side or stacked |
| `stack` | One child at a time (`"active": "<child id>"`), with an optional `header` (a mod, or `"tabs"`) |

## Node properties

- `id` (unique; commands target it), `size` (`{ "px": n }` or
  `{ "weight": n }`), `min`, `max`, `hidden`
- Paint: `background` (a color, `{ "gradient": [...], "angle": n }` or
  `{ "image": "path", "fit": "cover" }`), `border`, `radius`, `shadow`
  (`sm`, `md` or `lg`), `focus`
- `padding` (`n` or `[v, h]`); for row and column nodes: `gap`, `divider`,
  `resizable`
- `movable`: inherited; set it on the root to stop panes being dragged
- `window_drag: true`: dragging the node moves the window, and a
  double-click maximizes it
- `floating`: blocks that float over this node (see below)
- Root only: `"titlebar": "none"` with `"traffic_lights": [x, y]` on macOS;
  `"preview": "layouts/<name>.svg"` (the picture Settings shows);
  `"terminal_menu": "<mod>"`
- Look fields (`theme`, `colors`, `font`, `ui_font`, …): see
  [look-and-theming.md](look-and-theming.md)
- Colors are theme names (`border`, `accent`, `chrome`) or `#rrggbb[aa]`.
  Prefer names so the layout follows light and dark themes.

## Pane frames (the tab block)

```json
{ "tab": "active",
  "pane": { "gap": 0, "radius": 0, "background": "background", "lone": true,
            "border": { "width": 1, "color": "border" },
            "focus":  { "width": 1, "color": "accent" },
            "header": { "content": { "mod": "pane" }, "height": 24,
                        "position": "top", "reveal": "always" } } }
```

- `focus` replaces `border` while the pane has the keyboard.
- `lone: true` frames a tab's only pane as well.
- `header` is a mod drawn once per pane, with `props().pane` and
  `props().terminal`. `reveal: "hover"` draws it over the terminal without
  resizing it.

## Floating blocks

```json
"floating": [ { "id": "board", "content": { "mod": "board" },
                "edge": "left", "align": "center", "peek": 52 } ]
```

A floating block sizes to its content, and people can drag it to another
edge. `peek` turns it into a drawer on a side edge. The mod reads
`placement()` and draws only its content; Herdr draws the frame.

## Clicks vs files

Clicks such as sizes, show/hide, the active stack child, floating
positions, theme picks and text size are saved in `layouts/.state/` and
survive restarts. Do not edit `.state/`. A deliberate edit to the layout
file wins over a click on the same field. `layout.reset {name}` resets a
shipped layout and its clicks.

## This repo's `tui.json`

A copy of `main` made to feel like a TUI:

- Square corners, no gaps or padding around panes, a 1px `border` with an
  `accent` outline on focus
- `terminal_padding [4, 8]`
- Slimmer sidebar (240px), brand row (38px), tabs (32px), pane header
  (24px) and status bar (24px)
- The agents list above the spaces list (the order of the `sidebar-lists`
  children), with a divider between them
- Root look: theme `nordic`, `font` and `ui_font` `Cascadia Code NF` at
  size 14
- Uses the shipped mods (`workspace-chrome`, `spaces`, `agents`, `tabs`,
  `pane`, `files`, `changes`, `workspace-status`) unchanged

## Edit loop

1. Edit the layout file and save. It applies live.
2. Check for `layout.error` in the home, and run `herdr-app status`
   (`errors`).
3. Look at the result: `herdr-app shot /tmp/x.png` or a cua-driver
   screenshot (see [verification.md](verification.md)).
4. If you break the window: `ctrl-alt-shift-escape` sets aside the shown
   layout and `keys.json` and returns to the default.

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "Layouts", "Pane frames", "Floating blocks"
- https://herdr.dev/layouts/herdrdev/pasture (recipe: layout tree with role-based mod props)
