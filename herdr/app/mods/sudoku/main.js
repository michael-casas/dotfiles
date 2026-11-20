import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme, props, closeOverlay } from "herdr";
import { DIFFICULTIES, newGame, place, erase, toggleNote, restart, tick, isGiven, remaining, undo, canUndo, recordResult, emptyStats } from "./game.js";
import { loadGame, saveGame, loadStats, saveStats } from "./store.js";

const LEVELS = ["easy", "normal", "hard"];
const CELL = 60;
const timeLabel = (ms) => {
  const seconds = Math.floor(ms / 1000);
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
};

export default class Sudoku extends View {
  init(_props, cx) {
    this.game = null;
    this.stats = emptyStats();
    this.newBest = false;
    this.scoreFloater = null;
    this.floaterVersion = 0;
    this.screen = "loading";
    this.cursor = 0;
    this.notesMode = false;
    this.level = 1;
    this.flash = null;
    this.flashVersion = 0;
    this.closed = false;
    this.lastClock = Date.now();
    this.unsavedTime = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(50, () => this.handle.focus());
    this.beginLoading("loading", cx);
    cx.spawn(async (cx) => {
      const game = await loadGame();
      const stats = await loadStats();
      if (this.closed) return;
      this.loadingComplete = (cx) => {
        this.stats = stats;
        this.game = game;
        this.cursor = Number.isInteger(game?.cursor) && game.cursor >= 0 && game.cursor < 81 ? game.cursor : 0;
        this.notesMode = game?.notesMode === true;
        this.screen = game?.status === "playing" ? "board" : "new";
        this.lastClock = Date.now();
        cx.notify();
      };
    });
    cx.timer.every(1000, (cx) => {
      if (this.closed) return;
      this.advanceClock();
      if (this.unsavedTime >= 10000) this.persist(cx);
      if (this.screen === "board" && this.game?.status === "playing") cx.notify();
    });
  }

  beginLoading(screen, cx) {
    this.loadingTimer?.cancel();
    this.screen = screen;
    this.loadingStarted = Date.now();
    this.loadingStep = 0;
    this.loadingFrame = 0;
    this.loadingComplete = null;
    this.loadingTimer = cx.timer.every(40, (cx) => {
      if (this.closed || !["loading", "generating"].includes(this.screen)) {
        this.loadingTimer.cancel();
        this.loadingTimer = null;
        return;
      }
      // Show a full bar for one tick before leaving the loading screen.
      if (this.loadingStep === 20 && this.loadingComplete) {
        const complete = this.loadingComplete;
        this.loadingComplete = null;
        this.loadingTimer.cancel();
        this.loadingTimer = null;
        complete(cx);
        return;
      }
      const elapsed = Date.now() - this.loadingStarted;
      this.loadingFrame++;
      this.loadingStep = elapsed >= 600 && this.loadingComplete ? 20 : Math.min(19, Math.floor(elapsed / 32));
      cx.notify();
    });
    cx.notify();
  }

  loadingScreen(t) {
    const label = this.screen === "loading" ? "LOADING…" : "GENERATING…";
    const blink = Math.floor(this.loadingFrame / 8) % 2 === 0;
    return v_flex().flex_1().items_center().justify_center().gap(16)
      .child(div().text_size(13).font_semibold().text_color(t.accent).opacity(blink ? 1 : 0).child(label))
      .child(h_flex().p(6).gap(3).border(2).border_color(t.foreground).bg(t.background)
        .children(Array.from({ length: 20 }, (_, index) => div().w(12).h(12).flex_none()
          .bg(index < this.loadingStep ? t.accent : t.raised))))
      .child(div().text_size(12).text_color(t.muted).child(`${this.loadingStep * 5}%`));
  }

  advanceClock() {
    const now = Date.now();
    if (this.screen === "board" && this.game?.status === "playing") {
      const elapsed = Math.max(0, now - this.lastClock);
      this.game = tick(this.game, elapsed);
      this.unsavedTime += elapsed;
    }
    this.lastClock = now;
  }

  snapshot() {
    return this.game ? { ...this.game, cursor: this.cursor, notesMode: this.notesMode } : null;
  }

  persist(cx) {
    const game = this.snapshot();
    this.unsavedTime = 0;
    cx.spawn(async () => { await saveGame(game); });
  }

  async close() {
    this.advanceClock();
    this.closed = true;
    this.loadingTimer?.cancel();
    this.loadingTimer = null;
    if (this.game) await saveGame(this.snapshot());
  }

  select(index, cx) {
    this.handle.focus();
    if (this.screen !== "board") return;
    this.cursor = index;
    this.persist(cx);
    cx.notify();
  }

