import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { DIFFICULTIES, generate, newGame, place, erase, toggleNote, restart, tick, isGiven, remaining, validate, randomSeed, undo, canUndo, timeBonus, emptyStats, recordResult } from '../mods/sudoku/game.js';

// Independent solver: verifies the published puzzles, not the generator's own counter.
function countSolutions(text) {
  const board = [...text].map(Number);
  function solve() {
    let index = -1, choices = [];
    for (let i = 0; i < 81; i++) {
      if (board[i]) continue;
      const row = Math.floor(i / 9), col = i % 9;
      const used = new Set();
      for (let j = 0; j < 9; j++) {
        used.add(board[row * 9 + j]);
        used.add(board[j * 9 + col]);
        used.add(board[(Math.floor(row / 3) * 3 + Math.floor(j / 3)) * 9 + Math.floor(col / 3) * 3 + j % 3]);
      }
      const available = [1, 2, 3, 4, 5, 6, 7, 8, 9].filter(d => !used.has(d));
      if (!available.length) return 0;
      if (index < 0 || available.length < choices.length) { index = i; choices = available; }
      if (choices.length === 1) break;
    }
    if (index < 0) return 1;
    let count = 0;
    for (const digit of choices) {
      board[index] = digit;
      count += solve();
      if (count >= 2) break;
    }
    board[index] = 0;
    return Math.min(count, 2);
  }
  return solve();
}
function validSolution(solution) {
  assert.match(solution, /^[1-9]{81}$/);
  for (let i = 0; i < 9; i++) {
    const row = [], col = [], box = [];
    for (let j = 0; j < 9; j++) {
      row.push(solution[i * 9 + j]); col.push(solution[j * 9 + i]);
      box.push(solution[(Math.floor(i / 3) * 3 + Math.floor(j / 3)) * 9 + (i % 3) * 3 + j % 3]);
    }
    for (const unit of [row, col, box]) assert.equal([...unit].sort().join(''), '123456789');
  }
}
const blank = game => game.board.indexOf('0');
const wrong = (game, index) => Number(game.solution[index]) % 9 + 1;
const freeze = game => { Object.freeze(game.notes); if (game.last) Object.freeze(game.last); return Object.freeze(game); };

for (const [difficulty, config] of Object.entries(DIFFICULTIES)) {
  test(`${difficulty}: deterministic, valid, unique, in clue range for ten seeds`, () => {
    for (let seed = 0; seed < 10; seed++) {
      const generated = generate(difficulty, seed);
      assert.deepEqual(generate(difficulty, seed), generated);
      validSolution(generated.solution);
      assert.match(generated.puzzle, /^[0-9]{81}$/);
      for (let i = 0; i < 81; i++) assert.ok(generated.puzzle[i] === '0' || generated.puzzle[i] === generated.solution[i]);
      const clues = generated.puzzle.replaceAll('0', '').length;
      assert.ok(clues >= config.clues[0] && clues <= config.clues[1], `${difficulty}/${seed}: ${clues}`);
      assert.equal(countSolutions(generated.puzzle), 1);
    }
  });
  test(`${difficulty}: loses only after permitted mistakes`, () => {
    let game = newGame(difficulty, 42, 100);
    const index = blank(game), digit = wrong(game, index);
    for (let n = 1; n <= config.permitted + 1; n++) {
      const previous = freeze(game);
      game = place(previous, index, digit, 100 + n);
      assert.equal(game.board, previous.board);
      assert.equal(game.mistakes, n);
      assert.deepEqual(game.last, { index, digit, ok: false });
      assert.equal(game.status, n <= config.permitted ? 'playing' : 'lost');
    }
    assert.equal(game.finished, 100 + config.permitted + 1);
    assert.equal(place(game, index, Number(game.solution[index])), game);
    assert.equal(erase(game, index), game);
    assert.equal(toggleNote(game, index, 1), game);
    assert.equal(tick(game, 100), game);
    assert.deepEqual(validate(game), game);
  });
}

