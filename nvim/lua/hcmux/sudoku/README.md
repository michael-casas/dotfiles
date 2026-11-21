# hcmux.sudoku: the Sudoku popover

`:EnviSudoku [new [<puzzle>]]` opens a centred, focused popover with a 9x9 board.
The contract (Gherkin features, the `state()` API and the `classic` fixture) lives
in `~/.local/share/envi-design/sudoku/features/`. This is the WP1 shell: window,
model, rendering, timer and `state()`. Motions, search, editing and saving
(WP2–WP5) plug into the seams below **without editing the core files**.

| File | What it owns |
|---|---|
| `init.lua` | `:EnviSudoku`, the window (zindex 60 or above the Snacks windows it overlaps, centred, recentred on resize, `winfixbuf`, never scrolled), `:q` via `config.panel-close` (pause, close, focus back to the invoker), the hidden caret, the timer tick, `state()`, events |
| `game.lua` | the model `{ puzzle, board, givens, cursor, mode, timer }` and the timer (`resume`/`pause`/`stop`, injectable clock) |
| `puzzles.lua` | the bundled puzzles; `classic` is the fixture. `test/00-puzzles.lua` proves each has one solution |
| `keys.lua` | the key registration table |
| `render.lua` | board text, highlight groups, highlight layers, footer segments |
| `test/` | the headless harness (`run.sh`, `harness.lua`) and one suite per feature file |

## Behaviour (WP1)

- **The cursor is the outlined cell.** Neovim's cursor sits on the selected digit
  and `guicursor` hides it (`EnviSudokuCaret`, `blend=100`) while the board has
  focus; the command line keeps its caret. Native motions snap back to the cell.