  showNew(cx) {
    if (this.screen === "loading" || this.screen === "generating") return;
    this.advanceClock();
    this.screen = "new";
    this.level = this.game ? LEVELS.indexOf(this.game.difficulty) : 1;
    cx.notify();
  }

  start(difficulty, cx) {
    if (this.screen !== "new") return;
    this.beginLoading("generating", cx);
    // Give the loading description a frame before synchronous puzzle generation.
    cx.timer.after(50, (cx) => {
      if (this.closed) return;
      const game = newGame(difficulty);
      this.loadingComplete = (cx) => {
        this.game = game;
        this.cursor = this.game.puzzle.indexOf("0");
        if (this.cursor < 0) this.cursor = 0;
        this.notesMode = false;
        this.newBest = false;
        this.scoreFloater = null;
        this.flash = null;
        this.lastClock = Date.now();
        this.screen = "board";
        this.persist(cx);
        this.handle.focus();
        cx.notify();
      };
    });
  }

  edit(action, cx) {
    if (this.screen !== "board" || this.game?.status !== "playing") return;
    this.advanceClock();
    const before = this.game;
    this.game = action(before);
    if (this.game !== before) {
      if (this.game.mistakes > before.mistakes) {
        this.flash = this.cursor;
        const version = ++this.flashVersion;
        cx.timer.after(600, (cx) => {
          if (version !== this.flashVersion || this.closed) return;
          this.flash = null;
          cx.notify();
        });
      }
      if (this.game.status !== "playing") this.finishGame(cx);
      this.persist(cx);
    }
    cx.notify();
  }

  finishGame(cx) {
    const game = this.game;
    const best = this.stats[game.difficulty];
    this.newBest = game.status === "won" && (game.score > best.bestScore || best.bestTime === null || game.elapsed < best.bestTime);
    this.stats = recordResult(this.stats, game);
    const stats = this.stats;
    cx.spawn(async () => { await saveStats(stats); });
  }

  digit(digit, cx) {
    const before = this.game;
    this.edit((game) => this.notesMode ? toggleNote(game, this.cursor, digit) : place(game, this.cursor, digit), cx);
    if (this.notesMode || !before || this.game === before) return;
    const wrong = this.game.mistakes > before.mistakes;
    const correct = before.board[this.cursor] === "0" && this.game.board[this.cursor] !== "0";
    if (!wrong && !correct) return;
    const base = DIFFICULTIES[this.game.difficulty].base;
    const streak = correct && before.lastCorrectAt !== null && this.game.elapsed - before.lastCorrectAt <= 10000;
    this.scoreFloater = { index: this.cursor, wrong, label: wrong ? `−${base}` : `+${base * (streak ? 2 : 1)}${streak ? " streak" : ""}` };
    const version = ++this.floaterVersion;
    cx.timer.after(700, (cx) => {
      if (version !== this.floaterVersion || this.closed) return;
      this.scoreFloater = null;
      cx.notify();
    });
    cx.notify();
  }

  toggleNotes(cx) {
    if (this.game?.status !== "playing" || this.screen !== "board") return;
    this.notesMode = !this.notesMode;
    this.persist(cx);
    cx.notify();
  }

  restartPuzzle(cx) {
    if (this.game?.status !== "lost") return;
    this.game = restart(this.game);
    this.newBest = false;
    this.scoreFloater = null;
    this.flash = null;
    this.notesMode = false;
    this.lastClock = Date.now();
    this.persist(cx);
    cx.notify();
  }

  keyDown(event, cx) {
    cx.stop_propagation();
    const key = event.key_char || event.key;
    if (event.key === "escape") {
      if (this.screen === "new" && this.game?.status === "playing") {
        this.screen = "board";
        this.lastClock = Date.now();
        cx.notify();
      } else closeOverlay(props().overlay);
      return;
    }
    if (["cmd-z", "ctrl-z"].includes(event.keystroke)) {
      this.edit((game) => undo(game), cx);
      return;
    }
    if (event.modifiers.control || event.modifiers.platform || event.modifiers.alt) return;
    if (this.screen === "new") {
      const quick = { "1": "easy", e: "easy", "2": "normal", n: "normal", "3": "hard", h: "hard" };
      if (quick[key]) this.start(quick[key], cx);
      else if (["up", "left", "down", "right"].includes(event.key)) {
        this.level = (this.level + (["up", "left"].includes(event.key) ? 2 : 1)) % 3;
        cx.notify();
      } else if (event.key === "enter") this.start(LEVELS[this.level], cx);
      return;
    }
    if (this.screen !== "board") return;
    if (key === "+") { this.showNew(cx); return; }
    if (key === "r") { this.restartPuzzle(cx); return; }
    if (this.game.status !== "playing") return;
    const moves = { left: [0, -1], h: [0, -1], right: [0, 1], l: [0, 1], up: [-1, 0], k: [-1, 0], down: [1, 0], j: [1, 0] };
    if (moves[key]) {
      const [dr, dc] = moves[key];
      this.select(((Math.floor(this.cursor / 9) + dr + 9) % 9) * 9 + (this.cursor % 9 + dc + 9) % 9, cx);
    } else if (/^[1-9]$/.test(key)) this.digit(Number(key), cx);
    else if (key === "0" || ["backspace", "delete"].includes(event.key)) this.edit((game) => erase(game, this.cursor), cx);
    else if (key === "n") this.toggleNotes(cx);
    else if (key === "u") this.edit((game) => undo(game), cx);
  }

