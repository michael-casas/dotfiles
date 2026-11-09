# Look and theming: fonts, themes, colors

How the app decides fonts and colors, and how this repo makes it match the
shell (Cascadia Code NF, Nordic).

## Precedence

From highest to lowest:

1. **The theme picker** (`app.theme {name}`, Settings → Look). It wins over
   everything and is stored per layout in `layouts/.state/`.
2. **The layout's look:** fields on its root node.
3. **`settings.json`:** fills whatever the layout leaves unset.
4. **Herdr defaults:** JetBrains Mono 14 for terminals, Geist for the UI,
   and the `graphite` (dark) or `paper` (light) theme.

Today only the root node's look applies. A block's own look is planned but
not yet supported.

## Look fields

These can be set on a layout's root node or in `settings.json`:

| Field | Meaning |
|---|---|
| `font`, `font_size` | Terminal font family and size (px at zoom 1). |
| `ui_font` | Mods' font: sidebar, tabs, headers, status bar. Mods set their own text sizes. |
| `theme` | `graphite`, `ink`, `moss`, `paper`, a `themes/<name>.json` name, or `{ "light": …, "dark": … }`. |
| `colors` | Overrides for individual theme colors, by name. |
| `terminal_padding` | `[vertical, horizontal]` px inside each terminal. |
| `terminal_opacity` | 0..1. Below 1, the background behind a terminal shows through. |

These are only valid in `settings.json`: `zoom` (0.5–3), `font_ligatures`,
`minimum_contrast` (1–21), `appearance` (`light` or `dark`),
`option_as_alt`, `pane_scrollbars`, `clipboard_write`, `sounds`,
`telemetry`.

Fonts: any installed font works. A terminal font the machine lacks falls
back to JetBrains Mono. A layout can bring its own `.ttf` or `.otf` files
in `mods/<mod>/fonts/` or in the home's `fonts/`.

## Theme files: `themes/<name>.json`

```json
{ "background": "#rrggbb", "foreground": "#rrggbb", "selection": "#rrggbb",
  "cursor": "#rrggbb", "ansi": [ "16 colors" ], "colors": { "<name>": "#rrggbb" } }
```

The app derives panel colors from the base colors. Use `colors` to override
any of these named colors:

`background` (terminals, cards) · `canvas` (behind cards) · `chrome`
(sidebars, bars) · `surface` · `popover` · `raised` · `hover` · `selected` ·
`border` · `input` (a stronger border) · `foreground` · `muted` · `dim` ·
`accent` · `accent_foreground` · `solid` · `solid_foreground` (primary
button) · `selection` · `working` · `blocked` · `done` · `idle` · `unknown` ·
`ansi0`..`ansi15`.

A theme named after a layout (for example `themes/win98.json`) belongs to
that layout, and Settings offers it only there. New theme files appear in
Settings automatically.

## This repo's look

- `settings.json`: `font` and `ui_font` are `"Cascadia Code NF"`, with
  `font_size` 14 and `theme` `"nordic"`. The built-in layouts follow these
  too.
- `themes/nordic.json`: the same palette as `ghostty/config` (Nordic from
  `AlexvZyl/nordic.nvim`, reduced_blue). Main overrides: `canvas` and
  `chrome` `#1E222A`, `border` `#3B4252`, `accent` `#88C0D0`, and status
  colors `working` `#EBCB8B`, `blocked` `#BF616A`, `done` `#A3BE8C`,
  `idle` `#4C566A`.
- `layouts/tui.json` sets the same font and theme on its root, so it looks
  the same even if `settings.json` changes.

Keep these three in sync with `ghostty/config` and
`nvim/lua/plugins/colorscheme.lua` when the palette changes.

Run `fc-list : family | grep -i cascadia` to see the family names. Use
`Cascadia Code NF` (Nerd Font glyphs), not `Cascadia Code`.

## Known gaps

- **Rounded shapes:** shipped mods hardcode some of their shapes. The tab
  pills use `.rounded(7)` and the sidebar rows are rounded too. A layout or
  theme cannot square them. Clone the mod and edit the copy (see
  [mods.md](mods.md)).
- **Hardcoded fonts:** `mods/changes` falls back to `"JetBrains Mono"` when
  no font is set. The Settings frame uses its own default font in one
  preview. Neither can be overridden.
- **Terminal program colors:** text colors inside a terminal come from the
  program. Claude Code and nvim draw their own colors, and the app theme
  sets only the ANSI palette and background.

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "The look: on the layout, cascading", "The person: settings.json"
- `~/.config/herdr-app/herdr.d.ts`: `theme()`
- https://herdr.dev/guide ("Your look")
