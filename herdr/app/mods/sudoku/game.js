// Pure Sudoku state and seeded generation; compatible with QuickJS and Node.
export const DIFFICULTIES = {
  easy: { label: 'Easy', permitted: 5, clues: [38, 42], base: 10, par: 8 },
  normal: { label: 'Normal', permitted: 3, clues: [30, 34], base: 20, par: 15 },
  hard: { label: 'Hard', permitted: 1, clues: [24, 28], base: 40, par: 25 },
};

const FULL = 511;
const ROW = Array.from({ length: 81 }, (_, i) => Math.floor(i / 9));
const COL = Array.from({ length: 81 }, (_, i) => i % 9);
const BOX = Array.from({ length: 81 }, (_, i) => Math.floor(i / 27) * 3 + Math.floor((i % 9) / 3));
const POPCOUNT = Array.from({ length: 512 }, (_, mask) => {
  let count = 0;
  while (mask) { mask &= mask - 1; count++; }
  return count;
});
const DIGIT = Array.from({ length: 512 }, (_, bit) => Math.log2(bit) + 1);
const validIndex = index => Number.isInteger(index) && index >= 0 && index < 81;
const validDigit = digit => Number.isInteger(digit) && digit >= 1 && digit <= 9;
const nonnegative = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
const configFor = difficulty => Object.prototype.hasOwnProperty.call(DIFFICULTIES, difficulty) ? DIFFICULTIES[difficulty] : null;
const replaceCell = (board, index, digit) => board.slice(0, index) + digit + board.slice(index + 1);
const peers = (a, b) => ROW[a] === ROW[b] || COL[a] === COL[b] || BOX[a] === BOX[b];

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value ^= value + Math.imul(value ^ (value >>> 7), 61 | value);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle(values, random) {
  for (let i = values.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [values[i], values[j]] = [values[j], values[i]];
  }
  return values;
}

// One MRV bitmask search serves randomized filling and capped solution counting.
// All scratch arrays are local; counting always restores the supplied grid.
function searchGrid(grid, limit, random = null) {
  const rows = new Uint16Array(9), cols = new Uint16Array(9), boxes = new Uint16Array(9);
  for (let i = 0; i < 81; i++) {
    if (!grid[i]) continue;
    const bit = 1 << (grid[i] - 1), r = ROW[i], c = COL[i], b = BOX[i];
    if ((rows[r] | cols[c] | boxes[b]) & bit) return 0;
    rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit;
  }
  function visit() {
    let index = -1, candidates = 0, fewest = 10;
    for (let i = 0; i < 81; i++) {
      if (grid[i]) continue;
      const mask = FULL & ~(rows[ROW[i]] | cols[COL[i]] | boxes[BOX[i]]);
      const size = POPCOUNT[mask];
      if (!size) return 0;
      if (size < fewest) { index = i; candidates = mask; fewest = size; }
      if (size === 1) break;
    }
    if (index < 0) return 1;
    const r = ROW[index], c = COL[index], b = BOX[index];
    let count = 0;
    let choices = null;
    if (random) {
      choices = [];
      for (let mask = candidates; mask; mask &= mask - 1) choices.push(mask & -mask);
      shuffle(choices, random);
    }
    let choice = 0;
    while (candidates) {
      const bit = choices ? choices[choice++] : candidates & -candidates;
      candidates &= ~bit;
      grid[index] = DIGIT[bit];
      rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit;
      count += visit();
      // Keep the completed grid only during randomized filling.
      if (random && count) return count;
      grid[index] = 0;
      rows[r] &= ~bit; cols[c] &= ~bit; boxes[b] &= ~bit;
      if (count >= limit) return limit;
    }
    return count;
  }
  return visit();
}

