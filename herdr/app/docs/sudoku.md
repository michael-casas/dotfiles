# Sudoku

A keyboard-and-mouse Sudoku dialog with uniquely solvable puzzles, pencil
notes, undo, scoring and saved progress. The roughly 700 × 860 dialog
uses larger cells and digits. `ctrl-space` then `s` toggles it; Esc also hides
it. Hiding never ends the game: reopen to continue the same board.

## Difficulties

Mistakes are **permitted**, not lives remaining. A wrong digit counts a
mistake but is not kept on the board.

| Difficulty | Permitted mistakes | Lose on | Clues |
|---|---|---|---|
| Easy | 5 | 6th mistake | 38–42 |
| Normal | 3 | 4th mistake | 30–34 |
| Hard | 1 | 2nd mistake | 24–28 |

## Screens

- **New game?** Choose Easy, Normal or Hard. A saved playing game opens
  directly on the board instead. Each difficulty shows its best score and
  best time (or “—” before a win).
- **Board:** difficulty, mistakes, score, elapsed time, the 9×9 grid and a number
  pad with counts still to place. Notes are pencil marks; givens cannot
  be erased. `+` opens the new-game chooser; Back / Esc returns to the
  current board without replacing it.
- **Lost:** “Out of mistakes”; Restart this puzzle (`r`) keeps the same
  puzzle and resets progress, notes, mistakes, score, undo history and time, or `+` chooses a
  new game.
- **Won:** score, time, time bonus and best score / best time for that
  difficulty; “New best!” marks an improvement. Choose a new game with `+`.

## Controls

| Input | Does |
|---|---|
| `ctrl-space` `s` | Toggle the dialog |
| Esc | Hide the dialog (from the new-game chooser with an active game, return to its board) |
| Arrows / `h j k l` | Move selection, wrapping at the edges |
| `1`–`9` | Place a digit, or toggle its pencil note in notes mode |
| `0`, Backspace, Delete | Erase an entered digit and its notes |
| `u`, `cmd-z`, `ctrl-z` / Undo button | Undo the last successful edit; mistakes are not refunded |
| `n` | Toggle notes mode |
| `+` | Choose a new game |
| `r` while lost | Restart the same puzzle |
| `1` / `2` / `3` or `e` / `n` / `h` in the chooser | Start Easy / Normal / Hard |
| Arrows + Enter in the chooser | Select and start a difficulty |
| Click a cell / pad digit / button | Select / enter / activate |

Elapsed time grows only while the dialog is open and the game is playing.

## Undo, scoring and bests

Undo replaces the Erase button; `0`, Backspace and Delete still erase.
Up to 200 successful placements, erasures and note changes can be undone
while playing, restoring affected notes and the previous score. Mistakes
are never refunded. Undo is dimmed when unavailable.

| Difficulty | Correct digit | Speed streak | Par time |
|---|---|---|---|
| Easy | +10 | +20 | 8 minutes |
| Normal | +20 | +40 | 15 minutes |
| Hard | +40 | +80 | 25 minutes |

A correct digit within 10 seconds of elapsed play after the previous
correct entry earns double base points. A wrong digit subtracts the base
points, never below zero. A brief label near the cell shows the gain,
streak or penalty.

Winning adds `round(base × 20 × clamp(par time / elapsed time, 0.25, 2))`
as a time bonus. Results track played and won counts per difficulty;
wins also update the best score and fastest time. Losses count as played
but do not change bests.

## Saved state and reset

State lives at `~/.local/share/herdr-sudoku/state.json`, outside the mod
folder so `sync.sh` does not replace it. Changes are saved after moves,
notes, undo, new games and restarts, every 10 seconds of play, and on close.
The version-1 file contains both the game and per-difficulty stats; old
files without stats start with empty records. Saving either preserves the
other. Loads use the latest in-memory save without waiting on writes; a
new save bypasses a write stuck for more than three seconds.
Writes are serialized and atomic; a stale snapshot is re-read and retried
once, with the latest writer winning. Missing, broken or unsupported saves
open as no game; I/O failures are logged rather than thrown to the UI.

To reset the game **and all bests**, close the dialog, delete that state file, then reload the mod or
restart Herdr before reopening (a live copy may still hold the old game).

## Files

| File | What |
|---|---|
| `mods/sudoku/main.js` | Dialog, screens, input, timer and save calls |
| `mods/sudoku/mod.json` | Dialog registration and size |
| `mods/sudoku/game.js` | Puzzle generation, game rules, undo, scoring, results and validation |
| `mods/sudoku/store.js` | Versioned game/stats JSON, loading and serialized atomic saves |
| `mods/leader/main.js` | `ctrl-space` then `s` binding |
| `tests/sudoku-game.test.mjs` | Engine tests |
| `tests/sudoku-store.test.mjs` | State parsing and persistence tests with a Herdr stub |

Run the store tests from the repository root:

```sh
node --test herdr/app/tests/sudoku-store.test.mjs
```
