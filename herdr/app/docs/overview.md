# Overview: what the Herdr app is and where things live

Read this first. It explains the moving parts, which file is the source of
truth, and which files an agent may edit.

## Three different programs

| Program | Binary | What it is | Config |
|---|---|---|---|
| **Herdr app** (this doc set) | `herdr-app` | Native desktop window (macOS, Linux, Windows). Draws spaces, tabs, panes and panels with GPUI. | `~/.config/herdr-app/` |
| **herdr-core** | `hc` | Headless runtime that owns every terminal and agent. Keeps them alive when the window closes or updates. | `~/.config/herdr-core/config.toml` |
| **herdr TUI** (legacy) | `herdr` | The older terminal multiplexer. Separate product with its own docs at `herdr.dev/tui/docs`. | `~/.config/herdr/config.toml` → `herdr/config.toml` in this repo |

Rules that follow from this:

- Default to `hc` (herdr-core) for running, reading and coordinating
  terminals and agents. Use `herdr-app` only to drive the window.
- Do not apply `herdr.dev/tui/docs` or the `herdr` CLI to the desktop app.
  Its config keys, plugins and keybindings do not carry over.
- The app is one client of herdr-core. Closing or updating the app never
  kills terminals.

## The app home

`~/.config/herdr-app/` is the app's whole interface as files. The app
redraws itself from these files while it runs, usually within a second.

- `XDG_CONFIG_HOME` changes the config root.
- `HERDR_APP_HOME` picks an app home directly and wins over everything. It
  also selects which running window `herdr-app status` and `herdr-app shot`
  talk to.

### Who owns each file

| Path | Owner | Edit it? |
|---|---|---|
| `settings.json` | you | yes: fonts, theme, zoom, sounds, telemetry |
| `keys.json` | you (once edited) | yes, see [keys.md](keys.md) |
| `programs.json` | you | yes: program names, icons, launchers |
| `layouts/<your-name>.json` | you | yes |
| `mods/<your-name>/` | you | yes |
| `themes/<your-name>.json` | you | yes |
| `layouts/{main,terminals,win98}.json` | Herdr | **no**: replaced on start; edits are moved to `<name>-edited` |
| `mods/<shipped>/` (listed in `installed.json`) | Herdr | **no**: clone first |
| `frame/`, `icons/` | Herdr | no: rewritten on every start |
| `AGENTS.md`, `herdr.d.ts`, `gpui-kit.d.ts` | Herdr | no: rewritten on every start |
| `layouts/.state/` | Herdr (records your clicks) | no |
| `shared.json`, `data/`, `seen.json`, `installed.json`, `view.json`, `window*.json` | Herdr state | no |
| `telemetry/`, `update-notes*` | Herdr | no |
| `herdr-app.sock` | Herdr control socket | no; access to it means control of the window |

To find out whether a mod or layout is shipped, check the keys in
`installed.json`. Shipped layouts appear there as `layout:<name>`.

## Spaces, tabs, panes, agents

- **Space:** a place to work on one machine. Structure (spaces, tabs,
  splits) lives in each machine's herdr-core document, not in a file. Change
  it with commands; there is no `spaces.json`.
- **Tab:** one piece of work in a space, with its terminals and splits.
- **Pane:** a terminal on screen, or a mod placed beside terminals.
- **Agent:** a terminal whose program reports status over OSC 7501. Status
  is one of `working`, `blocked`, `idle` or `done`. A space or tab shows its
  most urgent agent: blocked > done > working > idle.
- **Sub-agent:** a terminal an agent started with `hc run`. It belongs to
  its parent's tab without a pane of its own.

## Sources of truth, in order

1. The installed `~/.config/herdr-app/AGENTS.md`, `herdr.d.ts` and
   `gpui-kit.d.ts`. These match the installed version exactly.
2. `herdr-app commands` and `herdr-app --skill`. Run them; they do not
   need an open window.
3. Upstream: `github.com/herdrdev/herdr-app` (`defaults/AGENTS.md`,
   `docs/`), and `herdr.dev/guide`.
4. These docs: a summary for this dotfiles repo. When they disagree with
   (1), (1) wins. Update the doc.

## Security

A mod is trusted JavaScript with your full access. It can run programs, read
files, use the network and reach connected machines. No prompt appears for
each action. Treat a mod like a shell script: read it before you install it.
Layouts can load mods, so check the mods a layout references too.

Telemetry is on by default. It sends daily counts with no terminal content,
paths or custom mod names. Turn it off with `"telemetry": false` in
`settings.json`, or for one run with `DO_NOT_TRACK=1` or
`HERDR_TELEMETRY=0`.

## Sources

- `~/.config/herdr-app/AGENTS.md` (herdr-app 0.1.14): "Two programs", "The files", "The model"
- https://herdr.dev/guide, https://herdr.dev/core
- https://github.com/herdrdev/herdr-app/blob/master/docs/security.md
- Verified on this machine 2026-11-09