export function generate(difficulty, seed) {
  const config = configFor(difficulty);
  if (!config) throw new RangeError('Unknown Sudoku difficulty');
  const random = seededRandom(seed);
  // A removal order can become irreducible above the range; retry with the
  // same PRNG stream, never return an out-of-range or ambiguous puzzle.
  for (;;) {
    const grid = new Uint8Array(81);
    searchGrid(grid, 1, random);
    const solution = Array.from(grid).join('');
    const order = shuffle(Array.from({ length: 81 }, (_, i) => i), random);
    const target = config.clues[0] + Math.floor(random() * (config.clues[1] - config.clues[0] + 1));
    let clues = 81;
    for (const index of order) {
      const digit = grid[index];
      grid[index] = 0;
      if (searchGrid(grid, 2) === 1) clues--;
      else grid[index] = digit;
      if (clues <= target) break;
    }
    if (clues <= config.clues[1]) return { puzzle: Array.from(grid).join(''), solution };
  }
}

export function randomSeed() {
  return Math.floor(Math.random() * 4294967296) >>> 0;
}

export function newGame(difficulty, seed = randomSeed(), now = Date.now()) {
  const { puzzle, solution } = generate(difficulty, seed);
  return {
    version: 1, difficulty, seed: seed >>> 0, puzzle, solution, board: puzzle,
    notes: {}, mistakes: 0, permitted: DIFFICULTIES[difficulty].permitted,
    status: 'playing', elapsed: 0, started: now, finished: null, last: null,
    history: [], score: 0, lastCorrectAt: null, timeBonus: 0,
  };
}

export function isGiven(game, index) {
  return validIndex(index) && game.puzzle[index] !== '0';
}

export function place(game, index, digit, now = Date.now()) {
  if (game.status !== 'playing' || !validIndex(index) || !validDigit(digit) || game.board[index] !== '0' || isGiven(game, index)) return game;
  const ok = game.solution[index] === String(digit);
  const last = { index, digit, ok };
  if (!ok) {
    const mistakes = game.mistakes + 1;
    const lost = mistakes > game.permitted;
    const score = Math.max(0, (game.score ?? 0) - DIFFICULTIES[game.difficulty].base);
    return { ...game, score, notes: { ...game.notes }, mistakes, last, status: lost ? 'lost' : 'playing', finished: lost ? now : null };
  }
  const notes = {};
  for (const key of Object.keys(game.notes)) {
    if (Number(key) === index) continue;
    const digits = peers(index, Number(key)) ? game.notes[key].replace(String(digit), '') : game.notes[key];
    if (digits) notes[key] = digits;
  }
  const board = replaceCell(game.board, index, digit), won = board === game.solution;
  const base = DIFFICULTIES[game.difficulty].base;
  const streak = game.lastCorrectAt != null && game.elapsed - game.lastCorrectAt <= 10000;
  const bonus = won ? timeBonus(game) : 0;
  const score = (game.score ?? 0) + base * (streak ? 2 : 1) + bonus;
  return { ...game, board, notes, last, score, lastCorrectAt: game.elapsed, timeBonus: bonus,
    history: pushHistory(game, index, notes), status: won ? 'won' : 'playing', finished: won ? now : null };

}

export function erase(game, index) {
  if (game.status !== 'playing' || !validIndex(index) || isGiven(game, index)) return game;
  if (game.board[index] === '0' && !game.notes[index]) return game;
  const notes = { ...game.notes };
  delete notes[index];
  return { ...game, board: replaceCell(game.board, index, '0'), notes, last: null, history: pushHistory(game, index, notes) };
}

export function toggleNote(game, index, digit) {
  if (game.status !== 'playing' || !validIndex(index) || !validDigit(digit) || game.board[index] !== '0' || isGiven(game, index)) return game;
  const notes = { ...game.notes }, value = String(digit), current = notes[index] || '';
  const next = current.includes(value) ? current.replace(value, '') : [...current, value].sort().join('');
  if (next) notes[index] = next;
  else delete notes[index];
  return { ...game, notes, last: game.last ? { ...game.last } : null, history: pushHistory(game, index, notes) };
}

export function restart(game, now = Date.now()) {
  return { ...game, board: game.puzzle, notes: {}, mistakes: 0, status: 'playing', elapsed: 0, started: now, finished: null, last: null, history: [], score: 0, lastCorrectAt: null, timeBonus: 0 };
}

