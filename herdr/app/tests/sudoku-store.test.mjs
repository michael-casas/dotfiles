import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { newGame, validate, emptyStats } from '../mods/sudoku/game.js';

const storeURL = new URL('../mods/sudoku/store.js', import.meta.url);
let instance = 0;

// Exercise the real module without Node needing Herdr or touching the user's save.
async function loadStore() {
  const source = readFileSync(storeURL, 'utf8')
    .replace(/import \{[^}]+\} from "herdr";/, `
      export const io = {
        text: null, reads: 0, writes: [], directories: 0, failures: 0,
        readError: false, mkdirError: false, external: undefined,
        now: 0, hangNext: false, release: null,
      };
      const Date = { now: () => io.now };
      const home = () => '/test-home';
      const exec = async (command, args) => {
        if (command !== 'mkdir' || args[0] !== '-p') throw new Error('unexpected exec');
        io.directories++;
        return { code: io.mkdirError ? 1 : 0, stdout: '', stderr: 'mkdir failed' };
      };
      const readTextFile = async () => {
        io.reads++;
        if (io.readError) throw new Error('read failed');
        return io.text;
      };
      const writeTextFile = async (path, text, expected) => {
        io.writes.push({ path, text, expected });
        if (io.hangNext) {
          io.hangNext = false;
          await new Promise(resolve => { io.release = resolve; });
        }
        await Promise.resolve();
        if (io.external !== undefined) {
          io.text = io.external;
          io.external = undefined;
        }
        if (io.failures > 0) { io.failures--; throw new Error('write failed'); }
        if (io.text !== expected) throw new Error('stale snapshot');
        io.text = text;
        return null;
      };
    `)
    .replace('"./game.js"', JSON.stringify(new URL('../mods/sudoku/game.js', import.meta.url).href));
  return import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}#${instance++}`);
}

const game = newGame('easy', 123, 1731400000000);

test('round trips a validated game without changing it', async () => {
  const { parseState, serializeState } = await loadStore();
  const before = structuredClone(game);
  assert.ok(validate(game));
  assert.deepEqual(parseState(serializeState(game)), game);
  assert.deepEqual(game, before);
});

test('round trips a null game in a versioned envelope', async () => {
  const { parseState, serializeState } = await loadStore();
  assert.deepEqual(JSON.parse(serializeState(null)), { version: 1, game: null, stats: emptyStats() });
  assert.equal(parseState(serializeState(null)), null);
});

test('broken JSON and junk envelopes produce null', async () => {
  const { parseState } = await loadStore();
  for (const value of [null, undefined, '', '{broken', 'null', '[]', '42', '{}']) {
    assert.equal(parseState(value), null);
  }
});

test('rejects an unsupported envelope version', async () => {
  const { parseState } = await loadStore();
  assert.equal(parseState(JSON.stringify({ version: 2, game })), null);
});

test('rejects a game the engine validator rejects', async () => {
  const { parseState, serializeState } = await loadStore();
  const invalid = { ...game, board: 'invalid' };
  assert.equal(validate(invalid), null);
  assert.equal(parseState(JSON.stringify({ version: 1, game: invalid })), null);
  assert.deepEqual(JSON.parse(serializeState(invalid)), { version: 1, game: null, stats: emptyStats() });
});

test('serializing junk safely produces a null game', async () => {
  const { serializeState } = await loadStore();
  const cyclic = {}; cyclic.self = cyclic;
  for (const value of [undefined, 42, [], {}, cyclic]) {
    assert.deepEqual(JSON.parse(serializeState(value)), { version: 1, game: null, stats: emptyStats() });
  }
});

test('loads missing and malformed saves as null', async () => {
  const store = await loadStore();
  assert.equal(await store.loadGame(), null);
  store.io.text = '{broken';
  assert.equal(await store.loadGame(), null);
  assert.equal(store.io.directories, 0);
});

