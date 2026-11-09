# Keys: `keys.json`

What every key does in the desktop app.

## Ownership caveat

On upgrade, a `keys.json` you never touched gets the new default shortcuts.
**Any edit, even whitespace, makes the whole file yours.** After that, new
default shortcuts must be added by hand. Before tracking `keys.json` in this
repo, accept that trade-off. It is not tracked today.

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
