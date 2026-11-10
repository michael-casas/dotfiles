# Views: save and swap the whole app setup

A **view** is a saved, restorable Herdr app setup: `herdr/app` at one
dotfiles commit (layouts, themes, `keys.json`, `settings.json`, our mods, and
the Omarchy fork pinned by the submodule) plus the clicks the app keeps
outside git in `layouts/.state/<layout>.json` (node sizes, hidden nodes,
chosen stack children).

`herdr/app/view.sh` saves and loads them.

| Command | What it does |
|---|---|
| `view.sh save <name>` | Records the shown layout and its clicks in `views/<name>.json`, commits that file, tags the commit `herdr-view/<name>`. Refuses while `herdr/app` has uncommitted changes. `save -f` moves an existing tag |
| `view.sh load <name>` | Exports the tag (and the fork commit it pins) to `~/.local/share/herdr-views/<name>/`, installs that copy with its own `sync.sh`, switches to its layout and replays its clicks |
| `view.sh live` | Points the app back at the checkout (`sync.sh`) |
| `view.sh list` | Saved views |

## Saved views

| Name | Layout | What |
|---|---|---|
| `omarchy` | `omarchy` | The Omarchy fork as of 2026-11-10: Cascadia Code NF, macOS key set, `ctrl-space` leader, key-hint tooltips, `cmd-1…9` spaces, sidebar 308px |
| `2dungeon` | `dungeon` | The dungeon mockup ([dungeon.md](dungeon.md)) on the `tui` base, Nordic theme |

## How it isolates

A loaded view runs from its export, not from the checkout, so switching
branches or editing `herdr/app` doesn't change it. Writes the app makes while
a view is loaded go to the export copy and are lost on the next `load`:

- Settings changes through the `settings.json` symlink, for example
  `omarchy-themes` writing `appearance`.
- The Omarchy wallpaper button, which runs `layout.set` on `omarchy.json`.

To keep such a change, run `view.sh live`, make the change again in the
checkout, commit, and `save -f`.

## Trying a new idea

```bash
herdr/app/view.sh save omarchy        # once: freeze what works
git switch -c feat/<idea>             # work in the checkout, then:
bash herdr/app/sync.sh                # see the idea live
herdr/app/view.sh load omarchy        # swap back to the saved view
herdr/app/view.sh live                # swap to the idea again
```

Give a new layout its own name (`layout.clone`), so it doesn't share click
state or `layout:<name>` keys with the saved one.

Leftovers: a load doesn't remove mods, themes or layouts that another branch
installed. They stay in the app home, unused until something selects them.
