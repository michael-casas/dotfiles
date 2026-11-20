# Envi theme hub

`theme.json` is the shared palette and semantic-token registry. This round wires
only the T3 thread TUI and its Neovim float. It does **not** change the editor's
colorscheme, terminal ANSI palette, or any other application's configuration.

**Nord is the default** (`active: "nord"`), by the user's alignment decision:
the main Neovim, herdr-app, Claude Code `custom:nordic`, and pi `nordic` already
use that family. Gruvbox dark remains the second theme, available by explicit
selection. The lead separately switched envi's colorscheme to Nordic; this lane
does not edit its colorscheme configuration.

## Schema

```json
{
  "active": "nord",
  "themes": {
    "nord": {
      "label": "Nord (nordic)",
      "appearance": "dark",
      "palette": { "white0_reduce_blue": "#c0c8d8" },
      "ansi": ["...16 #rrggbb colours in terminal index order..."],
      "tokens": {
        "ui": { "fg": "white0_reduce_blue" },
        "status": {},
        "chat": {},
        "diff": {},
        "syntax": {}
      },
      "consumers": { "nvim": { "scheme": "nordic", "background": "dark" } }
    }
  }
}
```

This is a structural illustration; `theme.json` contains the complete required
token sets. `active` names an entry in `themes`. Each entry has a human-readable
`label`, `appearance` (`dark` or `light`), named `palette`, exactly 16 literal
hex `ansi` entries, five token groups, and consumer metadata. `consumers.nvim`
records `scheme` and `background` (with optional plugin-specific `opts`, such as
Gruvbox's hard contrast); it does not load that colorscheme in this round.

Token values are either a palette name or a six-digit `#rrggbb` literal
(case-insensitive). Palette entries are literal hex, not aliases: there is no
recursive expansion. Every theme must expose the same token keys. `ui.bg` is
the editor backdrop; the TUI's flat `bg` intentionally maps to `ui.popover`,
not `ui.bg`.

## Tokens

| Flat TUI name | Hub key | Meaning |
| --- | --- | --- |
| — | `ui.bg` | Editor backdrop; metadata only this round |
| `bg` | `ui.popover` | Float background, painted by Neovim, not Ink |
| `fg` | `ui.fg` | Content and heading foreground |
| `fg_dim` | `ui.fg_dim` | Expanded command output |
| `muted` | `ui.muted` | Chrome, breadcrumb project, row labels, placeholder |
| `faint` | `ui.faint` | Timestamps and quiet hints |
| `border` | `ui.border` | Rules and float frame |
| `surface` | `ui.surface` | Composer card background |
| `accent` | `ui.accent` | Focus, send block background |
| `accent_fg` | `ui.accent_fg` | Text on an accent block |
| `link` | `ui.link` | Underlined links |
| `title` | `ui.title` | Quiet, bold Neovim float title |
| `info` | `status.info` | Working/live state |
| `success` | `status.success` | Completed state |
| `warning` | `status.warning` | Approval, high context usage |
| `error` | `status.error` | Failure, stop, exit code, critical context usage |
| `attention` | `status.attention` | Input requested |
| `user_bubble` | `chat.user_bubble` | User message and agent chip background |
| `code_bg` | `chat.code_bg` | Inline code and fenced code background |
| `provider` | `chat.provider` | Provider glyph |
| `diff_add` | `diff.add_fg` | Added text/count foreground |
| `diff_del` | `diff.del_fg` | Deleted text/count foreground |
| `syn_keyword` | `syntax.keyword` | Shell program/keyword |
| `syn_flag` | `syntax.flag` | Shell flags |
| `syn_string` | `syntax.string` | Quoted strings |
| `syn_number` | `syntax.number` | Numbers |

Gruvbox uses the binding redesign values: editor `#1d2021`, popover `#282828`,
composer/code `#3c3836`, bubble/frame `#504945`. Nord uses the installed Nordic
palette: editor `gray0` `#242933`, popover `gray1` `#2e3440`, composer/code `gray2`
`#3b4252`, bubble/frame `gray3` `#434c5e`. These lifted surfaces are intentional;
the old audit sketch is not the final Gruvbox token contract.

### Nordic palette provenance and contrast

Native Nord palette entries were verified read-only against
`~/.local/share/nvim/lazy/nordic.nvim/lua/nordic/colors/nordic.lua`. Names follow
that file, with nested variants flattened (`red.base` → `red`, `red.bright` →
`red_bright`). All native variants, including the ANSI bright variants, are
named palette entries; tokens reference names rather than embedded literals.
The `ansi` array retains the hub schema's 16 literal hex entries, drawn from
those named entries.

With `reduced_blue = true`, foreground is `white0_reduce_blue` `#c0c8d8`.
Expanded output uses the semantic `fg_dim` mix below: native `white0_normal`
`#bbc3d4` was too close to foreground to distinguish output from answer text in
the real popover. With transparency off and `swap_backgrounds = false`, the
editor backdrop is `gray0`. These options are recorded in `consumers.nvim.opts`
as metadata.

Three explicitly semantic extensions are not native Nordic colours:

- `fg_dim` `#aab2c1` is **85% foreground `#c0c8d8` + 15% popover `#2e3440`**,
  mixed in encoded sRGB with each channel rounded to the nearest integer.
  Gruvbox retains `fg3` `#bdae93`: it is already darker in every channel than
  its equivalent 85% foreground `#ebdbb2` + 15% popover `#282828` mix `#cec09d`.
- `muted` `#9aa3b5` is the binding chrome/title colour retained from the redesign
  contract; it is not claimed to occur in the installed plugin palette.
- `faint` `#6e7f96` is **85% `gray5` `#60728a` + 15% `white0_reduce_blue`
  `#c0c8d8`**, mixed in encoded sRGB with each channel rounded to the nearest
  integer. Native `gray5` against popover `gray1` measures **2.5403:1**, below
  the required 3:1. The mix measures **3.0565:1** against that popover.

Ratios use WCAG relative luminance: linearize each normalized sRGB channel
(`c / 12.92` for `c <= 0.04045`, otherwise `((c + 0.055) / 1.055)^2.4`), weight
by `0.2126 / 0.7152 / 0.0722`, then `(lighter + 0.05) / (darker + 0.05)`.
Tests fix the native palette snapshot, token roles, minimum faint contrast,
and output dimming of at least 15% toward the popover for both themes.

## Runtime readers

### T3 TUI

`nvim/tools/t3-thread/theme.mjs` exports:

```js
export const TOKEN_NAMES; // frozen array of the flat names above
export function loadTheme(opts); // { id, source: "hub" | "ansi", tokens }
export function watchTheme(onChange, opts); // returns an idempotent stop()
```

The optional `opts` object accepts `file` and `id` for both functions. File
precedence is `opts.file`, `ENVI_THEME_FILE`, then this repository's
`theme/theme.json`, located relative to the **real** module path (so symlinked
profiles work). Relative file overrides resolve against the caller's cwd.
Theme precedence is `opts.id`, `ENVI_THEME`, then the hub's `active`.

`loadTheme` is synchronous and never throws. It resolves every required flat
token, and validates the remaining token values of the selected theme. A missing
or unreadable file, invalid JSON, unknown theme, missing required token,
unresolved palette reference, or invalid hex gives a whole-theme ANSI fallback
(`id: "ansi"`, `source: "ansi"`), never a mixture of themes. Invalid unused themes
do not prevent loading a valid selected theme. This small reader is not a full
metadata/schema validator.

ANSI text inherits the terminal default (`fg` is an own key with value
`undefined`); muted, faint, title, and dim output use `white` (ANSI 7), while
only the border uses `gray` (ANSI 8). On Nord, ANSI 8 is `#3b4252`, too close
to popover `#2e3440` for readable labels. Semantic colours use bright ANSI names. `bg`, `surface`, `user_bubble`, and `code_bg` are
`null`. Consumers omit those backgrounds; the composer uses an outlined border
instead of a filled surface. The hub's `ansi` array documents the theme palette;
this module does not set the terminal palette.

The watcher observes the **parent directory**, filters to the hub filename,
debounces 100 ms, then calls `onChange(loadTheme(...))`. Atomic replacement,
deletion (ANSI), and recreation (hub) all work while the directory remains.
Call `loadTheme` for the initial render: watching has no initial callback.
`stop()` cancels pending notifications and closes the watcher. Both watcher and
debounce timer are unreferenced and cannot retain the Node process. If the
parent directory itself is unavailable, watching is a safe no-op; start a new
watch after restoring that directory.

### Neovim T3 float

`nvim/lua/hcmux/t3.lua` locates the hub relative to its real source file, or uses
`vim.env.ENVI_THEME_FILE`; `vim.env.ENVI_THEME` overrides `active`. It reads with
`vim.json.decode` when the float opens/reopens, defining:

- `EnviT3Normal`: `ui.fg` on `ui.popover`;
- `EnviT3Border`: `ui.border` on `ui.popover`;
- `EnviT3Title`: bold `ui.title` on `ui.popover`.

After the window exists, the float's `winhl` maps `NormalFloat` and `Normal` to
`EnviT3Normal`, `FloatBorder` to `EnviT3Border`, and `FloatTitle` to `EnviT3Title`.
The centered `" T3 "` title, toggle/hide behavior, and terminal names/labels
stay unchanged. A `ColorScheme` autocmd redefines these groups. A missing or
invalid hub makes no highlight or `winhl` changes; a never-themed float keeps
its normal look. Neovim may retain prior window options when reattaching an
already-themed terminal buffer. This reader does not watch the hub: reopen the
float to pick up valid edits. It does not alter `Normal`, the editor scheme,
OSC replies, or other floats.

Nord loads by default. To try Gruvbox without changing the hub, start Neovim or
the standalone TUI with `ENVI_THEME=gruvbox-dark`. To change the default for both readers, change `active` and
reopen the float; a running TUI watches and repaints. `ENVI_THEME_FILE` can point
both readers to a temporary copy for safe experiments.

## Adding a theme

1. Copy an existing entry under a new unique id, preserving all token keys.
2. Set label, appearance, literal palette, and all 16 ANSI entries.
3. Map each role to the new palette or literal hex; keep the backdrop → popover
   → composer → bubble surface steps readable.
4. Record `consumers.nvim.scheme` and `.background` (and any plugin options).
   Installing/loading that plugin is separate from defining a hub theme.
5. Run the checks below, load the id explicitly, and inspect both the TUI and
   float. Only then change `active` if it should become the default.

```sh
cd nvim/tools/t3-thread
node --check theme.mjs
node --test test/theme.test.mjs
```

## Other consumers

The paths below describe **future integration targets**, not generated artifacts
or live config changes made here. Runtime readers may eventually use resolved
`~/.local/state/envi/theme/current.json`; format-specific consumers need a
builder/publication step. No such builder is implemented this round.

- **Envi/main Neovim colorscheme — runtime read.** Target
  `nvim/lua/plugins/colorscheme.lua` in each checkout, using hub
  `consumers.nvim` (or resolved `current.json`) with optional highlight overrides.
  The colorscheme plugin retains its palette. The lead separately selected
  Nordic; automatic hub-driven scheme selection remains future work.
- **herdr-app — generated file.** Target
  `~/.config/herdr-app/themes/envi.json` in its `{background, foreground,
  selection, cursor, ansi, colors}` format. Opt in once with `theme: "envi"`
  in `~/.config/herdr-app/settings.json` (repo source `herdr/app/settings.json`).
- **Claude Code — generated/published file.** Target
  `~/.claude/themes/envi.json`, `{name, base, overrides}`; participating sessions
  select `custom:envi`. Preserve hand-tuned per-theme overrides rather than
  reducing their fidelity to an automatic palette translation.
- **pi — generated/published file.** Target `~/.pi/agent/themes/envi.json`,
  `{name, vars, colors, export}`; participating sessions select `envi`.
  Its strict token contract and hand-tuned overrides remain authoritative.
- **Ghostty — generated include.** Target
  `~/.local/state/envi/theme/ghostty.conf`; reference with `config-file` from
  `ghostty/config`, replacing the inline palette. Reload is required.
- **Starship — generated whole file.** Target
  `~/.local/state/envi/theme/starship.toml`, rendered from the existing
  `starship/starship.toml` template, selected via `STARSHIP_CONFIG`. Starship
  has neither a JSON reader nor palette includes.
- **herdr TUI multiplexer — generated block.** Target `[theme.custom]` in
  `herdr/config.toml` (installed `~/.config/herdr/config.toml`), using a template
  and scoped splice rather than replacing unrelated configuration.

## Relation to theme design v5

Design v5 (`~/.local/share/envi-design/theme/design.md`) remains the design for
coordinated publication; it is **not implemented by this lane**.

- **Replaced: the registry.** Hub `themes.<id>.{label, appearance,
  consumers.nvim}` replaces the proposed `nvim/lua/envi/theme/registry.lua`.
  Keep one theme list, not two competing registries.
- **Retained: state and operations.** v5's committed/pending state file,
  `select` / `apply_local` / `finalize`, sequence ordering, cancellation rules,
  repair and opt-in/off stay. The hub's `active` is the fresh-machine default,
  not a replacement for committed state. The proposed state path is
  `~/.local/state/envi/theme.json`; a future integration should distinguish it
  clearly (e.g. `theme-state.json`) from this tracked hub.
- **Retained: lock.** The same Neovim writer holds the advisory flock while
  writing outputs and committed state; readers never follow pending selection.
- **Retained/extended: publication.** Stable output names (`custom:envi`, pi
  `envi`) and temp-file + rename publication remain. Future generated outputs
  join that locked transaction with checksums. Hand-tuned Claude/pi assets can
  live in `theme/overrides/<id>/`; generation must not silently replace them.
- **Retained: followers.** v5's state-directory watchers, 100 ms debounce,
  sequence filtering, and picker deferral still govern coordinated switching.
  The TUI's direct hub-directory watcher is the limited mechanism for this round,
  not an implementation of those committed-state followers.
- **Retained/extended: validation.** v5's pi contract, Claude key set and scheme
  availability checks remain required before publication/repair. A future hub
  builder adds metadata/schema validation and validates generated outputs.

Nothing outside the T3 TUI and its float is wired this round. In particular,
there are no settings edits, generated consumer files, scheme switches, global
theme state writes, or cross-process publication changes.