test('newGame fields, seed boundaries and randomSeed uint32', () => {
  for (const seed of [0, 1, 0xffffffff]) {
    const game = newGame('easy', seed, 123);
    assert.equal(game.seed, seed); assert.equal(game.started, 123);
    assert.equal(game.board, game.puzzle); assert.equal(game.version, 1);
    assert.equal(game.status, 'playing'); assert.equal(game.finished, null);
    assert.equal(game.last, null); assert.equal(game.elapsed, 0);
    assert.equal(game.mistakes, 0); assert.deepEqual(game.notes, {});
  }
  const seed = randomSeed(); assert.ok(Number.isInteger(seed) && seed >= 0 && seed <= 0xffffffff);
  assert.throws(() => generate('unknown', 1));
  assert.throws(() => generate('toString', 1));
});

test('correct placement clears own and peer notes, preserving non-peers', () => {
  const original = newGame('easy', 7, 100), index = blank(original), digit = Number(original.solution[index]);
  const row = Math.floor(index / 9), col = index % 9;
  const peers = i => Math.floor(i / 9) === row || i % 9 === col || (Math.floor(i / 27) === Math.floor(index / 27) && Math.floor((i % 9) / 3) === Math.floor(col / 3));
  let game = original;
  for (let i = 0; i < 81; i++) if (game.board[i] === '0') game = toggleNote(game, i, digit);
  const snapshot = JSON.stringify(game);
  const next = place(freeze(game), index, digit, 120);
  assert.equal(JSON.stringify(game), snapshot);
  assert.equal(next.board[index], String(digit)); assert.equal(next.notes[index], undefined);
  for (const key of Object.keys(game.notes)) assert.equal(next.notes[key], peers(Number(key)) ? undefined : String(digit));
  assert.deepEqual(next.last, { index, digit, ok: true });
  assert.equal(next.mistakes, 0);
  assert.equal(place(next, index, digit), next);
  const given = [...game.puzzle].findIndex(d => d !== '0');
  assert.equal(isGiven(game, given), true); assert.equal(isGiven(game, index), false);
  assert.equal(place(game, given, wrong(game, given)), game);
});

test('notes toggle sorted digits only on empty cells; erase clears entries and notes', () => {
  let game = newGame('normal', 8, 100), index = blank(game);
  game = toggleNote(freeze(game), index, 9);
  game = toggleNote(freeze(game), index, 2);
  assert.equal(game.notes[index], '29');
  game = toggleNote(freeze(game), index, 9); assert.equal(game.notes[index], '2');
  game = toggleNote(freeze(game), index, 2); assert.equal(game.notes[index], undefined);
  game = toggleNote(game, index, 4);
  const erasedNote = erase(freeze(game), index); assert.equal(erasedNote.notes[index], undefined);
  const entered = place(game, index, Number(game.solution[index]));
  assert.equal(toggleNote(entered, index, 2), entered);
  const erased = erase(freeze(entered), index); assert.equal(erased.board[index], '0'); assert.equal(erased.last, null);
  const given = [...game.puzzle].findIndex(d => d !== '0');
  assert.equal(erase(game, given), game); assert.equal(toggleNote(game, given, 1), game);
  for (const invalid of [-1, 81, 1.5, '1', null]) {
    assert.equal(place(game, invalid, 1), game); assert.equal(erase(game, invalid), game); assert.equal(toggleNote(game, invalid, 1), game);
  }
  for (const invalid of [0, 10, 1.5, '1', null]) {
    assert.equal(place(game, index, invalid), game); assert.equal(toggleNote(game, index, invalid), game);
  }
});

test('last placement wins; completed games are inert and validate', () => {
  let game = newGame('normal', 10, 100);
  for (let i = 0; i < 81; i++) if (game.board[i] === '0') game = place(freeze(game), i, Number(game.solution[i]), 200 + i);
  assert.equal(game.status, 'won'); assert.equal(game.board, game.solution); assert.ok(game.finished >= 200);
  assert.deepEqual(remaining(game), Array(9).fill(0));
  assert.equal(place(game, 0, 1), game); assert.equal(erase(game, 0), game);
  assert.equal(toggleNote(game, 0, 1), game); assert.equal(tick(game, 100), game);
  assert.deepEqual(validate(game), game);
});

