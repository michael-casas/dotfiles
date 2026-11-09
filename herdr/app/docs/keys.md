# Keys: `keys.json`

What every key does in the desktop app.

## Ownership caveat

On upgrade, a `keys.json` you never touched gets the new default shortcuts.
**Any edit, even whitespace, makes the whole file yours.** After that, new
default shortcuts must be added by hand. This repo tracks `keys.json`
(`herdr/app/keys.json`, symlinked by `sync.sh`), so read the changelog
after upgrades and add new defaults yourself.

## This repo's key set (macOS)

`herdr/app/keys.json` is Herdr's defaults, plus Omarchy's keys, minus what
macOS takes before Herdr sees it, plus a leader key.

Removed because macOS takes them:

| Key | Taken by |
|---|---|
| `ctrl-left/right/up/down` (Omarchy's pane movement, in `terminal` and `layout:omarchy`) | Mission Control and switching Spaces |
| `super-ctrl-space` (Omarchy's next wallpaper) | the emoji and symbols picker. `super-ctrl-w` still works |
| `super-alt-space` (Omarchy's palette) | Finder search. `ctrl-shift-p` and leader `:` still work |

`super-*` means **Cmd** on macOS (GPUI reads `super`, `cmd` and `win` as
the same modifier). In the Omarchy layout, `super-w` (Cmd-W) closes the
**pane**, not the tab. `super-f` (Cmd-F) zooms the pane outside terminals,
but inside a terminal the `terminal` section's `cmd-f` search wins.

Leader key: `ctrl-space` (bound in `global` and `terminal`) opens
`mods/leader`, a hint popup that waits for one key. macOS's own
`ctrl-space` (Select previous input source) is disabled on this machine.
If you enable it, the OS takes the key first.

| After `ctrl-space` | Action |
|---|---|
| `/` | Find a tab or agent: the built-in `picker`, which filters on tab name, space name and agents' program names; Enter goes there |
| `h j k l` or arrows | Focus the pane left, down, up or right (repeatable for 600 ms) |
| `\` or `\|` / `-` | Split right / down |
| `z` / `x` | Zoom / close the pane |
| `c`, `n` / `p`, `1`–`9` | New tab, next / previous tab (repeatable), tab 1–9 |
| `]` / `[` | Next / previous space (repeatable) |
| `:` | Command palette (Omarchy's in the Omarchy layout) |
| `t`, `?`, `s`, `L` | Themes, all key bindings, toggle sidebar, switch layout |
| `ctrl-space` | Send a literal `ctrl-space` (NUL) to the focused terminal, for example for nvim completion |
| `esc` (or any other key) | Cancel |

The second `ctrl-space` is caught by `"mod:leader": { "ctrl-space":
"leader.send-prefix" }`. Without that entry, the global binding would
close the popup instead. The leader runs `hc keys <terminal> ctrl+space`
for the literal key (verified to arrive as `^@`). To change the bindings,
edit `BINDINGS` and `REPEAT_MS` at the top of `mods/leader/main.js`, then
re-run `sync.sh`.

Moving between panes without the leader: Herdr's default
`cmd-alt-arrows`.

Numbers: `cmd-1`…`cmd-9` select **space** 1–9 (Herdr's default is tab;
`ctrl-1`…`9` also select spaces). Tabs are `ctrl-space` then `1`–`9`, or
`alt-1`…`9` in the Omarchy layout.

## Shape

```json
{
  "global": {
    "cmd-t": "tab.new",
    "cmd-d": "pane.split:right",
    "ctrl-shift-r": { "command": "layout.resize", "args": { "id": "sidebar", "px": 240 } }
  },
  "terminal":        { "ctrl-shift-c": "terminal.copy", "ctrl-left": "send:\u001bb" },
  "layout:tui":      { "cmd-alt-]": "space.next" },
  "mod:tmux-prefix": { "ctrl-b": "tmux-prefix.send-prefix" }
}
```

- Sections, most specific first: `terminal` > `layout:<name>` > `global`.
  `mod:<name>` applies while that mod has focus.
- Actions:
  - `command` or `command:value` (the value fills the first argument)
  - `send:<text>`, which types into the terminal
  - `<mod>.<command>`, delivered to that mod's `nextCommand()`
  - `terminal`, which passes the key through to the program
  - `{ "command", "args" }` for typed or multiple arguments
- Invalid bindings show an error toast and write `keys.error`.

## Rules for agents

- Do not bind keys programs rely on unless asked: ctrl+c, d, l, r, w, a,
  e, u, k, z, ctrl+[ (Escape). On many Mac keyboards, Option+digits and
  Option+letters type characters. If the person asks for one of these
  anyway, bind it and say what it takes away from typing.
- A mod's `keys.json` (from the community gallery) is **merged** into the
  person's file: add sections and keys, and ask before replacing a key
  already in use.
- `herdr-app commands` lists every command a key can call.
- If keys break the app: `ctrl-alt-shift-escape` sets aside the shown
  layout and `keys.json`.

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "Keys: keys.json"
- https://herdr.dev/mods/herdrdev/tmux-prefix (recipe: merged `keys.json` snippet, `mod:` section)
