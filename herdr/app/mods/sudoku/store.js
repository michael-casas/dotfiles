import { home, exec, readTextFile, writeTextFile } from "herdr";
import { validate, emptyStats } from "./game.js";

export const STATE_DIR = `${home()}/.local/share/herdr-sudoku`;
export const STATE_PATH = `${STATE_DIR}/state.json`;

let queue = Promise.resolve();
let directoryReady = false;
let snapshot;
let latestText;
let writeStarted = null;
let generation = 0;
let gameOverride;
let statsOverride;

export function parseState(text) {
  try {
    const state = JSON.parse(text);
    if (!state || state.version !== 1) return null;
    return validate(state.game);
  } catch {
    return null;
  }
}

function parseStats(text) {
  try {
    const state = JSON.parse(text);
    if (state?.version !== 1) return emptyStats();
    return normalizeStats(state.stats);
  } catch {
    return emptyStats();
  }
}

function normalizeStats(stats) {
  const result = emptyStats();
  for (const difficulty of Object.keys(result)) {
    const entry = stats?.[difficulty];
    if (!entry || !Number.isSafeInteger(entry.played) || entry.played < 0 ||
        !Number.isSafeInteger(entry.won) || entry.won < 0 || entry.won > entry.played ||
        !Number.isSafeInteger(entry.bestScore) || entry.bestScore < 0 ||
        !(entry.bestTime === null || (Number.isFinite(entry.bestTime) && entry.bestTime >= 0))) continue;
    result[difficulty] = {
      played: entry.played, won: entry.won,
      bestScore: entry.bestScore, bestTime: entry.bestTime,
    };
  }
  return result;
}

export function serializeState(game, stats = emptyStats()) {
  try {
    return JSON.stringify({ version: 1, game: validate(game), stats: normalizeStats(stats) }) + "\n";
  } catch {
    return JSON.stringify({ version: 1, game: null, stats: emptyStats() }) + "\n";
  }
}

async function loadText() {
  if (latestText !== undefined) return latestText;
  try {
    const text = await readTextFile(STATE_PATH);
    if (latestText !== undefined) return latestText;
    snapshot = text;
    return text;
  } catch (error) {
    console.error("Sudoku: could not load state", error);
    return latestText ?? null;
  }
}

export async function loadGame() {
  return parseState(await loadText());
}

export async function loadStats() {
  return parseStats(await loadText());
}

function refreshLatest(base) {
  latestText = serializeState(
    gameOverride === undefined ? parseState(base) : gameOverride,
    statsOverride === undefined ? parseStats(base) : statsOverride,
  );
}

export async function saveGame(game) {
  gameOverride = parseState(serializeState(game));
  refreshLatest(latestText ?? snapshot);
  await saveLatest();
}

export async function saveStats(stats) {
  statsOverride = normalizeStats(stats);
  refreshLatest(latestText ?? snapshot);
  await saveLatest();
}

async function saveLatest() {
  if (writeStarted !== null && Date.now() - writeStarted > 3000) {
    // Host promises may never settle after their originating View is torn down.
    generation++;
    queue = Promise.resolve();
    snapshot = undefined;
    writeStarted = null;
  }
  const currentGeneration = generation;
  queue = queue.then(async () => {
    if (currentGeneration !== generation) return;
    writeStarted = Date.now();
    try {
      if (!directoryReady) {
        const result = await exec("mkdir", ["-p", STATE_DIR]);
        if (result.code !== 0) throw new Error(`mkdir failed (${result.code}): ${result.stderr}`);
        if (currentGeneration !== generation) return;
        directoryReady = true;
      }
      let expected = snapshot;
      if (expected === undefined) expected = await readTextFile(STATE_PATH);
      if (currentGeneration !== generation) return;
      refreshLatest(expected);
      let text = latestText;
      try {
        await writeTextFile(STATE_PATH, text, expected);
      } catch {
        // An abandoned chain must not retry over a newer save.
        if (currentGeneration !== generation) return;
        expected = await readTextFile(STATE_PATH);
        if (currentGeneration !== generation) return;
        refreshLatest(expected);
        text = latestText;
        await writeTextFile(STATE_PATH, text, expected);
      }
      if (currentGeneration === generation) snapshot = text;
    } catch (error) {
      console.error("Sudoku: could not save state", error);
    } finally {
      if (currentGeneration === generation) writeStarted = null;
    }
  });
  await queue;
}
