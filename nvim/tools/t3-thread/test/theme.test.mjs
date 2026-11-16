import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, readFileSync, writeFileSync, renameSync, unlinkSync, rmSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { spawnSync } from "node:child_process";
import { TOKEN_NAMES, loadTheme, watchTheme } from "../theme.mjs";

const hubFile = fileURLToPath(new URL("../../../../theme/theme.json", import.meta.url));
const scratch = "/tmp/t3-rd1";
function fixture(t) {
  mkdirSync(scratch, { recursive: true });
  const dir = mkdtempSync(join(scratch, "theme-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = join(dir, "theme.json");
  const hub = JSON.parse(readFileSync(hubFile, "utf8"));
  hub.active = "gruvbox-dark"; // Fixtures choose their own theme, independent of the hub default.
  const save = () => writeFileSync(file, JSON.stringify(hub));
  save();
  return { dir, file, hub, save };
}
function env(t, values) {
  const previous = Object.fromEntries(Object.keys(values).map((key) => [key, process.env[key]]));
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
}
function fallback(result) {
  assert.equal(result.source, "ansi");
  assert.equal(result.id, "ansi");
  assert.deepEqual(Object.keys(result.tokens).sort(), [...TOKEN_NAMES].sort());
  assert.equal(result.tokens.fg, undefined);
  for (const key of ["bg", "surface", "user_bubble", "code_bg"]) assert.equal(result.tokens[key], null);
  assert.equal(result.tokens.accent, "yellowBright");
  assert.equal(result.tokens.accent_fg, "black");
  for (const key of ["muted", "faint", "fg_dim", "title"]) assert.equal(result.tokens[key], "white");
  assert.deepEqual(Object.keys(result.tokens).filter((key) => result.tokens[key] === "gray"), ["border"]);
  assert.equal(result.tokens.error, "redBright");
}

test("hub resolves every token for both themes and uses the binding gruvbox values", (t) => {
  env(t, { ENVI_THEME_FILE: undefined, ENVI_THEME: undefined });
  const expected = {
    bg: "#282828", fg: "#ebdbb2", fg_dim: "#bdae93", muted: "#a89984", faint: "#928374",
    border: "#504945", surface: "#3c3836", accent: "#fe8019", accent_fg: "#1d2021", link: "#83a598",
    title: "#a89984", info: "#83a598", success: "#b8bb26", warning: "#fabd2f", error: "#fb4934",
    attention: "#d3869b", user_bubble: "#504945", code_bg: "#3c3836", provider: "#fe8019",
    diff_add: "#b8bb26", diff_del: "#fb4934", syn_keyword: "#d3869b", syn_flag: "#fe8019",
    syn_string: "#b8bb26", syn_number: "#83a598",
  };
  assert.deepEqual(loadTheme({ id: "gruvbox-dark" }).tokens, expected);
  for (const id of ["gruvbox-dark", "nord"]) {
    const theme = loadTheme({ id });
    assert.equal(theme.source, "hub");
    assert.equal(theme.id, id);
    assert.deepEqual(Object.keys(theme.tokens).sort(), [...TOKEN_NAMES].sort());
    for (const value of Object.values(theme.tokens)) assert.match(value, /^#[\da-f]{6}$/i);
  }
  const hub = JSON.parse(readFileSync(hubFile, "utf8"));
  const keys = (theme) => Object.entries(theme.tokens).flatMap(([group, values]) =>
    Object.keys(values).map((key) => `${group}.${key}`)).sort();
  assert.deepEqual(keys(hub.themes.nord), keys(hub.themes["gruvbox-dark"]));
  for (const theme of Object.values(hub.themes)) {
    assert.equal(theme.ansi.length, 16);
    for (const value of theme.ansi) assert.match(value, /^#[\da-f]{6}$/i);
    assert.equal(theme.consumers.nvim.background, "dark");
    assert.equal(typeof theme.consumers.nvim.scheme, "string");
  }
  const nord = loadTheme({ id: "nord" }).tokens;
  assert.equal(nord.bg.toLowerCase(), "#2e3440");
  assert.equal(nord.surface.toLowerCase(), "#3b4252");
  assert.equal(nord.user_bubble.toLowerCase(), "#434c5e");
});

test("default is nord", (t) => {
  env(t, { ENVI_THEME_FILE: undefined, ENVI_THEME: undefined });
  assert.equal(loadTheme().id, "nord");
});

function luminance(hex) {
  const rgb = hex.slice(1).match(/../g).map((value) => parseInt(value, 16) / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return rgb.reduce((sum, value, i) => sum + value * [0.2126, 0.7152, 0.0722][i], 0);
}

test("Nord roles match Nordic reduced-blue colours and accessible faint mix", (t) => {
  env(t, { ENVI_THEME_FILE: undefined, ENVI_THEME: undefined });
  const nord = loadTheme({ id: "nord" });
  assert.equal(nord.source, "hub");
  assert.deepEqual(nord.tokens, {
    bg: "#2e3440", fg: "#c0c8d8", fg_dim: "#aab2c1", muted: "#9aa3b5", faint: "#6e7f96",
    border: "#434c5e", surface: "#3b4252", accent: "#d08770", accent_fg: "#191d24", link: "#88c0d0",
    title: "#9aa3b5", info: "#81a1c1", success: "#a3be8c", warning: "#ebcb8b", error: "#bf616a",
    attention: "#b48ead", user_bubble: "#434c5e", code_bg: "#3b4252", provider: "#d08770",
    diff_add: "#a3be8c", diff_del: "#bf616a", syn_keyword: "#b48ead", syn_flag: "#d08770",
    syn_string: "#a3be8c", syn_number: "#81a1c1",
  });
  assert.ok(luminance(nord.tokens.fg_dim) < luminance(nord.tokens.fg));
  assert.ok((luminance(nord.tokens.faint) + 0.05) / (luminance(nord.tokens.bg) + 0.05) >= 3);
  const theme = JSON.parse(readFileSync(hubFile, "utf8")).themes.nord;
  // Snapshot of installed nordic.nvim/lua/nordic/colors/nordic.lua. Only the
  // binding muted colour and documented faint/output mixes extend that palette.
  const native = {
    black0: "#191d24", black1: "#1e222a", black2: "#222630",
    gray0: "#242933", gray1: "#2e3440", gray2: "#3b4252", gray3: "#434c5e", gray4: "#4c566a", gray5: "#60728a",
    white0_normal: "#bbc3d4", white0_reduce_blue: "#c0c8d8", white1: "#d8dee9", white2: "#e5e9f0", white3: "#eceff4",
    blue0: "#5e81ac", blue1: "#81a1c1", blue2: "#88c0d0",
    cyan: "#8fbcbb", cyan_bright: "#9fc6c5", cyan_dim: "#80b3b2",
    red: "#bf616a", red_bright: "#c5727a", red_dim: "#b74e58",
    orange: "#d08770", orange_bright: "#d79784", orange_dim: "#cb775d",
    yellow: "#ebcb8b", yellow_bright: "#efd49f", yellow_dim: "#e7c173",
    green: "#a3be8c", green_bright: "#b1c89d", green_dim: "#97b67c",
    magenta: "#b48ead", magenta_bright: "#be9db8", magenta_dim: "#a97ea1",
  };
  assert.deepEqual(theme.palette, { ...native, muted: "#9aa3b5", faint: "#6e7f96", fg_dim: "#aab2c1" });
  assert.equal(theme.tokens.ui.bg, "gray0");
  assert.equal(theme.tokens.ui.fg, "white0_reduce_blue");
  assert.equal(theme.tokens.ui.fg_dim, "fg_dim");
  assert.deepEqual(theme.ansi, [
    "black0", "red", "green", "yellow", "blue0", "magenta", "cyan", "white0_reduce_blue",
    "gray2", "red_bright", "green_bright", "yellow_bright", "blue2", "magenta_bright", "cyan_bright", "white1",
  ].map((name) => theme.palette[name]));
  for (const group of Object.values(theme.tokens)) {
    for (const value of Object.values(group)) assert.ok(Object.hasOwn(theme.palette, value));
  }
});

test("command output is at least 15 percent toward the popover from foreground", (t) => {
  env(t, { ENVI_THEME_FILE: undefined, ENVI_THEME: undefined });
  const channels = (hex) => hex.slice(1).match(/../g).map((value) => parseInt(value, 16));
  for (const id of ["nord", "gruvbox-dark"]) {
    const { fg, fg_dim, bg } = loadTheme({ id }).tokens;
    const foreground = channels(fg), output = channels(fg_dim), background = channels(bg);
    for (let i = 0; i < 3; i++) {
      assert.ok(output[i] <= Math.round(foreground[i] * 0.85 + background[i] * 0.15), `${id} output channel ${i}`);
    }
  }
});

test("environment selects file and id; explicit options win", (t) => {
  const { file, hub, save } = fixture(t);
  hub.active = "nord";
  save();
  env(t, { ENVI_THEME_FILE: file, ENVI_THEME: undefined });
  assert.equal(loadTheme().id, "nord");
  process.env.ENVI_THEME = "gruvbox-dark";
  assert.equal(loadTheme().id, "gruvbox-dark");
  assert.equal(loadTheme({ id: "nord" }).id, "nord");
  assert.equal(loadTheme({ file: hubFile, id: "gruvbox-dark" }).tokens.bg, "#282828");
  process.env.ENVI_THEME_FILE = "/tmp/t3-rd1/absent-hub";
  assert.equal(loadTheme({ file: hubFile, id: "nord" }).source, "hub");
});

for (const [name, mutate] of Object.entries({
  "missing file": ({ file }) => unlinkSync(file),
  "bad JSON": ({ file }) => writeFileSync(file, "{"),
  "unknown active id": ({ hub }) => { hub.active = "missing"; },
  "unresolved palette name": ({ hub }) => { hub.themes[hub.active].tokens.ui.fg = "missing"; },
  "non-hex literal": ({ hub }) => { hub.themes[hub.active].tokens.ui.fg = "rgb(255, 0, 0)"; },
  "short hex literal": ({ hub }) => { hub.themes[hub.active].tokens.ui.fg = "#fff"; },
  "invalid palette hex": ({ hub }) => { hub.themes[hub.active].palette.fg1 = "#zzzzzz"; },
  "missing token": ({ hub }) => { delete hub.themes[hub.active].tokens.ui.title; },
  "null token": ({ hub }) => { hub.themes[hub.active].tokens.ui.fg = null; },
  "missing group": ({ hub }) => { delete hub.themes[hub.active].tokens.syntax; },
  "bad structure": ({ file }) => writeFileSync(file, "null"),
})) {
  test(`${name} falls back for the whole theme`, (t) => {
    env(t, { ENVI_THEME: undefined });
    const f = fixture(t);
    mutate(f);
    if (!["missing file", "bad JSON", "bad structure"].includes(name)) f.save();
    fallback(loadTheme({ file: f.file }));
  });
}

test("unknown explicit id and invalid options never throw", (t) => {
  env(t, { ENVI_THEME_FILE: undefined, ENVI_THEME: undefined });
  fallback(loadTheme({ id: "missing" }));
  fallback(loadTheme({ file: 42 }));
  assert.doesNotThrow(() => loadTheme(null));
  assert.doesNotThrow(() => watchTheme(null, { file: 42 })());
});

test("literal hex is accepted and returned theme tokens are independent", (t) => {
  env(t, { ENVI_THEME: undefined });
  const { file, hub, save } = fixture(t);
  hub.themes[hub.active].tokens.ui.fg = "#ABCDEF";
  save();
  assert.equal(loadTheme({ file }).tokens.fg, "#ABCDEF");
  const broken = loadTheme({ file: "/tmp/t3-rd1/absent-hub" });
  broken.tokens.error = "black";
  fallback(loadTheme({ file: "/tmp/t3-rd1/absent-hub" }));
});

async function nextTheme(events, predicate) {
  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    const found = events.find(predicate);
    if (found) return found;
    await delay(20);
  }
  assert.fail(`theme watch timed out: ${JSON.stringify(events)}`);
}
for (const viaEnv of [false, true]) {
  test(`watch handles atomic rename, disappearance, recovery and stop (${viaEnv ? "env" : "opts"})`, async (t) => {
    const { file, dir, hub } = fixture(t);
    env(t, { ENVI_THEME_FILE: viaEnv ? file : undefined, ENVI_THEME: undefined });
    const events = [];
    const stop = watchTheme((theme) => events.push(theme), viaEnv ? undefined : { file });
    t.after(stop);
    const replace = (active) => {
      hub.active = active;
      const temp = join(dir, "next.json");
      writeFileSync(temp, JSON.stringify(hub));
      renameSync(temp, file);
    };
    replace("nord");
    replace("gruvbox-dark");
    replace("nord");
    assert.equal((await nextTheme(events, (x) => x.id === "nord")).source, "hub");
    await delay(180);
    assert.equal(events.length, 1, "rename burst is debounced");
    unlinkSync(file);
    await nextTheme(events, (x) => x.source === "ansi");
    replace("gruvbox-dark");
    await nextTheme(events, (x) => x.id === "gruvbox-dark");
    // Stop also cancels a pending debounce callback.
    replace("nord");
    stop();
    stop();
    const count = events.length;
    await delay(250);
    assert.equal(events.length, count);
  });
}

test("watch can start with a missing hub and does not retain the process", async (t) => {
  const { file, save } = fixture(t);
  env(t, { ENVI_THEME: undefined });
  unlinkSync(file);
  const events = [];
  const stop = watchTheme((value) => events.push(value), { file });
  t.after(stop);
  save();
  await nextTheme(events, (x) => x.source === "hub");
  const module = new URL("../theme.mjs", import.meta.url).href;
  const child = spawnSync(process.execPath, ["--input-type=module", "-e",
    `import {watchTheme} from ${JSON.stringify(module)}; watchTheme(() => {}, {file: ${JSON.stringify(file)}});`],
    { timeout: 2000, encoding: "utf8" });
  assert.equal(child.error, undefined);
  assert.equal(child.status, 0, child.stderr);
});