test('restart preserves identity, clears all progress; tick and remaining are immutable', () => {
  let game = newGame('hard', 12, 100), index = blank(game);
  const counts = remaining(game); assert.equal(counts.reduce((a, b) => a + b, 0), game.board.split('0').length - 1);
  const entered = place(game, index, Number(game.solution[index]));
  assert.equal(remaining(entered)[Number(game.solution[index]) - 1], counts[Number(game.solution[index]) - 1] - 1);
  game = toggleNote(game, index, 3); game = place(game, index, wrong(game, index)); game = tick(game, 1234);
  assert.equal(game.elapsed, 1234);
  for (const bad of [-1, NaN, Infinity, '2']) assert.equal(tick(game, bad), game);
  const reset = restart(freeze(game), 900);
  assert.deepEqual(reset, newGame('hard', 12, 900));
});

test('validate accepts JSON state, clones nested state, rejects corrupt invariants and junk', () => {
  const game = newGame('easy', 15, 100), index = blank(game);
  assert.deepEqual(validate(game), game);
  assert.deepEqual(validate(JSON.parse(JSON.stringify(game))), game);
  const noted = toggleNote(game, index, 3), copy = validate(noted);
  assert.notEqual(copy, noted); assert.notEqual(copy.notes, noted.notes);
  const replacement = (text, i, digit) => text.slice(0, i) + digit + text.slice(i + 1);
  const corrupt = [null, false, 4, '', [], {},
    { ...game, difficulty: 'bad' }, { ...game, difficulty: 'toString' },
    { ...game, version: 2 }, { ...game, puzzle: '0' }, { ...game, board: '0' }, { ...game, solution: '1' },
    { ...game, solution: '1'.repeat(81) },
    { ...game, board: replacement(game.board, index, wrong(game, index)) },
    { ...game, board: '0'.repeat(81) }, { ...game, permitted: 100 },
    { ...game, mistakes: -1 }, { ...game, elapsed: -1 }, { ...game, seed: -1 }, { ...game, started: NaN },
    { ...game, notes: { 81: '1' } }, { ...game, notes: { [index]: '31' } },
    { ...game, notes: [] }, { ...game, status: 'won' }, { ...game, status: 'lost' },
    { ...game, finished: 200 }, { ...game, last: { index: 99, digit: 1, ok: false } },
  ];
  for (const value of corrupt) assert.equal(validate(value), null, JSON.stringify(value));
});

test('optional UI fields survive validation and state transitions; invalid fields are dropped', () => {
  const base = newGame('easy', 23, 100), index = blank(base);
  const game = freeze({ ...base, cursor: index, notesMode: true });
  const loaded = validate(JSON.parse(JSON.stringify(game)));
  assert.deepEqual(loaded, game);
  for (const next of [
    place(game, index, Number(game.solution[index]), 200),
    place(game, index, wrong(game, index), 200),
    erase(toggleNote(game, index, 1), index),
    toggleNote(game, index, 1), tick(game, 100), restart(game, 200),
  ]) {
    assert.equal(next.cursor, index);
    assert.equal(next.notesMode, true);
  }
  for (const cursor of [0, 80]) {
    for (const notesMode of [true, false]) {
      const valid = validate({ ...base, cursor, notesMode });
      assert.equal(valid.cursor, cursor); assert.equal(valid.notesMode, notesMode);
    }
  }
  for (const cursor of [-1, 81, 1.5, '1', null]) {
    const valid = validate({ ...base, cursor, notesMode: false });
    assert.ok(valid); assert.equal(Object.hasOwn(valid, 'cursor'), false);
    assert.equal(valid.notesMode, false);
  }
  for (const notesMode of [0, 1, 'true', null]) {
    const valid = validate({ ...base, cursor: 80, notesMode });
    assert.ok(valid); assert.equal(Object.hasOwn(valid, 'notesMode'), false);
    assert.equal(valid.cursor, 80);
  }
  assert.equal(Object.hasOwn(validate(base), 'cursor'), false);
  assert.equal(Object.hasOwn(validate(base), 'notesMode'), false);
});