  button(id, label, action, t, active = false) {
    return h_flex().id(id).h(34).px(12).flex_none().items_center().justify_center()
      .border_1().border_color(active ? t.accent : t.border).bg(active ? t.selected : t.raised)
      .text_color(active ? t.accent : t.foreground).hover((style) => style.bg(t.hover))
      .on_mouse_down("left", () => this.handle.focus())
      .on_click((_event, cx) => { this.handle.focus(); action(cx); cx.stop_propagation(); })
      .child(label);
  }

  newScreen(t) {
    return v_flex().flex_1().justify_center().gap(16)
      .child(div().text_size(22).font_semibold().child("Start a new game?"))
      .child(div().text_color(t.muted).child("Choose a difficulty. One solution, no hints."))
      .children(LEVELS.map((level, index) => {
        const difficulty = DIFFICULTIES[level];
        const best = this.stats[level];
        return this.button(`difficulty-${level}`, `${index + 1}  ${difficulty.label} — ${difficulty.permitted} ${difficulty.permitted === 1 ? "mistake" : "mistakes"} permitted`,
          (cx) => this.start(level, cx), t, index === this.level).h(88).flex_col().gap(8)
          .child(div().text_size(12).text_color(t.muted)
            .child(`Best time ${best.bestTime === null ? "—" : timeLabel(best.bestTime)} · Best score ${best.won ? best.bestScore : "—"}`));
      }))
      .child(div().text_size(11).text_color(t.dim).child("1 / 2 / 3 or e / n / h · ↑ ↓ and Enter"))
      .when(this.game?.status === "playing", (element) => element.child(this.button("back", "Back · Esc", (cx) => {
        this.screen = "board";
        this.lastClock = Date.now();
        cx.notify();
      }, t)));
  }

  cell(index, t) {
    const game = this.game;
    const row = Math.floor(index / 9), col = index % 9;
    const selectedRow = Math.floor(this.cursor / 9), selectedCol = this.cursor % 9;
    const digit = game.board[index];
    const same = digit !== "0" && digit === game.board[this.cursor];
    const related = row === selectedRow || col === selectedCol ||
      (Math.floor(row / 3) === Math.floor(selectedRow / 3) && Math.floor(col / 3) === Math.floor(selectedCol / 3));
    const background = this.flash === index ? t.ansi1 : index === this.cursor ? t.selected : same ? t.hover : related ? t.raised : t.background;
    const cell = v_flex().id(`cell-${index}`).relative().w(CELL).h(CELL).flex_none().items_center().justify_center()
      .border_r(col === 8 || col % 3 === 2 ? 0 : 1)
      .border_b(row === 8 || row % 3 === 2 ? 0 : 1).border_color(t.border).bg(background)
      .when(col === 2 || col === 5, (element) => element.child(div().absolute().right(0).top(0).w(2).h(CELL).bg(t.foreground)))
      .when(row === 2 || row === 5, (element) => element.child(div().absolute().bottom(0).left(0).h(2).w(CELL).bg(t.foreground)))
      .on_mouse_down("left", (_event, cx) => { this.select(index, cx); cx.stop_propagation(); })
      .on_click((_event, cx) => { this.select(index, cx); cx.stop_propagation(); });
    if (digit !== "0") return cell.child(div().text_size(34)
      .text_color(this.flash === index ? t.background : isGiven(game, index) ? t.foreground : t.accent).child(digit));
    const notes = game.notes[String(index)] || "";
    return cell.child(v_flex().children([0, 1, 2].map((r) => h_flex().children([1, 2, 3].map((c) => {
      const note = String(r * 3 + c);
      return div().w(18).h(18).text_size(12).text_center().text_color(t.muted).child(notes.includes(note) ? note : " ");
    })))));
  }