test('loads a valid save and preserves the exact text for compare-and-swap', async () => {
  const store = await loadStore();
  const text = JSON.stringify({ version: 1, game }, null, 4);
  store.io.text = text;
  assert.deepEqual(await store.loadGame(), game);
  await store.saveGame(null);
  assert.equal(store.io.writes[0].expected, text);
});

test('serializes fast saves and creates the directory once', async () => {
  const store = await loadStore();
  const next = { ...game, elapsed: 1000 };
  await Promise.all([store.saveGame(game), store.saveGame(next), store.saveGame(null)]);
  assert.equal(store.io.directories, 1);
  assert.equal(store.io.writes.length, 3);
  assert.equal(store.io.writes[0].expected, null);
  assert.equal(store.io.writes[1].expected, store.io.writes[0].text);
  assert.equal(store.io.writes[2].expected, store.io.writes[1].text);
  assert.equal(store.parseState(store.io.text), null);
  assert.equal(store.STATE_PATH, '/test-home/.local/share/herdr-sudoku/state.json');
});

test('save before load reads an existing snapshot before writing', async () => {
  const store = await loadStore();
  store.io.text = 'existing broken save';
  await store.saveGame(game);
  assert.equal(store.io.writes[0].expected, 'existing broken save');
  assert.deepEqual(store.parseState(store.io.text), game);
});

test('re-reads once after a stale snapshot and retries with last writer winning', async () => {
  const store = await loadStore();
  await store.loadGame();
  store.io.external = 'external writer';
  await store.saveGame(game);
  assert.equal(store.io.reads, 2);
  assert.equal(store.io.writes.length, 2);
  assert.equal(store.io.writes[1].expected, 'external writer');
  assert.deepEqual(store.parseState(store.io.text), game);
});

test('exhausted writes log but resolve, and later saves still work', async (t) => {
  const errors = [];
  t.mock.method(console, 'error', (...args) => errors.push(args));
  const store = await loadStore();
  store.io.failures = 2;
  await assert.doesNotReject(store.saveGame(game));
  assert.equal(store.io.writes.length, 2);
  assert.equal(errors.length, 1);
  await store.saveGame(game);
  assert.deepEqual(store.parseState(store.io.text), game);
});

test('read failures never escape to the UI', async (t) => {
  t.mock.method(console, 'error', () => {});
  const store = await loadStore();
  store.io.readError = true;
  assert.equal(await store.loadGame(), null);
  await assert.doesNotReject(store.saveGame(game));
  assert.equal(store.io.writes.length, 0);
  store.io.readError = false;
  await store.saveGame(game);
  assert.deepEqual(store.parseState(store.io.text), game);
});

test('failed mkdir prevents writes and a later save can recover', async (t) => {
  t.mock.method(console, 'error', () => {});
  const store = await loadStore();
  store.io.mkdirError = true;
  await assert.doesNotReject(store.saveGame(game));
  assert.equal(store.io.writes.length, 0);
  store.io.mkdirError = false;
  await store.saveGame(game);
  assert.deepEqual(store.parseState(store.io.text), game);
});

test('a load immediately after a save observes the latest game', async () => {
  const store = await loadStore();
  const saving = store.saveGame(game);
  const loading = store.loadGame();
  await saving;
  assert.deepEqual(await loading, game);
});

const flush = () => new Promise(resolve => setImmediate(resolve));
async function bounded(promise) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('operation stuck behind hung write')), 100); }),
    ]);
  } finally { clearTimeout(timer); }
}

test('load resolves with the latest game even when a write never resolves', async () => {
  const store = await loadStore();
  store.io.hangNext = true;
  store.saveGame(game);
  await flush();
  assert.equal(store.io.writes.length, 1);
  assert.deepEqual(await bounded(store.loadGame()), game);
});

