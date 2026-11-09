# herdr/app: Herdr desktop app config

Personal config for the **Herdr app** (`herdr-app`, the native desktop
window). Its home is `~/.config/herdr-app/`. The files here are symlinked
into that home one at a time.

This is not the legacy `herdr` TUI. That one is configured by
`../config.toml`. Terminals and agents run in **herdr-core** (`hc`), which
is the default tool for driving them.

## Tracked files

| File | Purpose |
|---|---|
| `settings.json` | Cascadia Code NF for terminals and UI, size 14, `nordic` theme, zoom, sounds |
| `themes/nordic.json` | Nordic palette, matching `ghostty/config` and nvim `nordic.nvim` |
| `layouts/tui.json` | `main` reworked to feel like a TUI: square corners, no padding, 1px borders, slimmer bars |
| `layouts/tui.svg` | Preview shown in Settings → Look |
| `omarchy/` | Submodule: private fork `michael-casas/herdr-omarchy` of the Omarchy layout (mods, themes, wallpapers) |
| `omarchy-sync.sh` | Installs `omarchy/` into the app home: copies mods, symlinks themes, layout and wallpapers |

## Rules for agents

1. Read the installed `~/.config/herdr-app/AGENTS.md`, `herdr.d.ts` and
   `gpui-kit.d.ts` before changing anything. They match the installed
   version and win over these docs.
2. Only track files you own. Never copy, edit or symlink shipped layouts,
   mods, `frame/`, `icons/`, generated docs or app state.
3. To change a shipped layout or mod, clone it first
   (`layout.clone` / `mod.clone`), then track the clone.
4. Verify every change: no `.error` files, `herdr-app status` errors empty,
   `herdr-app check` for mods, and a screenshot.
5. Use `hc` for terminals and agents, and `herdr-app` for the window.

## Docs

| Topic | Read when |
|---|---|
| [overview.md](docs/overview.md) | First. App vs herdr-core vs legacy TUI, the app home, file ownership, sources of truth, security |
| [dotfiles-wiring.md](docs/dotfiles-wiring.md) | Adding, linking or installing files from this repo; worktree preview and return |
| [look-and-theming.md](docs/look-and-theming.md) | Fonts, themes, colors, settings precedence, the Nordic/Cascadia setup, known gaps |
| [layouts.md](docs/layouts.md) | Changing the window's structure: node tree, pane frames, floating blocks, cloning, `tui.json` |
| [keys.md](docs/keys.md) | Rebinding keys and merging a mod's `keys.json` |
| [commands.md](docs/commands.md) | The `herdr-app` CLI and the command list (`herdr-app do …`) |
| [mods.md](docs/mods.md) | Writing or cloning panels: the gpui-shell runtime, rules, the `herdr` API, patterns, definition of done |
| [herdr-core.md](docs/herdr-core.md) | Running agents and terminals with `hc`, labels, OSC 7501 status, adopting terminals into spaces |
| [omarchy.md](docs/omarchy.md) | The Omarchy layout: private fork, submodule, sync script, fork changes, keys, what it runs, updating from upstream |
| [community.md](docs/community.md) | Installing gallery layouts and mods safely; publishing with `RECIPE.md` |
| [verification.md](docs/verification.md) | Checking a change: error files, status, `check`, screenshots (`herdr-app shot`, cua-driver), recovery |

Docs written against herdr-app 0.1.14 (2026-11-09). If the installed
version differs, read the installed `AGENTS.md` first.
