# Commands and the `herdr-app` CLI

Commands are the only way to change anything in the window. Keys, mods
(`run(name, args)`), menus and agents in a shell all call the same list.

## CLI

```sh
herdr-app                       # open the window
herdr-app commands              # every command, its arguments, what it does (no window needed)
herdr-app do <command> [args]   # run one: --name x --argv '["claude"]', or one JSON object
herdr-app ls                    # spaces, tabs, terminals (sub-agents under their parent)
herdr-app status                # shown layout, focus, overlays, zoom, errors from files and mods
herdr-app shot [file.png]       # last rendered frame as PNG (no screen-recording permission needed)
herdr-app check <mod folder>    # load a mod once and report what's wrong
herdr-app feedback <text>       # draft feedback for the person to review and send
herdr-app --skill               # the agent manual for driving the window
```

`do` prints what it created, for example `{ "space", "tab", "terminal" }`.
On failure it prints `{ "error": "..." }` and exits 1. **Agents never get a
dialog**, so pass every required argument. Unknown argument names are
errors. Target IDs (`id`, `pane`, `space`, `terminal`) must be strings.

## Main commands

| Area | Commands |
|---|---|
| Spaces | `space.new {name?, folder?, tab?, argv?, task?, machine?}`, `space.close {id?, confirmed?}`, `space.rename`, `space.move`, `space.select`, `space.next`, `space.prev` |
| Tabs | `tab.new {name?, space?, folder?, argv?, task?}` or `{mod, props?}`, `tab.close`, `tab.rename`, `tab.move`, `tab.select`, `tab.next`, `tab.prev`, `tab.settle`, `tab.unsettle` |
| Panes | `pane.split {direction, pane?, argv? \| mod?, props?}`, `pane.close`, `pane.zoom`, `pane.focus {pane \| terminal}`, `pane.go {direction}`, `pane.swap` |
| Terminals | `terminal.open`, `terminal.kill`, `terminal.keep`, `terminal.park`, `terminal.peek`, `terminal.show`, `terminal.search`, `terminal.copy`, `terminal.paste`, `terminal.scroll`, `terminal.pin {terminal, pinned}`, `terminal.right_click` |
| Agents | `agent.next`, `agent.prev`, `agent.focus {terminal}` |
| Layout | `layout.switch {name?}`, `layout.toggle {id}`, `layout.show`, `layout.hide`, `layout.resize {id, px \| weight}`, `layout.select {stack, child}`, `layout.set {layout}`, `layout.reset {name?}`, `layout.clone {name, as?}` |
| App | `mod.clone {name, as?}`, `mod.open {name}`, `overlay.close`, `app.palette`, `app.settings {section?}`, `app.theme {name}`, `app.zoom_in`, `app.zoom_out`, `app.zoom_reset`, `app.reset`, `app.check_updates`, `app.update_core`, `app.feedback` |
| Window | `window.minimize`, `window.maximize`, `window.close`; macOS: `app.quit`, `app.hide`, `app.hide_others`, `app.show_all` |

`herdr-app commands` is the source of truth. This table is a map, not a
spec.

## Examples

```sh
herdr-app do layout.switch '{"name":"tui"}'
herdr-app do tab.new --name "fix login" --argv '["claude"]' --task "look at the login bug"
herdr-app do pane.split:right
herdr-app do space.new '{"name":"docs","folder":"~/.dotfiles"}'
herdr-app do space.close --id <id> --confirmed true
```

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "Commands"
- `herdr-app --help`, `herdr-app commands` (0.1.14)