- **Keys the board consumes** (no-ops until a later WP registers a handler):
  edit and mode keys (`i a o s c d x r p u . v V <C-v>` …), `<Esc>` (never closes),
  `<C-h/j/k/l>` (never move focus to a split under the board, REC F2) and `H`/`L`
  (LazyVim's buffer switch). Every board map has a `desc` starting `Sudoku: `.
- **Focus leaving by other means** (a click, `<C-w>p`): the board stays visible,
  lualine stops reading `SUDOKU`, and `:EnviSudoku` focuses it again on the same
  cell. The timer keeps running (pausing on WinLeave is WP5's).
- **`:q`, `:qu`, `:quit`, `:q!`** go through panel-close's `EnviClose` router:
  pause, close, focus back to the invoking window. The puzzle stays in memory;
  `:EnviSudoku` reopens it with the timer resuming. Closing the window any other
  way also pauses. The invoker is the window current when the board window was
  created; refocusing an open board from elsewhere doesn't change it. If it no
  longer exists, Neovim picks the next window as usual.
- **Z-order:** the board opens at zindex 60, or one above every Snacks window it
  overlaps (as Snacks stacks its own), and is raised again whenever `:EnviSudoku`
  refocuses it, e.g. under a picker opened since. It stays below 100, where
  Neovim's popupmenu, messages and command line live. `state().zindex` is the
  window's real zindex.
- **Viewport:** the board is centred in the rows between the tabline and the
  statusline/command line. The full layout needs a 41x23 viewport (content 39x21
  plus the border); below that the **compact** layout (box rules only, one line
  per row, footer fields one space apart, the cursor drawn as `[5]` brackets in
  `EnviSudokuCursor`) needs **36 columns x 17 usable rows**, e.g. a 36x21 Neovim
  with a one-line command line and statusline. That is the minimum supported
  viewport; anything smaller clamps the window to the screen and clips the
  board's right and bottom until the viewport grows again.
- **The board never scrolls:** scroll keys (`<C-e> <C-y> <C-d> <C-u> <C-f> <C-b>`,
  `zt`/`zz`/`zb` …, `<PageUp>`/`<PageDown>`, the mouse wheel) are consumed, and a
  scroll that bypasses them (the wheel over the unfocused float) is undone.
- **Resizes:** Snacks rebuilds its layouts on `VimResized` and moves focus with
  `noautocmd`. If the board had focus, it takes focus back after that transition,
  unless a real focus change (to any window, Snacks' explorer included) happened
  in between or the board closed.

## Seams for WP2–WP5

All of these are public on the modules above. Put a work package's code in
`lua/hcmux/sudoku/ext/<name>.lua` (e.g. `ext/motions.lua`) and register there at
module load: the core requires every `ext/*.lua` once, in name order, right after
it loads, so no core file changes. An extension may `require("hcmux.sudoku")`.

### Keys: `require("hcmux.sudoku.keys").register(spec)`

```lua
keys.register({
  lhs = "j", mode = "normal",            -- "normal" | "insert" | "search" | "*" (fallback)
  desc = "Sudoku: down [count] cells",   -- required, must start "Sudoku: "
  fn = function(game, ctx)               -- ctx = { lhs, count = v:count, count1 = v:count1 }
    game.cursor.r = math.min(9, game.cursor.r + ctx.count1)
  end,
})
```

- The handler for the current `game.mode` runs, else the `"*"` one. After it
  returns, the board re-renders (and re-installs keys if `game.mode` changed).
- The buffer only carries maps for keys with a handler **in the current game
  mode**. Digits registered for `"insert"` or `"search"` therefore don't exist in
  board NORMAL, where Neovim keeps reading them as counts (`3j`).
- To take over a consumed key (`i`, `p`, `u`, `<Esc>` …), register it for your
  mode; the core's `"*"` no-op stays the fallback for the other modes.
- `keys.handler(lhs, mode)` returns the spec that would run (`spec.mode == "*"`
  means only the core's fallback).

### Highlights: `require("hcmux.sudoku.render").layer(spec)`

```lua
render.layer({
  name = "search-match", group = "EnviSudokuMatch", priority = 130,
  cells = function(game) return { { r = 2, c = 5 }, … } end,  -- recomputed on every render
  outline = false,  -- true: style the cell's border (as the cursor does), not its digit
})
```

- Built in: `given` and `entry` (100), `cursor` (200, outline). Suggested
  priorities: dim 110 < guide 120 < match 130 < conflict 140 < draft 150 <
  cursor 200. Higher wins where they overlap.
- Several layers may share a group (dim from search, insert and pause);
  `state().hl.{cursor,match,guide,dim}` is the union of their cells, row-major.
- The groups (`EnviSudokuGiven Entry Draft Cursor Match Guide Dim Conflict`) are
  defined in `render.define_hl()` with `default = true`. `EnviSudokuDim` is
  foreground-only; the window's `winblend` stays 0.
- `render.span(r, c)` and `render.outline(r, c)` give the extmark positions of a
  cell's digit and border (namespace `render.ns`) in the current layout
  (`render.layout()`: `"full"` or `"compact"`; a compact outline span carries the
  bracket glyph as a fourth element). Always ask them; don't hard-code offsets.

### Footer: `render.footer_segment(fn)`

`fn(game) -> string|nil` is appended after `MODE  R<r>C<c>  MM:SS STATUS`, two
spaces apart (WP3: `/9 4/9`).

### Model and state

- `sudoku.game()` is the live, mutable model; call `sudoku.refresh()` after a
  change made outside a key handler. `sudoku.set_game(g)` replaces it (WP5's load).
- `game.timer:pause()`, `:resume()`, `:stop()` (SOLVED), `:elapsed()`; set
  `game.mode` to switch the footer label and key set.
- `sudoku.extend_state(function(state, game) state.undo = … end)` fills the
  fields WP1 leaves at their defaults: `search = nil`, `draft = nil`,
  `undo = redo = 0`, `conflicts = {}`.

### Events: `sudoku.on(event, fn)` → unsubscribe

`load` (`:EnviSudoku` with no puzzle in memory: call `set_game` to resume a save,
else a random puzzle starts), `new`, `open`, `render`, `close`. Each gets `game`.

`before_new` runs when `:EnviSudoku new [<puzzle>]` is asked for, **before** the
model, timer, window or focus change: `fn(ctx)` with `ctx = { puzzle, requested,
game, confirmed }` (`puzzle` is the one that would load, `requested` the argument
or nil for a random one, `game` the current game or nil). Returning `false`
declines and nothing happens. For an asynchronous confirmation (Q19, WP5):
decline, ask, then call `sudoku.open({ new = true, puzzle = ctx.puzzle, confirmed = true })`;
your hook sees `ctx.confirmed` and lets it through.
WP5's `:w`/`:wq` routing extends `config.panel-close` and is scoped to buffers
that own the new commands; `sudoku.state().save_path` is the slot path.

## Tests

```sh
nvim/lua/hcmux/sudoku/test/run.sh                # every suite
nvim/lua/hcmux/sudoku/test/run.sh 10-escape      # one suite
```

Each suite is a fresh `nvim --headless -u NONE` with isolated XDG homes, the
worktree config, Snacks, LazyVim's keymaps and the `:q` router. A scenario:

```lua
local H = require("hcmux.sudoku.test.harness")
H.boot()
H.scenario("title from the .feature", function()
  H.background()               -- layout + :EnviSudoku new classic, focused at R1C1
  H.type(":q<CR>")             -- nvim_feedkeys(keys, "mtx"), one typed command per call
  H.advance(2000)              -- the injected clock
  H.eq(H.state().timer, { status = "paused", elapsed_ms = 0 })
end)
H.finish()
```

`H.place`/`H.enter` set up a Given on the model; `H.groups(r, c)`, `H.spans(group)`
and `H.footer()` read what is drawn.