test('a save after three seconds bypasses a hung write and skips its queued saves', async () => {
  const store = await loadStore();
  store.io.hangNext = true;
  store.saveGame(game);
  await flush();
  store.saveGame({ ...game, elapsed: 1000 });
  store.io.now = 3001;
  const newest = { ...game, elapsed: 4000 };
  await bounded(store.saveGame(newest));
  assert.deepEqual(store.parseState(store.io.text), newest);
  assert.equal(store.io.writes.length, 2);
  store.io.release();
  await flush();
  assert.deepEqual(store.parseState(store.io.text), newest);
  assert.equal(store.io.writes.length, 2);
});

test('null is also a latest save and loads without waiting for I/O', async () => {
  const store = await loadStore();
  store.io.hangNext = true;
  store.saveGame(null);
  await flush();
  assert.equal(await bounded(store.loadGame()), null);
});

test('old saves without stats load empty stats without losing the game', async () => {
  const store = await loadStore();
  store.io.text = JSON.stringify({ version: 1, game });
  assert.deepEqual(await store.loadStats(), emptyStats());
  assert.deepEqual(await store.loadGame(), game);
});

test('saving stats preserves an existing game without a prior load', async () => {
  const store = await loadStore();
  store.io.text = JSON.stringify({ version: 1, game });
  const stats = emptyStats();
  stats.easy = { played: 2, won: 1, bestScore: 200, bestTime: 60000 };
  await store.saveStats(stats);
  assert.deepEqual(await store.loadStats(), stats);
  assert.deepEqual(store.parseState(store.io.text), game);
  assert.deepEqual(JSON.parse(store.io.text).stats, stats);
});

test('saving a game preserves existing stats without a prior load', async () => {
  const store = await loadStore();
  const stats = emptyStats();
  stats.hard = { played: 4, won: 2, bestScore: 900, bestTime: 100000 };
  store.io.text = JSON.stringify({ version: 1, game: null, stats });
  await store.saveGame(game);
  assert.deepEqual(await store.loadStats(), stats);
  assert.deepEqual(JSON.parse(store.io.text).stats, stats);
});

test('interleaved game and stats saves preserve both latest values', async () => {
  const store = await loadStore();
  const stats = emptyStats();
  stats.normal = { played: 1, won: 0, bestScore: 0, bestTime: null };
  const next = { ...game, elapsed: 3000 };
  await Promise.all([store.saveGame(game), store.saveStats(stats), store.saveGame(next)]);
  assert.deepEqual(await store.loadStats(), stats);
  assert.deepEqual(store.parseState(store.io.text), next);
  assert.deepEqual(JSON.parse(store.io.text).stats, stats);
});

test('stats load resolves and a later stats save bypasses a hung game save', async () => {
  const store = await loadStore();
  store.io.hangNext = true;
  store.saveGame(game);
  await flush();
  assert.deepEqual(await bounded(store.loadStats()), emptyStats());
  store.io.now = 3001;
  const stats = emptyStats();
  stats.easy.played = 1;
  await bounded(store.saveStats(stats));
  assert.deepEqual(store.parseState(store.io.text), game);
  assert.deepEqual(await store.loadStats(), stats);
});

test('malformed stats and read failures load empty stats', async (t) => {
  t.mock.method(console, 'error', () => {});
  const store = await loadStore();
  for (const stats of [null, {}, { easy: { played: -1 } }]) {
    store.io.text = JSON.stringify({ version: 1, game, stats });
    assert.deepEqual(await store.loadStats(), emptyStats());
  }
  store.io.readError = true;
  assert.deepEqual(await store.loadStats(), emptyStats());
});

test('stale game-save retry preserves stats from the external writer', async () => {
  const store = await loadStore();
  await store.loadGame();
  const stats = emptyStats();
  stats.hard = { played: 1, won: 1, bestScore: 800, bestTime: 120000 };
  store.io.external = JSON.stringify({ version: 1, game: null, stats });
  await store.saveGame(game);
  assert.deepEqual(JSON.parse(store.io.text).stats, stats);
  assert.deepEqual(store.parseState(store.io.text), game);
});