for (const difficulty of Object.keys(DIFFICULTIES)) {
  test(`${difficulty}: generation timing over twenty seeds`, t => {
    const start = performance.now();
    for (let seed = 100; seed < 120; seed++) generate(difficulty, seed);
    const average = (performance.now() - start) / 20;
    t.diagnostic(`${difficulty} average: ${average.toFixed(3)} ms`);
    if (difficulty === 'hard') assert.ok(average < 40, `hard average ${average} ms exceeds 40 ms`);
  });
}


test('scoring uses base, inclusive ten-second streaks and nonnegative mistake penalties', () => {
  for (const [difficulty, base, par] of [['easy', 10, 8], ['normal', 20, 15], ['hard', 40, 25]]) {
    assert.equal(DIFFICULTIES[difficulty].base, base);
    assert.equal(DIFFICULTIES[difficulty].par, par);
    let game = newGame(difficulty, 61, 100);
    assert.equal(game.score, 0); assert.equal(game.lastCorrectAt, null);
    assert.equal(game.timeBonus, 0); assert.deepEqual(game.history, []);
    let i = blank(game);
    game = place(game, i, wrong(game, i), 110);
    assert.equal(game.score, 0); assert.equal(canUndo(game), false);
    game = tick(game, 20000);
    game = place(game, i, Number(game.solution[i]), 120);
    assert.equal(game.score, base); assert.equal(game.lastCorrectAt, 20000);
    game = tick(game, 10000); i = blank(game);
    game = place(game, i, Number(game.solution[i]), 130);
    assert.equal(game.score, base * 3);
    game = tick(game, 10001); i = blank(game);
    game = place(game, i, Number(game.solution[i]), 140);
    assert.equal(game.score, base * 4);
    game = place(game, blank(game), wrong(game, blank(game)), 150);
    assert.equal(game.score, base * 3);
  }
});

test('undo restores correct placement and peer notes, preserves mistakes, time and UI fields', () => {
  let game = newGame('easy', 62, 100), i = blank(game);
  const digit = Number(game.solution[i]);
  for (let j = 0; j < 81; j++) if (game.board[j] === '0') game = toggleNote(game, j, digit);
  game = { ...game, cursor: i, notesMode: true };
  const before = game;
  game = place(freeze(game), i, digit, 110);
  assert.equal(canUndo(game), true);
  const placed = game;
  const j = blank(game);
  game = place(game, j, wrong(game, j), 120);
  const undone = undo(freeze(tick(game, 500)));
  assert.equal(undone.board, before.board); assert.deepEqual(undone.notes, before.notes);
  assert.equal(undone.score, before.score); assert.equal(undone.mistakes, 1);
  assert.equal(undone.elapsed, 500); assert.equal(undone.cursor, i); assert.equal(undone.notesMode, true);
  assert.equal(undone.last, null);
  assert.equal(placed.board[i], String(digit));
  assert.deepEqual(validate(JSON.parse(JSON.stringify(undone))), undone);
});

test('undo handles erasure, note addition/removal and the 200-entry history bound', () => {
  let game = newGame('normal', 63, 100), i = blank(game);
  assert.equal(undo(game), game); assert.equal(canUndo(game), false);
  const noted = toggleNote(game, i, 3);
  assert.deepEqual(undo(noted).notes, {});
  const removed = toggleNote(noted, i, 3);
  assert.deepEqual(undo(removed).notes, noted.notes);
  assert.deepEqual(undo(erase(noted, i)).notes, noted.notes);
  const placed = place(game, i, Number(game.solution[i]), 110);
  const erased = erase(placed, i);
  const restored = undo(erased);
  assert.equal(restored.board, placed.board); assert.equal(restored.score, placed.score);
  assert.deepEqual(validate(JSON.parse(JSON.stringify(erased))), erased);
  for (let n = 0; n < 220; n++) game = toggleNote(game, i, 3);
  assert.equal(game.history.length, 200);
  assert.deepEqual(validate(game), game);
  for (let n = 0; n < 200; n++) game = undo(game);
  assert.equal(canUndo(game), false);
  assert.deepEqual(restart(placed, 200), newGame('normal', 63, 200));
  assert.equal(place(placed, i, Number(placed.solution[i])), placed);
});

