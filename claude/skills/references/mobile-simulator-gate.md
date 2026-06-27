# Mobile Simulator ATDD Gate — Operational Notes

The fifth ATDD gate class (visual / storybook / static / api /
**simulator**). Future sessions working on any project that drives
mobile UI through an iOS Simulator (Expo Go, native iOS app, React
Native app) will hit these patterns.

## When this gate applies

- ATDD scenario asserts a *mobile UI state* on iOS Simulator.
- The simulator is the only honest proof of native UI behavior.
  Web bundles and headless snapshots are NOT proof — they don't
  exercise the native module graph.
- `pnpm nx test`, jest, vitest, and Playwright can't reach a running
  iOS Simulator. The gate has to be driven by `computer_use` against
  cua-driver (or equivalent screenshotting tool) over the
  simulator window.

## cua-driver simulator capture — the three failure modes

In a verified-real session (casona-ai, 2026-06-25), `computer_use
action=capture mode=vision app=Simulator` returned `0×0` three
times before working. The three causes, in order of likelihood:

### 1. Stale daemon (most common)

**Symptom:** `width: 0, height: 0`, `app: ""`, no error.
**Cause:** cua-driver daemon has cached MCP capabilities and a
broken tool-discovery state. Permissions are green, simulator is
running, windows exist — but the bridge's `screenshot` fallback
errors with `Unknown tool: screenshot` and the `get_window_state`
fallthrough doesn't fire.
**Fix:**
```bash
/Applications/CuaDriver.app/Contents/MacOS/cua-driver stop
# restart daemon in background
/Applications/CuaDriver.app/Contents/MacOS/cua-driver serve &
sleep 3
/Applications/CuaDriver.app/Contents/MacOS/cua-driver status
```
Then retry `computer_use action=capture`. The capture should now
report `width > 0`, `app: "Simulator"`, `window_title: "iPad Pro
11-inch (M5) – iOS 26.2"` (or similar).

### 2. Multiple windows for the app, wrong one picked

**Symptom:** Captures succeed but return the title-bar chrome
(`height: 33, width: 1512`), not the visible content window.
**Cause:** cua-driver picks the first on-screen window matching
the app name. Simulator has 2-3 windows (title bar pieces + the
visible iPad window). The first match by z-order is often a chrome
window, not the display.
**Fix:** `get_window_state(pid, window_id)` with the specific
window_id of the visible display window. The Hermes `computer_use`
tool doesn't expose `window_id`; for that, drop down to
`cua-driver call get_window_state '{"pid": ..., "window_id": ...}'`.

To find the right window_id:
```bash
/Applications/CuaDriver.app/Contents/MacOS/cua-driver call list_windows '{}' \
  | python3 -c "import json,sys; [print(w['window_id'], w.get('bounds'), w.get('is_on_screen'), w.get('title')) for w in json.load(sys.stdin)['windows'] if w.get('app_name') == 'Simulator']"
```
The visible iPad display is the entry with `is_on_screen: True` and
`bounds.height > 100` (not the 33px title bar).

### 3. Permission revoked

