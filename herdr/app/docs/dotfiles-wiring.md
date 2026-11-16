# Dotfiles wiring: `herdr/app/` to `~/.config/herdr-app/`

How this repo tracks the Herdr app's personal config, and the rules for
adding to it.

## Model: symlink each file you own

Track only files you own (see [overview.md](overview.md#who-owns-each-file)).
Each one is symlinked from the app home into `~/.dotfiles/herdr/app/`.

```text
~/.config/herdr-app/settings.json         -> ~/.dotfiles/herdr/app/settings.json
~/.config/herdr-app/themes/nordic.json    -> ~/.dotfiles/herdr/app/themes/nordic.json
~/.config/herdr-app/layouts/tui.json      -> ~/.dotfiles/herdr/app/layouts/tui.json
~/.config/herdr-app/layouts/tui.svg       -> ~/.dotfiles/herdr/app/layouts/tui.svg
```

Rejected alternatives:

- **Symlink the whole home, or set `HERDR_APP_HOME` to the repo.** The app
  writes generated files, state, sockets and telemetry into its home. A
  `HERDR_APP_HOME` set in a shell profile is not seen by Finder launches.
- **Copy files.** They drift, and changes made in the Settings window
  would never reach the repo.

## Verified behavior

- **Writes go through symlinks.** With `settings.json` symlinked,
  `herdr-app do app.zoom_in` and `app.zoom_reset` updated the target file
  and left the link in place. So changes made in the Settings window land
  in the repo. (Tested 2026-11-09, herdr-app 0.1.14.)
- **Symlinked theme and layout files load.** `layout.switch {"name":"tui"}`
  worked, and `herdr-app status` reported `"errors": []`.
- **Symlinked mod folders don't work.** The mod's JavaScript runs and
  `herdr-app check` passes, but its SVG and image assets don't render.
  Copy mod folders instead (see `sync.sh` and
  [omarchy.md](omarchy.md)). A symlinked `backgrounds/<dir>` does work.
  (Tested 2026-11-09, herdr-app 0.1.14.)

## What to track and what never to track

Track:

- `settings.json`, `programs.json`
- `keys.json`. Once you track it, the app treats the whole file as yours
  and stops merging new default shortcuts on upgrade. Add new defaults by
  hand after reading the changelog.
- Your own `layouts/<name>.json` (plus a preview `.svg` or `.png`),
  `mods/<name>/` (installed by copying, not symlinking) and
  `themes/<name>.json`.
- Community packages as a submodule of a private fork, installed with a
  sync script (`herdr/app/omarchy` + `sync.sh`).

Never track, and never symlink:

- Shipped layouts and mods, `frame/`, `icons/`, `AGENTS.md`, `*.d.ts`
- `layouts/.state/`, `shared.json`, `data/`, `seen.json`,
  `installed.json`, `view.json`, `window*.json`, `telemetry/`, the socket

Do not edit a shipped file in place. To change one, clone it under a new
name and track the clone (see [layouts.md](layouts.md#cloning)).

## Installing on a machine

`setup.sh` does **not** call it yet. Run the installer by hand:

```bash
git -C ~/.dotfiles submodule update --init herdr/app/omarchy
bash ~/.dotfiles/herdr/app/sync.sh
```

`sync.sh` symlinks `settings.json`, `keys.json`, `programs.json`, our
themes and layouts, and the Omarchy fork's themes, layout and wallpapers.
It **copies** every mod folder (`herdr/app/mods/*` and the fork's
`omarchy-*`). Re-run it after changing any mod. `ln -sfn` replaces live
files, so back them up first if they hold changes that aren't in the repo.
To wire it into `setup.sh`, add a block that calls it, following the
existing `herdr/config.toml` block.

## Working from a treehouse worktree

To preview changes from a worktree, run the worktree's `herdr/app/sync.sh`.
**Before** `treehouse return`, run `~/.dotfiles/herdr/app/sync.sh` (after
the merge and `git submodule update --init`), so the links point back to
`~/.dotfiles/herdr/app/`. Otherwise they dangle and the app falls back to
defaults. Check with `ls -l ~/.config/herdr-app/{settings.json,themes,layouts}`.

## Sources

- Empirical tests on this machine, 2026-11-09
- `~/.config/herdr-app/AGENTS.md` (0.1.14): "The files", "Keys"
