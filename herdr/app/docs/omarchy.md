# Omarchy layout (private fork)

The `omarchy` layout is the community layout
`shafiqimtiaz/herdr-omarchy`, installed from a **private fork**:
`github.com/michael-casas/herdr-omarchy`. Its look is Omarchy's desktop:
square bordered tiles over a wallpaper, a top bar, Omarchy's 23 themes and
their wallpapers, and 14 `omarchy-*` mods.

## Where it lives

| Piece | Location |
|---|---|
| Source | Submodule `herdr/app/omarchy` → `michael-casas/herdr-omarchy` (`origin`), with `upstream` = `shafiqimtiaz/herdr-omarchy` |
| Installer | `herdr/app/sync.sh` (installs all of `herdr/app/`, including this) |
| Mods | **Copied** to `~/.config/herdr-app/mods/omarchy-*` by the installer |
| Themes, layout, wallpapers | **Symlinked** from the submodule (`themes/*.json`, `layouts/omarchy.{json,svg}`, `backgrounds/omarchy`) |
| Keys | Tracked `herdr/app/keys.json` (symlinked): the fork's keys merged in, adapted for macOS (see [keys.md](keys.md#this-repos-key-set-macos)) |

Mods are copied, not symlinked, because herdr-app 0.1.14 runs a symlinked
mod folder's JavaScript but does not load its SVG and image assets. The icons
disappear even though `herdr-app check` passes.

## Fork changes vs upstream

1. `layouts/omarchy.json`: `font` and `ui_font` changed to `Cascadia Code NF`
   (upstream uses CaskaydiaMono Nerd Font, which isn't installed here).
2. `layouts/omarchy.json`: the `ai-usage` block is replaced by an empty
   `row` spacer of the same weight, and `omarchy-ai-usage` is not installed.
   That mod reads AI login tokens to fetch quotas. It will be replaced by a
   cliproxyapi-based meter. A `hidden` block is not enough, because the
   app still loads a hidden block's mod.

Everything else is as published, including the default theme
(`tokyo-night`). The fork's own `keys.json` is unchanged. The macOS
adaptation lives in this repo's tracked `herdr/app/keys.json` instead.

## Install or update

```bash
git submodule update --init herdr/app/omarchy   # once per checkout
bash herdr/app/sync.sh                          # after any change in the fork
herdr-app do layout.switch '{"name":"omarchy"}'
```

Keys: if upstream changes its `keys.json`, merge the new bindings into
`herdr/app/keys.json` by hand. Leave out the ones macOS takes (listed in
[keys.md](keys.md#this-repos-key-set-macos)).

## Pull upstream changes

```bash
cd herdr/app/omarchy
git fetch upstream && git merge upstream/main   # resolve conflicts against the two fork changes
git push origin HEAD:main
cd - && bash herdr/app/sync.sh
git add herdr/app/omarchy && git commit -m "chore(herdr): bump omarchy fork"
```

Then run `herdr-app check` on each `omarchy-*` mod, confirm `herdr-app
status` errors are empty, and take a screenshot (see
[verification.md](verification.md)).

## What it runs (audited 2026-11-09 at upstream `2c8c985`)

- `git` (spaces, files, changes, commit graph), plus `find` and `env` for the
  graph's multi-repo fetch.
- `sh` to list folders, and `ls` and `herdr-app do layout.set` for the
  wallpaper.
- `python3` and `hc connect` to reopen closed tabs. Agent session detection
  reads Linux `/proc`, so on macOS it falls back to restarting agents.
- `open` for links.
- The mod manager runs `gh` and `git` to search, fetch and install community
  mods, then `herdr-app check`, and deletes only its own cache directories.
- Network: GitHub search in the mod manager, and `127.0.0.1` for the
  herdr-browser helper (`omarchy-notes`, `omarchy-pane`). The graph's
  upstream release check is disabled in code (`CHECK = false`).
- `omarchy-themes` writes `appearance` into `settings.json`, which is the
  tracked `herdr/app/settings.json` through its symlink. Expect a diff after
  you pick a light or dark theme.

## macOS caveats

- The recipe was written for Linux and GNOME. `super-*` keys depend on how
  Herdr maps Super on macOS.
- macOS reserves Ctrl+arrows for Mission Control by default, so the OS may
  take them before Herdr sees them.

## Sources

- `herdr/app/omarchy/RECIPE.md`, `README.md`, `DEVELOPMENT.md`
- Install and screenshots on this machine, 2026-11-09
