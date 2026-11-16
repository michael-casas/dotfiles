import { open } from "node:fs/promises";
import { constants, watch as watchDir } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { parseBoard, LIMITS } from "./document.mjs";
import { loadTheme, watchTheme } from "./hub-theme.mjs";

export async function readBoard(path) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > LIMITS.document)
      throw Error("not a bounded regular file");
    const bytes = Buffer.alloc(LIMITS.document + 1);
    let length = 0;
    while (length < bytes.length) {
      const r = await handle.read(bytes, length, bytes.length - length, null);
      if (!r.bytesRead) break;
      length += r.bytesRead;
    }
    return parseBoard(bytes.subarray(0, length));
  } finally {
    await handle.close();
  }
}

/** Sole owner of file reads, generation ordering, last-good and watch cleanup. */
export class BoardSession {
  constructor({ path, themeOptions } = {}) {
    this.path = resolve(path);
    this.themeOptions = themeOptions;
    this.theme = loadTheme(themeOptions);
    this.listeners = new Set();
    this.closed = false;
    this.generation = 0;
    this.request = 0;
    this.snapshot = null;
  }
  subscribe(fn) {
    this.listeners.add(fn);
    if (this.snapshot) fn(this.snapshot);
    return () => this.listeners.delete(fn);
  }
  publish(snapshot) {
    if (this.closed) return;
    this.snapshot = snapshot;
    for (const fn of this.listeners) fn(snapshot);
  }
  async refresh() {
    if (this.closed) return;
    const request = ++this.request;
    let document,
      error = null;
    try {
      document = await readBoard(this.path);
    } catch {
      error =
        "Board unavailable (missing, unreadable or not a bounded regular file)";
    }
    if (this.closed || request !== this.request) return;
    const invalid = error || !document.valid;
    if (
      !invalid &&
      this.snapshot?.document?.hash === document.hash &&
      !this.snapshot.stale &&
      this.snapshot.watchError === (this.watchError ?? null)
    )
      return;
    if (document?.valid) this.lastGood = document;
    this.publish({
      path: this.path,
      generation: ++this.generation,
      document: invalid ? (this.lastGood ?? document ?? null) : document,
      stale: !!invalid,
      error:
        error ??
        (invalid
          ? "Invalid board; showing last good snapshot or literal source"
          : null),
      diagnostics: document?.diagnostics ?? [],
      theme: this.theme,
      watchError: this.watchError ?? null,
    });
  }
  start() {
    if (this.started || this.closed) return;
    this.started = true;
    this.stopTheme = watchTheme((theme) => {
      this.theme = theme;
      if (this.snapshot) this.publish({ ...this.snapshot, theme });
    }, this.themeOptions);
    this.attachWatch();
    void this.refresh();
  }
  attachWatch() {
    if (this.closed) return;
    try {
      this.watcher = watchDir(dirname(this.path), (_event, file) => {
        if (file == null || String(file) === basename(this.path)) {
          clearTimeout(this.debounce);
          this.debounce = setTimeout(() => void this.refresh(), 100);
          this.debounce.unref();
        }
      });
      this.watcher.on("error", () => {
        this.watcher?.close();
        this.watchError = "Watch unavailable; use R to refresh";
        if (this.snapshot)
          this.publish({
            ...this.snapshot,
            generation: ++this.generation,
            watchError: this.watchError,
          });
        else void this.refresh();
      });
      this.watcher.unref();
      this.watchError = null;
    } catch {
      this.watchError = "Watch unavailable; use R to refresh";
    }
  }
  retry() {
    if (this.watchError) {
      this.watcher?.close();
      this.attachWatch();
    }
    return this.refresh();
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    this.request++;
    clearTimeout(this.debounce);
    this.watcher?.close();
    this.stopTheme?.();
    this.listeners.clear();
  }
}
