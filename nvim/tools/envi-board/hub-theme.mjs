// Shared semantic colours. Keep ANSI usable when the hub is unavailable.
import { readFileSync, realpathSync, watch } from "node:fs";
import { dirname, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";

const TOKEN_PATHS = {
  bg: ["ui", "popover"],
  fg: ["ui", "fg"],
  fg_dim: ["ui", "fg_dim"],
  muted: ["ui", "muted"],
  faint: ["ui", "faint"],
  border: ["ui", "border"],
  surface: ["ui", "surface"],
  accent: ["ui", "accent"],
  accent_fg: ["ui", "accent_fg"],
  link: ["ui", "link"],
  title: ["ui", "title"],
  info: ["status", "info"],
  success: ["status", "success"],
  warning: ["status", "warning"],
  error: ["status", "error"],
  attention: ["status", "attention"],
  user_bubble: ["chat", "user_bubble"],
  code_bg: ["chat", "code_bg"],
  provider: ["chat", "provider"],
  diff_add: ["diff", "add_fg"],
  diff_del: ["diff", "del_fg"],
  syn_keyword: ["syntax", "keyword"],
  syn_flag: ["syntax", "flag"],
  syn_string: ["syntax", "string"],
  syn_number: ["syntax", "number"],
};
export const TOKEN_NAMES = Object.freeze(Object.keys(TOKEN_PATHS));

const ANSI = {
  bg: null,
  fg: undefined, // Ink inherits the terminal's default foreground.
  fg_dim: "white",
  muted: "white",
  faint: "white",
  border: "gray",
  surface: null,
  accent: "yellowBright",
  accent_fg: "black",
  link: "blueBright",
  title: "white",
  info: "blueBright",
  success: "greenBright",
  warning: "yellowBright",
  error: "redBright",
  attention: "magentaBright",
  user_bubble: null,
  code_bg: null,
  provider: "yellowBright",
  diff_add: "greenBright",
  diff_del: "redBright",
  syn_keyword: "magentaBright",
  syn_flag: "yellowBright",
  syn_string: "greenBright",
  syn_number: "blueBright",
};
const fallback = () => ({ id: "ansi", source: "ansi", tokens: { ...ANSI } });
const isHex = (value) =>
  typeof value === "string" && /^#[\da-f]{6}$/i.test(value);

function themeFile(opts) {
  return resolve(
    opts?.file ??
      process.env.ENVI_THEME_FILE ??
      resolve(
        dirname(realpathSync(fileURLToPath(import.meta.url))),
        "../../../theme/theme.json",
      ),
  );
}

/** Sync, all-or-nothing token resolution; no filesystem/JSON error escapes. */
export function loadTheme(opts) {
  try {
    const hub = JSON.parse(readFileSync(themeFile(opts), "utf8"));
    const id = opts?.id ?? process.env.ENVI_THEME ?? hub.active;
    if (typeof id !== "string" || !Object.hasOwn(hub.themes, id))
      return fallback();
    const theme = hub.themes[id];
    const colour = (value) => {
      if (typeof value !== "string") return undefined;
      const resolved = value.startsWith("#") ? value : theme.palette?.[value];
      return isHex(resolved) ? resolved : undefined;
    };
    const tokens = {};
    for (const [name, [group, key]] of Object.entries(TOKEN_PATHS)) {
      const value = colour(theme.tokens?.[group]?.[key]);
      if (!value) return fallback();
      tokens[name] = value;
    }
    // Extra hub roles (e.g. editor background) must also resolve, even if Ink
    // doesn't use them. Never silently accept a partially broken theme.
    for (const group of Object.values(theme.tokens)) {
      for (const value of Object.values(group))
        if (!colour(value)) return fallback();
    }
    return { id, source: "hub", tokens };
  } catch {
    return fallback();
  }
}

/** Watch the directory, not the inode: editors commonly save via rename.
 * Optional opts use the same file/id precedence as loadTheme (also for tests).
 * No initial callback; callers load once at startup. Returns an idempotent stop.
 */
export function watchTheme(onChange, opts) {
  let watcher;
  let timer;
  let stopped = false;
  const stop = () => {
    stopped = true;
    clearTimeout(timer);
    watcher?.close();
  };
  try {
    const file = themeFile(opts);
    const notify = () => {
      if (stopped) return;
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (stopped) return;
        try {
          onChange(loadTheme({ ...opts, file }));
        } catch {
          // A consumer callback must not crash the terminal client either.
        }
      }, 100);
      timer.unref();
    };
    watcher = watch(dirname(file), (_event, filename) => {
      if (filename == null || String(filename) === basename(file)) notify();
    });
    // Missing hub files are fine while the parent directory still exists.
    // An unavailable directory is a safe no-op watcher, not a startup failure.
    watcher.on("error", () => {
      notify();
      watcher.close();
    });
    watcher.unref();
  } catch {
    // Standalone clients may have no hub directory at all.
  }
  return stop;
}