export function tick(game, ms) {
  if (game.status !== 'playing' || !nonnegative(ms) || ms === 0 || !Number.isFinite(game.elapsed + ms)) return game;
  return { ...game, notes: { ...game.notes }, last: game.last ? { ...game.last } : null, elapsed: game.elapsed + ms };
}

// Missing notes are recorded as null so history survives JSON serialization.
function pushHistory(game, index, nextNotes) {
  const notes = {};
  const keys = new Set([...Object.keys(game.notes), ...Object.keys(nextNotes)]);
  for (const key of keys) {
    if (game.notes[key] !== nextNotes[key]) notes[key] = game.notes[key] ?? null;
  }
  return [...(game.history || []).slice(-199), { index, board: game.board[index], notes, score: game.score ?? 0 }];
}

export function canUndo(game) {
  return game.status === 'playing' && Array.isArray(game.history) && game.history.length > 0;
}

export function undo(game) {
  if (!canUndo(game)) return game;
  const entry = game.history[game.history.length - 1];
  const notes = { ...game.notes };
  for (const key of Object.keys(entry.notes)) {
    if (entry.notes[key] === null) delete notes[key];
    else notes[key] = entry.notes[key];
  }
  return { ...game, board: replaceCell(game.board, entry.index, entry.board), notes,
    score: entry.score, history: game.history.slice(0, -1), last: null };
}

export function timeBonus(game) {
  const { base, par } = DIFFICULTIES[game.difficulty];
  const multiplier = Math.max(0.25, Math.min(2, par * 60000 / game.elapsed));
  return Math.round(base * 20 * multiplier);
}

export function emptyStats() {
  const stats = {};
  for (const difficulty of Object.keys(DIFFICULTIES)) {
    stats[difficulty] = { played: 0, won: 0, bestScore: 0, bestTime: null };
  }
  return stats;
}

// The caller records each terminal game once; this does not deduplicate results.
export function recordResult(stats, game) {
  const next = {};
  for (const difficulty of Object.keys(DIFFICULTIES)) next[difficulty] = { ...stats[difficulty] };
  if (game.status !== 'won' && game.status !== 'lost') return next;
  const result = next[game.difficulty];
  result.played++;
  if (game.status === 'won') {
    result.won++;
    result.bestScore = Math.max(result.bestScore, game.score ?? 0);
    result.bestTime = result.bestTime === null ? game.elapsed : Math.min(result.bestTime, game.elapsed);
  }
  return next;
}

const validScore = value => Number.isSafeInteger(value) && value >= 0;
const validNotes = value => typeof value === 'string' && /^[1-9]{1,9}$/.test(value) && [...new Set(value)].sort().join('') === value;

// Validate history by replaying it backwards, preventing restoration of a wrong
// digit or notes on a filled cell. A bad optional stack never loses the game.
function validateHistory(game) {
  if (!Array.isArray(game.history) || game.history.length > 200) return [];
  let board = game.board;
  const notes = { ...game.notes }, history = [];
  for (let n = game.history.length - 1; n >= 0; n--) {
    const entry = game.history[n];
    if (!entry || !validIndex(entry.index) || game.puzzle[entry.index] !== '0' ||
        typeof entry.board !== 'string' || !/^[0-9]$/.test(entry.board) ||
        (entry.board !== '0' && entry.board !== game.solution[entry.index]) || !validScore(entry.score) ||
        !entry.notes || typeof entry.notes !== 'object' || Array.isArray(entry.notes)) return [];
    board = replaceCell(board, entry.index, entry.board);
    const touched = {};
    for (const key of Object.keys(entry.notes)) {
      const index = Number(key), value = entry.notes[key];
      if (!validIndex(index) || String(index) !== key || !peers(index, entry.index) ||
          (value !== null && !validNotes(value))) return [];
      touched[key] = value;
      if (value === null) delete notes[key];
      else notes[key] = value;
    }
    for (const key of Object.keys(notes)) if (board[Number(key)] !== '0') return [];
    history.unshift({ index: entry.index, board: entry.board, notes: touched, score: entry.score });
  }
  return history;
}