test('time bonus clamps to quarter/double multiplier, awarded exactly once on win', () => {
  for (const difficulty of Object.keys(DIFFICULTIES)) {
    const config = DIFFICULTIES[difficulty];
    for (const [elapsed, multiplier] of [[0, 2], [1, 2], [config.par * 60000, 1], [config.par * 60000 * 10, 0.25]]) {
      let game = newGame(difficulty, 64, 100);
      game = tick(game, elapsed);
      assert.equal(timeBonus(game), Math.round(config.base * 20 * multiplier));
      const blanks = [...game.board].flatMap((d, i) => d === '0' ? [i] : []);
      for (const i of blanks) game = place(game, i, Number(game.solution[i]), 200);
      assert.equal(game.timeBonus, Math.round(config.base * 20 * multiplier));
      assert.equal(game.score, config.base * (blanks.length * 2 - 1) + game.timeBonus);
      assert.equal(canUndo(game), false); assert.equal(undo(game), game);
      assert.equal(place(game, 0, 1), game);
      assert.deepEqual(validate(game), game);
    }
  }
});

test('result stats count terminal games and winning bests without mutating input', () => {
  const stats = emptyStats();
  assert.deepEqual(stats.easy, { played: 0, won: 0, bestScore: 0, bestTime: null });
  assert.notEqual(stats.easy, stats.hard);
  let game = newGame('normal', 65, 100);
  assert.deepEqual(recordResult(stats, game), stats);
  for (const key of Object.keys(stats)) Object.freeze(stats[key]);
  Object.freeze(stats);
  const first = recordResult(stats, { ...game, status: 'won', score: 1000, elapsed: 30000 });
  assert.deepEqual(first.normal, { played: 1, won: 1, bestScore: 1000, bestTime: 30000 });
  const second = recordResult(first, { ...game, status: 'won', score: 800, elapsed: 20000 });
  assert.deepEqual(second.normal, { played: 2, won: 2, bestScore: 1000, bestTime: 20000 });
  const lost = recordResult(second, { ...game, status: 'lost', score: 2000, elapsed: 1 });
  assert.deepEqual(lost.normal, { played: 3, won: 2, bestScore: 1000, bestTime: 20000 });
  assert.equal(stats.normal.played, 0);
});

test('validation defaults legacy scoring, preserves valid history and discards malformed history', () => {
  let game = newGame('easy', 66, 100), i = blank(game);
  const legacy = { ...game };
  for (const key of ['score', 'lastCorrectAt', 'timeBonus', 'history']) delete legacy[key];
  assert.deepEqual(validate(legacy), game);
  game = toggleNote(game, i, 1);
  game = place(game, i, Number(game.solution[i]), 110);
  const copy = validate(JSON.parse(JSON.stringify(game)));
  assert.deepEqual(copy, game); assert.notEqual(copy.history, game.history);
  assert.notEqual(copy.history[0].notes, game.history[0].notes);
  for (const history of [null, {}, Array(201).fill(game.history[0]), [{ index: 81, board: '0', notes: {}, score: 0 }],
    [{ index: i, board: '9', notes: {}, score: 0 }], [{ index: i, board: '0', notes: { 81: '1' }, score: 0 }],
    [{ index: i, board: '0', notes: {}, score: -1 }]]) {
    const valid = validate({ ...game, history });
    assert.ok(valid); assert.deepEqual(valid.history, []);
  }
  for (const fields of [{ score: -1 }, { score: 1.5 }, { lastCorrectAt: game.elapsed + 1 }, { timeBonus: -1 }]) {
    assert.equal(validate({ ...game, ...fields }), null);
  }
});
