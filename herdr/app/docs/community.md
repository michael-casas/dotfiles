# Community layouts and mods: installing and publishing

`herdr.dev/gallery` lists layouts (`herdr.dev/layouts/<owner>/<name>`) and
mods (`herdr.dev/mods/<owner>/<name>`). Each entry is a public GitHub folder
laid out like the app home, with a `RECIPE.md` and a `preview.png`.

## Installing one

The person's request usually looks like:
`Read ~/.config/herdr-app/AGENTS.md, then add this mod: herdr.dev/mods/<owner>/<name>`.

1. **Read the recipe and every file before writing anything.** Tell the
   person if the mod reaches the network, runs programs (`exec`, `hc`) or
   reads files outside its own folder. Mods run with full user access (see
   [overview.md](overview.md#security)).
2. Copy the layout file into `layouts/` and each mod folder into `mods/`.
   Leave out `RECIPE.md` and `preview.png`. **Never overwrite.** If a name
   is taken, rename the new item: its file or folder, the `mod` names in
   the layout, and the mod's own `mods/<name>/` asset paths.
3. Adapt it only where its assumptions don't hold, or where the person
   asks. If the files don't work on this version, rebuild from the recipe.
4. **Merge** the mod's `keys.json` into the person's file, and ask before
   replacing a key already in use.
5. Run `herdr-app check` on each mod. For a layout, run
   `layout.switch {name}`. The person's own layout stays as it was;
   `ctrl-shift-l` switches back.

In this repo, track the installed files under `herdr/app/` and symlink them
(see [dotfiles-wiring.md](dotfiles-wiring.md)). Keep a note of the upstream
URL in the commit message.

## Publishing one

1. Put the folder in a public GitHub repo, one folder per layout or mod.
2. Write a `RECIPE.md` (format below) and save a screenshot as
   `preview.png`.
3. Add the repo topic `herdr-layout` or `herdr-mod`. It appears on the
   gallery within the hour.

### `RECIPE.md` format

The recipe is a brief: from an empty folder, another agent must be able to
build the item from it. Write it from the real files, in this order:

1. `# Name`, one paragraph of what the person sees, then
   `![Name](preview.png)`
2. **What you see:** the regions, their sizes, colors and type, and what
   each one shows
3. **How it behaves:** how each agent status (working, blocked, done, idle)
   looks; what clicks, keys and hovers do; what moves
4. **Built from:** the node tree and blocks, each mod and its `props`
   roles, the shipped mods it uses, the `herdr` functions and commands, any
   programs it runs, its art
5. **Watch out:** pitfalls, limits, controls that do nothing yet, and
   assumptions about the setup
6. **Done when:** checks that prove a build works

Be exact (`#ab7748`, 29px, `agent.focus`), and describe nothing the build
doesn't do. Code belongs only in Built from and Watch out.

## Reference recipes

- `herdr.dev/mods/herdrdev/tmux-prefix`: a popup-only mod
  (`place: "none"`) with a merged `keys.json`, a `mod:` key section,
  `nextCommand()`, `hc keys` and `cx.timer.after` with a generation
  counter.
- `herdr.dev/layouts/herdrdev/pasture`: a full layout in which one mod
  plays three roles through `props().role`. It uses `.transition` and
  `.loop` for motion and calls `setAgentOrder` on render.

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "Layouts and mods other people made"
- https://herdr.dev/gallery, https://herdr.dev/guide
- https://herdr.dev/mods/herdrdev/tmux-prefix, https://herdr.dev/layouts/herdrdev/pasture