export function remaining(game) {
  const counts = Array(9).fill(9);
  for (const digit of game.board) if (digit !== '0') counts[Number(digit) - 1]--;
  return counts;
}

export function validate(obj) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return null;
  const config = configFor(obj.difficulty);
  if (!config || obj.version !== 1 || !Number.isInteger(obj.seed) || obj.seed < 0 || obj.seed > 0xffffffff) return null;
  for (const key of ['puzzle', 'board']) if (typeof obj[key] !== 'string' || !/^[0-9]{81}$/.test(obj[key])) return null;
  if (typeof obj.solution !== 'string' || !/^[1-9]{81}$/.test(obj.solution)) return null;
  if (searchGrid([...obj.solution].map(Number), 1) !== 1) return null;
  let clues = 0;
  for (let i = 0; i < 81; i++) {
    if (obj.puzzle[i] !== '0') {
      clues++;
      if (obj.puzzle[i] !== obj.solution[i] || obj.board[i] !== obj.puzzle[i]) return null;
    }
    if (obj.board[i] !== '0' && obj.board[i] !== obj.solution[i]) return null;
  }
  if (clues < config.clues[0] || clues > config.clues[1]) return null;
  if (searchGrid([...obj.puzzle].map(Number), 2) !== 1) return null;
  if (obj.permitted !== config.permitted || !Number.isInteger(obj.mistakes) || obj.mistakes < 0 || obj.mistakes > config.permitted + 1) return null;
  if (!nonnegative(obj.elapsed) || !nonnegative(obj.started)) return null;
  const expectedStatus = obj.mistakes > config.permitted ? 'lost' : obj.board === obj.solution ? 'won' : 'playing';
  if (obj.status !== expectedStatus || (obj.status === 'lost' && obj.board === obj.solution)) return null;
  if (obj.status === 'playing' ? obj.finished !== null : !nonnegative(obj.finished) || obj.finished < obj.started) return null;
  if (!obj.notes || typeof obj.notes !== 'object' || Array.isArray(obj.notes)) return null;
  const notes = {};
  for (const key of Object.keys(obj.notes)) {
    const index = Number(key), value = obj.notes[key];
    if (!validIndex(index) || String(index) !== key || obj.board[index] !== '0' || typeof value !== 'string' || !/^[1-9]{1,9}$/.test(value)) return null;
    if ([...new Set(value)].sort().join('') !== value) return null;
    notes[key] = value;
  }
  let last = null;
  if (obj.last !== null) {
    const value = obj.last;
    if (!value || typeof value !== 'object' || !validIndex(value.index) || !validDigit(value.digit) || typeof value.ok !== 'boolean') return null;
    if (obj.puzzle[value.index] !== '0' || value.ok !== (obj.solution[value.index] === String(value.digit))) return null;
    if (value.ok ? obj.board[value.index] !== String(value.digit) : obj.board[value.index] !== '0' || obj.mistakes === 0) return null;
    last = { index: value.index, digit: value.digit, ok: value.ok };
  }
  const score = obj.score === undefined ? 0 : obj.score;
  const bonus = obj.timeBonus === undefined ? 0 : obj.timeBonus;
  const lastCorrectAt = obj.lastCorrectAt === undefined ? null : obj.lastCorrectAt;
  if (!validScore(score) || !validScore(bonus) || (obj.status !== 'won' && bonus !== 0)) return null;
  if (lastCorrectAt !== null && (!nonnegative(lastCorrectAt) || lastCorrectAt > obj.elapsed)) return null;
  return {
    version: 1, difficulty: obj.difficulty, seed: obj.seed, puzzle: obj.puzzle,
    solution: obj.solution, board: obj.board, notes, mistakes: obj.mistakes,
    permitted: obj.permitted, status: obj.status, elapsed: obj.elapsed,
    started: obj.started, finished: obj.finished, last,
    score, timeBonus: bonus, lastCorrectAt, history: validateHistory(obj),
    ...(validIndex(obj.cursor) ? { cursor: obj.cursor } : {}),
    ...(typeof obj.notesMode === 'boolean' ? { notesMode: obj.notesMode } : {}),
  };
}