  result(t) {
    const won = this.game.status === "won";
    const best = this.stats[this.game.difficulty];
    return v_flex().absolute().inset_0().items_center().justify_center().bg(t.popover + "dd")
      .child(v_flex().p(20).gap(14).border_1().border_color(won ? t.ansi2 : t.ansi1).bg(t.popover)
        .child(div().text_size(20).font_semibold().text_color(won ? t.ansi2 : t.ansi1)
          .child(won ? `Solved in ${timeLabel(this.game.elapsed)}` : "Out of mistakes"))
        .when(won, (element) => element
          .child(div().text_size(26).font_semibold().text_color(t.accent).child(`Score ${this.game.score}`))
          .child(div().text_color(t.muted).child(`Time bonus +${this.game.timeBonus}`))
          .when(this.newBest, (panel) => panel.child(div().text_color(t.ansi2).font_semibold().child("New best!")))
          .child(div().text_color(t.muted).child(`Best score ${best.bestScore} · Best time ${best.bestTime === null ? "—" : timeLabel(best.bestTime)}`)))
        .when(!won, (element) => element.child(this.button("restart", "Restart this puzzle · r", (cx) => this.restartPuzzle(cx), t)))
        .child(this.button("result-new", "New game · +", (cx) => this.showNew(cx), t)));
  }

  board(t) {
    const game = this.game;
    const counts = remaining(game);
    return v_flex().gap(10).flex_none().items_center().w_full()
      .child(h_flex().h(24).w_full().justify_between().items_center()
        .child(div().text_color(game.mistakes > game.permitted ? t.ansi1 : t.muted)
          .child(`${DIFFICULTIES[game.difficulty].label} · ${game.permitted === 1 ? "Mistake" : "Mistakes"} ${game.mistakes}/${game.permitted} permitted`))
        .child(div().text_color(t.accent).font_semibold().child(`Score ${game.score}`))
        .child(div().text_color(t.foreground).child(timeLabel(game.elapsed))))
      .child(v_flex().relative().w(CELL * 9 + 4).h(CELL * 9 + 4).flex_none().border(2).border_color(t.accent)
        .children(Array.from({ length: 9 }, (_, row) => h_flex().h(CELL).flex_none()
          .children(Array.from({ length: 9 }, (_, col) => this.cell(row * 9 + col, t)))))
        .when(Boolean(this.scoreFloater), (element) => element.child(div().absolute()
          .left(Math.min(7 * CELL, (this.scoreFloater.index % 9) * CELL))
          .top(Math.max(0, Math.floor(this.scoreFloater.index / 9) * CELL - 12))
          .px(6).py(3).border_1().border_color(this.scoreFloater.wrong ? t.ansi1 : t.accent)
          .bg(t.popover).text_size(15).font_semibold().text_color(this.scoreFloater.wrong ? t.ansi1 : t.accent)
          .child(this.scoreFloater.label)))
        .when(game.status !== "playing", (element) => element.child(this.result(t))))
      .child(h_flex().gap(4).children(counts.map((count, index) =>
        this.button(`digit-${index + 1}`, "", (cx) => this.digit(index + 1, cx), t).w(56).h(54).px(0)
          .opacity(count ? 1 : 0.35).child(v_flex().items_center()
            .child(div().text_size(24).child(String(index + 1)))
            .child(div().text_size(9).text_color(t.dim).child(`${count} left`))))))
      .child(h_flex().gap(8)
        .child(this.button("undo", "Undo · u / ⌘Z", (cx) => this.edit((current) => undo(current), cx), t).opacity(canUndo(game) ? 1 : 0.35))
        .child(this.button("notes", this.notesMode ? "Notes ON · n" : "Notes OFF · n", (cx) => this.toggleNotes(cx), t, this.notesMode)))
      .child(div().text_size(10).text_color(t.dim).child("Click a square, then type 1–9 · 0 / Delete erase · arrows / hjkl move · Esc close"));
  }

  render() {
    const t = theme();
    return v_flex().id("sudoku").track_focus(this.handle).size_full().p(20).gap(10)
      .bg(t.popover).text_color(t.foreground).text_size(12)
      .on_mouse_down("left", () => this.handle.focus())
      .on_click(() => this.handle.focus())
      .on_key_down((event, cx) => this.keyDown(event, cx))
      .child(h_flex().h(34).flex_none().justify_between().items_center()
        .child(div().text_size(16).font_semibold().child("SUDOKU"))
        .child(h_flex().gap(8)
          .when(this.screen === "board", (element) => element.child(this.button("new", "+", (cx) => this.showNew(cx), t)))
          .child(this.button("close", "Esc ×", () => closeOverlay(props().overlay), t))))
      .child(this.screen === "loading" || this.screen === "generating"
        ? this.loadingScreen(t)
        : this.screen === "new" ? this.newScreen(t) : this.board(t));
  }
}