**Symptom:** Same as #1 but `cua-driver permissions status` returns
`accessibility: false` or `screen_recording: false`.
**Fix:** Re-grant via System Settings → Privacy & Security, then
restart daemon (#1).

## Storybook-on-mobile: the `--web --clear` trap

**Symptom:** Metro bundles successfully. Web bundle serves
"Storybook UI" at `localhost:8081`. Expo Go on simulator gets
`exp://127.0.0.1:1XXXX` connection error.
**Cause:** `@nx/expo` plugin's `serve.impl.js` **hardcodes
`--web`** in the spawned `expo start` command:

```js
fork(...['start', '--web', ...createServeOptions(options)], ...)
```

So `pnpm nx serve @<scope>/<storybook-mobile-app>` ALWAYS serves the
web bundle via Metro, never the native bundle. Expo Go can't reach
it because Metro isn't listening on the native bundler port
(typically 19000).

**Fix (workaround, no nx patch):** Bypass nx. Call `expo start`
directly:

```bash
cd apps/storybook-expo
mkdir -p ../../.agent/recon/<app>/logs
npx expo start --clear > ../../.agent/recon/<app>/logs/expo-direct.log 2>&1 &
```

**Real fix (long-term):** File an issue upstream against nx
(`nrwl/nx` repo, `@nx/expo` package). The `--web` should be opt-in
via a plugin option, not the default.

## Storybook-on-mobile: the static-import-of-optional-peer trap

**Symptom:** Metro bundles fine. Storybook UI loads in web bundle.
On the simulator, Storybook crashes with
`SB_PREVIEW_API_0008 (EmptyIndexError)`. The error toast says
"Couldn't find any stories in your Storybook."
**Cause:** `packages/ui/src/provider/index.tsx` (or any module
re-exported via the package.json `exports` field) does
`import { useColorScheme } from 'nativewind'` at module top-level.
`apps/storybook-expo` doesn't have nativewind as a dep. Metro's
module resolution fails for the provider, storybook's
`storybook.requires.ts` walk bails, empty story index.
**Fix:** Decouple the UI package's provider from consumer-specific
deps via dynamic require + structural narrowing:

```typescript
function loadAppearance(): AppearanceLike | null {
  let rn: unknown;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    rn = require('react-native');
  } catch {
    return null;
  }
  if (!rn || typeof rn !== 'object') return null;
  const appearance = (rn as { Appearance?: unknown }).Appearance;
  if (
    appearance &&
    typeof appearance === 'object' &&
    typeof (appearance as AppearanceLike).addChangeListener === 'function'
  ) {
    return appearance as AppearanceLike;
  }
  return null;
}
```

`typed as unknown` + structural narrowing is the lint-clean way to
do this. ESLint flags raw `any` from `require()` (rules:
`no-unsafe-assignment`, `no-unsafe-member-access`).

## Storybook-react-native: `Exception in HostFunction: <unknown>`

**Symptom:** Storybook bootstrap works (storybook.requires.ts loads,
Expo Go deep-link succeeds, Metro serves the bundle). Storybook UI
renders, then `start({ annotations, storyEntries })` throws
`Exception in HostFunction: <unknown>`.
**Cause:** The preview.tsx decorator references a native module
that's not in the simulator's runtime graph. The actual exception
is in iOS-side React Native, not in JS.
**Fix path (NOT a one-shot fix):**
1. Check Metro's full error log — the `WARN storybook-log: error
   loading UI` line precedes the stack trace.
2. Open iOS Device Console: Window → Devices and Simulators →
   select iPad → Open Console.
3. Look for "RCTFatal" / "Unhandled JS Exception" with the actual
   error message (often a missing native module class).
4. The fix is usually: add the missing native dep to the consumer's
   `package.json`, OR change the preview decorator to not reference
   it.

## Process tracking — why `pkill -f "expo start"` lies

In an Nx + Expo setup, the process tree is:

```
pnpm nx serve @app
  └─ node /path/to/nx
       └─ node /path/to/expo/cli start --web --clear
              ├─ node metro (parent of bundler)
              └─ node expo-cli (peer)
```

`pkill -f "expo start"` only matches the second node, not the
forked metro child or the expo-cli peer. To clean up a serve:

```bash
# what to actually check
lsof -i:8081                      # who has port 8081?
ps -ef | grep -E "expo|metro|nx serve" | grep -v grep
# kill the right PIDs (the top-level pnpm process + the expo fork)
kill <pnpm-pid> <nx-pid> <expo-pid>
```

**Don't** rely on `pkill -f "expo"` alone — the forked metro child
will keep port 8081 held and the next serve attempt will fail with
"Port 8081 is running this app in another window."

## Computer_use output → vision analysis flow

When the gate needs to verify a UI state on the simulator:

1. `computer_use action=capture mode=vision app=Simulator` → returns
   PNG dimensions + a base64 PNG + (if everything works) SOM
   overlays.
2. The `vision_analysis` field in the response is auto-generated by
   `vision_analyze` on the captured PNG.
3. The agent's job: read the `vision_analysis` text and decide if
   the UI matches the scenario's Then-clause. If yes → scenario
   passes. If no → ATDD scenario fails, route to fix path.

This is the trust chain: `computer_use` (cua-driver) → `vision_analyze`
(auxiliary vision model) → agent judgment. Each link is fallible
(cua-driver stale, vision model misreads). The verification gate
should require BOTH a successful capture AND a sensible
vision_analysis, not just one.

## Recommended scenario template (mobile simulator)

```markdown
### Scenario 1: <App> launches on iOS Simulator and renders <screen>
- **Given:** An iPad Pro 11-inch (M5) simulator running iOS 26.2
  with Expo Go installed and the latest build of <App> loaded
- **When:** I tap the "<button>" element
- **Then:** The simulator shows <expected screen state>, verified
  via computer_use capture of the Simulator app

### Definition of Done (mobile simulator scenario)
- [ ] `computer_use action=capture app=Simulator` returns
      width > 0 + window_title containing the iPad model name
- [ ] `vision_analysis` describes the expected screen state
- [ ] No "Could not connect to the server" toast
- [ ] No SB_PREVIEW_API_0008 or other Storybook index errors
```

## What's still NOT solvable in this gate

- Render performance assertions (FPS, frame time) — `computer_use`
  is screen-grab; not fast enough for frame-by-frame capture.
- Touch interaction timing — `computer_use click` is async, no
  precise timing.
- Multi-touch gestures — `click` is single-point only.
- Deep links / URL schemes — use `xcrun simctl openurl booted
  "scheme://..."` instead of `computer_use`.

For those, drive the simulator via `xcrun simctl` commands
(recordVideo, spawn, ui, status_bar, push, openurl, terminate,
launch, getenv) directly. `computer_use` is the visual-verification
primitive; simctl is the action primitive. Pair them.

## Provenance

This gate was first exercised end-to-end against `casona-ai` on
2026-06-25 (Storybook Expo campaign). Outcomes:

- cua-driver stale-daemon fixed by restart (this session)
- ThemeProvider nativewind coupling fixed by dynamic require
- Storybook bootstrap wires up to Expo Go via deep link
- `--web --clear` trap bypassed by `npx expo start --clear` direct call
- `Exception in HostFunction` on render NOT YET fixed — deferred to
  follow-up session. Likely a peer-dep gap in the simulator's
  runtime graph for the preview decorator's native modules.

The mobile-simulator gate is the 5th ATDD gate class. `atdd` skill
§I-pitfall (visual / storybook / static / api) lists only the first
four — this reference extends the catalog with the simulator class
and the operational notes above.