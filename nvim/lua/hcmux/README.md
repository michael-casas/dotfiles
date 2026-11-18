# hcmux: nvim as a multiplexer on herdr-core

Terminal buffers in nvim are **views** onto herdr-core (`hc`) terminals. The
programs (shells, Claude, Codex, pi, …) run in herdr-core, not in nvim.

- Closing a buffer, closing a window or quitting nvim leaves them running.
- Reopening nvim in the same folder brings the whole layout back from its
  herdr-core session (see Sessions). Terminals attach when shown and replay
  2000 lines of scrollback.
- Each viewer runs `/bin/sh -c "printf '\033%s' 7; exec \"$@\"" hcmux-viewer hc attach --history N <t>`.
  `hc attach` opens with `ESC[?1049l`, which also restores the saved cursor; Neovim's terminal
  restores a never-saved cursor with an explicit black pen, so blank rows and the rest of each
  line stayed black (the "black bars" in T3 scrollback). The prelude saves a clean cursor first,
  then execs hc: same pid and exit status, arguments only as `"$@"`.
- nvim windows and tabs are the layout. herdr-core keeps the processes and
  their agent status (OSC 7501), streamed live through `hc events`.
- In the Herdr app, they appear as **sub-agents of nvim's tab**: the app shows
  their status and can peek at them, but adds no panes.

The AI session manager (`plugins/opencode.lua`: `:AI`, `<leader>ha`,
`:Claude`, …) opens every agent this way. Its session pickers tag a session
`[RUN]` when it is still alive in herdr-core, and selecting it re-attaches
rather than starting a second copy.

## Keys

The prefix `<C-\>` works in **normal and terminal mode**, so you can drive the
layout without leaving a terminal. `<leader>m` repeats the same keys in normal
mode and has which-key labels.

| Key | Action |
|---|---|
| `c` / `v` / `s` / `t` | new shell: here / vsplit / split / tab |
| `w` | pick any herdr-core terminal (live preview; `<c-v>` `<c-s>` `<c-t>` open, `<c-x>` kill, `<a-r>` rename) |
| `n` / `p` | next / previous terminal in this window |
| `h` `j` `k` `l` | move between windows (`H J K L` move the window) |
| `z` | zoom the window |
| `=` / `o` / `q` | equalize / only this window / close window |
| `d` | detach: close the view, keep the program running |
| `x` | kill the program (asks first) |
| `r` | rename (stored as a label, so every nvim sees it) |
| `a` | AI tool selector |
| `R` | list this session's terminals as buffers again |
| `<leader>m>` | send the line (normal) or the selection (visual) to the last terminal |

`<C-\><C-n>` is still nvim's own "leave terminal mode". A lone `ctrl+\` that
times out reaches `hc attach` and detaches. That is harmless: the buffer
closes and the program keeps running.

LazyVim's `<leader>bd` and `:bd!` also only detach.

In the **T3 layout**, INSERT `Esc` dismisses a client overlay first; otherwise it
shows/focuses the thread bar in NORMAL on the currently open thread's card title.
`Ctrl-]` still enters COMMAND in place for native scroll/select. Bar `Enter`/`o`
or a left-click release on any card line opens/focuses its main terminal in INSERT;
clicking project/Settled headers toggles them. Blank space does nothing; native
bar drag selection/wheel and main-terminal mouse handling remain unchanged.
Popover Esc retains dismiss → COMMAND behavior. See the
[T3 client guide](../../tools/t3-thread/README.md#keys) for overlay acknowledgements,
question resume and the safe old-client timeout fallback.

## Commands

`:Hc` (picker), `:Hc new|split|vsplit|tab [cmd…]`, `:Hc attach <t>`,
`:Hc detach`, `:Hc kill[!] [t]` (`!` skips the prompt), `:Hc rename [title]`,
`:Hc restore [all]`, `:[range]Hc send [text]`.

## Lifecycle

| Event | Result |
|---|---|
| program exits 0 or is killed | view closes, `hc rm` removes the record |
| program exits non-zero | view stays open so the error can be read |
| detach (`d`, `:bd!`, ctrl+\) | view closes, program keeps running |
| nvim quits | every view ends, every program keeps running |
| nvim attaches to a session | its layout returns with the terminals live; its other terminals are listed as buffers |

## Sessions (`session.lua`)

herdr-core is the single source of session truth. A session is a core
document, `nvs.<name>`, holding nvim's layout (tabs, splits, sizes, buffers,
cursors, folds), plus the terminals labelled `herdr.nvs=<name>`.

| You do | What happens |
|---|---|
| `nvim` or `nvim <dir>` | attaches to that folder's session (its git root), or creates it |
| `nvim-session attach api` (or `nvim-session api`) | attaches to session `api`, starting in its folder |
| `nvim <file>` | plain editor, no session: safe as `$EDITOR` and for git commits |
| edit, split, open tabs, start terminals, delete buffers (including Snacks/LazyVim “delete other buffers”) | saved automatically, 1.5 s after things settle; idle/focus loss also schedules a save |
| `:detach` or `:qd` (also `:Detach`, `<leader>qd`, `:qa`, `:q` on the last window) | **detach**: the layout is saved, the terminals keep running |
| `:reload` (also `:Reload`), in an nvim started by `envi` | **reload**: detach, then the `envi` launcher starts nvim again on the same session, so config changes take effect |
| graceful quit, SIGHUP or SIGTERM | final synchronous save, waiting up to 10 s for an in-flight save callback first |
| crash, SIGKILL or power loss | only the last completed save survives; changes inside the debounce/write window can be lost |

All of vim's own quit commands keep their meaning: `:q` closes a window (the
last one detaches), and `:wq`, `:qa!` work as usual. `:detach` and `:qd` are the
explicit way to leave a session from anywhere.

- **Two nvims on one session:** the second one says so, shows
  `(read-only)` in the statusline and doesn't save. `:Session take`
  (`<leader>qt`) moves the session to it. The core refuses any save based on
  an old version, so the first nvim then shows `(not saving)`, never
  overwriting. Both states re-warn on buffer/layout activity, at most once a
  minute, with `:Session take` as the recovery command. Even `:Session save`
  does not bypass ownership. `:Session reload` loads the newer layout.
- **Reload/exit and swap files:** `envi` records the actual Neovim server PID
  before config loads (the TUI frontend can have a different PID). After the
  frontend returns, the launcher waits for that server to exit before reloading
  or returning to the shell after `:Detach`. A wait prints a notice; after 30 s
  it refuses to launch another editor rather than racing the old swaps. Wait
  for the old server to finish, then run `envi` again. `ENVI_EXIT_TIMEOUT=1..120`
  adjusts this bound in seconds. The launcher never kills the server or removes
  its swap files. The exit barrier applies to all editors started by `envi`;
  direct `nvim`/`nvim-session` launches have no launcher barrier.
- **Stale swaps after hostname changes:** macOS DHCP can change the hostname
  recorded in an old swap. Neovim's automatic clean-swap removal requires a
  matching hostname, so even a clean dead swap can prompt after each reload.
  Session setup removes it only when it is in a configured absolute swap
  directory inside this profile's local state, has **no unsaved changes**, and
  its owner is absent (`pid=0` or a local ESRCH probe). It chooses deletion via
  `SwapExists` and prints one INFO notice: “removed stale swap for <file> (no
  unsaved changes)”. Dirty swaps retain Neovim's normal recovery behavior;
  project-relative swaps (`directory=.` / `./swap`), directories outside profile
  state and unprobeable owners never qualify for this cleanup. Hostname alone
  is not used to decide ownership. Pinning a stable macOS hostname with
  `sudo scutil --set HostName <stable-name>` can prevent DHCP drift; that is an
  optional user/admin decision, not something envi changes.
- **Live owners keep upstream behavior:** other cases chain to Neovim's
  installed default swap handler unchanged. On Neovim 0.11, a running same-user
  writer selects Edit and emits **W325**; this is upstream policy, not a new
  prompt or a session takeover. A second editor's read-only *session* status
  protects the stored layout, not file contents. No live-owner swaps are deleted.
  This also applies during `silent!` layout source or deferred buffer entry.
  `test/run-lua.sh session-swap` under `nvim/tools/t3-thread` checks private real
  swaps, hostname drift, recovery, delayed server exit and upstream live-owner
  behavior using an in-memory RPC UI; it never contacts herdr-core or the desktop.
- **Recover a stale session:** in the editor whose current buffers/layout you
  want to keep, run `:Session take`. This deliberately replaces the stored
  layout, not file contents. Do not reload first if your cleaned-up layout is
  the one you want. Failed takes warn rather than reporting success.
- **Holder identity:** new saves include a hashed stable machine identity
  (macOS platform UUID, Linux machine-id, otherwise a private cached state ID).
  A network hostname change no longer makes a local holder foreign. Live or
  unprobeable local pids stay protected; an identified different machine stays
  read-only until explicitly taken. Legacy host-only holders are reclaimed only
  when the pid is provably absent locally; machine-qualified remote terminal
  addresses stay protected. A host-only remote writer cannot be distinguished
  from an old local hostname: upgrade all writers before sharing a core across
  machines, or use explicit take/reload coordination.
- **What is saved:** the Vim session layout, not unsaved file contents. Deleting
  the final named buffer intentionally saves an empty editor; an empty startup
  does not replace a prior layout, and an all-excluded (e.g. T3-only) layout
  still never replaces the saved editor tabs. Unchanged serialized layouts do
  not generate repeated document writes. A failed layout load clears its
  temporary loading flags so later saves are not permanently disabled.
- **Session commands:** `:Session list|attach <name>|rename <new>|save|take|reload|kill [name]`.
  `<leader>qs` opens the session picker (`⏎` switches, `<c-x>` ends one).
  `<leader>qr` renames.
- **Shell commands:** `nvim-session ls` lists sessions;
  `nvim-session kill <name> [-f]` ends one and its terminals.
- **Plain `:terminal` buffers and side panels** (neo-tree) aren't brought
  back. Use hcmux terminals for anything that should survive.
- **Undo history, registers and marks** come back as usual through nvim's own
  `undofile` and shada.
- **Names:** default names are the folder's basename. A second folder with
  the same basename (another worktree, say) gets `name-xxxx`.

`session-bridge.lua` is what makes layouts bring terminals back: it teaches
nvim the `hc://` buffer scheme (`BufReadCmd`), so a saved layout's terminal
windows re-attach to the live programs. It works for any `:mksession` file.
persistence.nvim is disabled and auto-session removed. Set `session = false`
in the plugin spec to turn all of this off.

## Hot reload on commit (`hotreload.lua`)

Every nvim started by `envi` watches the git checkout its config comes from
(the git dir's `logs/HEAD`, plus a check on `FocusGained`). When a new commit
changes files under the config dir, it reloads itself with `:reload`.

- **Ignored:** commits that only touch `*.md`, or files outside the config dir.
- **When:** it waits until the editor is safe to restart: normal mode, no unsaved
  buffers, and no key pressed for 3 s. It waits while you type in INSERT or in a
  T3 popover (TERMINAL). With unsaved buffers it says so once and keeps waiting.
- **Notices:** you see "commit abc1234 changed N config file(s); reloading when
  idle", then "reloaded for commit abc1234" in the new nvim.
- **Scope:** an nvim not started by `envi` can't restart itself, so it only
  reports the new commit. T3 TUI clients keep running their old code; use
  `:T3Restart` for those.
- **Commands:** `:EnviHotReload on|off|status`. `ENVI_HOT_RELOAD_ROOT=<dir>`
  watches another config dir (used for testing). Headless test:
  `test/hotreload.lua`.

## Labels

Terminals started from nvim carry these labels:

- `herdr.nvim=1`
- `herdr.nvim.cwd=<nvim's cwd>`
- `herdr.nvs=<session>`: the session it belongs to
- `herdr.nvim.title`
- for agents: `herdr.nvim.tool` and `herdr.nvim.session`

They also get `--parent $HC_TERMINAL_ID --outlive-parent`. Outside herdr they
get `--no-parent`. They always get `--no-notify`, so hc never types notes into
nvim.

```sh
hc ls --label herdr.nvim=1          # what nvim started
hc attach <t>                       # take one over from any shell
```

## Files

`core.lua` covers the hc CLI and the event cache. `term.lua` covers buffers and
their lifecycle. `picker.lua` is the snacks picker. `session.lua` keeps sessions in herdr-core, with `session_cli.lua` and `nvim/bin/nvim-session` as its shell side. `session-bridge.lua` handles the `hc://` scheme. `init.lua` holds setup,
`:Hc`, keys and the statusline. `plugins/hcmux.lua` holds the lazy spec and the
lualine component.

## envi layouts (`hcmux.layout`)

`pick()` offers `nvim` / `T3`; `go(name)` switches their persistent tab pages.
`open_thread(id)` goes to T3 and attaches that thread in its main window;
`sidebar_toggle()` toggles its left, approximately 36-column split (outside T3
it only notifies). The main window/client/cursor persist; hiding the sidebar
widens the main window, and showing it restores the split width. No global or
leader maps are installed here.

The catalogue sidebar puts pinned cards first, then projects (current repository
first), with stable two-letter coloured badges and disclosure chevrons. Within
a project, active threads and unseen completions lead, then newest activity.
`Enter` / `o` on a project header collapses it: its green done count remains,
along with the selected/working threads. On a thread's title or branch line,
those keys attach and focus its client. The bar's NORMAL-mode keys are buffer-local:

| Key | Action |
|---|---|
| `j` / `k` (with counts, e.g. `3j`) | Next / previous visible distinct thread card; land on its title, skip metadata/headers/blanks, clamp without wrapping; never open/attach |
| `gg` / `G`, mouse | Native row navigation; reach disclosure headers |
| `Enter` / `o` | Open thread in the T3 layout's main client; on a project/Settled header, toggle disclosure |
| `/` | Search full thread titles across all projects, including collapsed and settled cards; exclude archived/unlisted threads |
| Search `Enter` / `Esc` | Open hit through `layout.open_thread`, move bar cursor to its visible title / cancel without changing bar cursor or main client |
| `R` | Refresh the shared feed |

From a card's secondary line, `j/k` step relative to that card, not to its
own title. From a header/blank, they choose the next card below / previous card
above. Collapsed groups' existing selected/working exceptions remain visible
and participate; hidden cards do not. Feed re-renders retain the cursor's card
id and exact subrow key when available. No global or leader keys are added.

Title search uses the already-installed Snacks picker: case-insensitive fuzzy
matching of untruncated snapshot titles only, with project and age context
from the shared presentation helpers. There is no client preview or attach on
highlight; Esc closes from INSERT or NORMAL and returns to the sidebar. The
candidate list is a snapshot at picker-open time; reopen for newer feed data.
`search_items()` provides UI-independent candidates for headless checks.

The bottom `Settled {count}` disclosure reveals settled threads locally; no
server state is changed. Unread titles are bold; selection covers both lines.
Branches/worktrees use a muted second line. Status stays right-aligned at the
sidebar width. `harness` from the feed selects Claude `✳` (orange), Pi `π`
(yellow), or Codex `` (muted); absent metadata uses the prior model fallback,
with a neutral diamond for ambiguous/unknown models. The feed has no draft field,
so no gold pencil is invented. Working is blue like the T3 desktop, through the
single `EnviT3Side_working` highlight (`working = resolve(t.tokens.status.info)`).
Attention/error remain red, done green,
idle muted. Catalogue badge colours, unread foreground and selection background
use its sampled values; status colours retain the theme hub and sane fallbacks.

The asynchronous NDJSON feed starts on first T3 open and stops at `VimLeavePre`;
errors occupy one sidebar line, keeping the last snapshot. The fixture is initial
content until live data arrives. On buffer creation it emits
`User EnviT3Sidebar` with `ev.data.buf`, so keybinder can install local maps; only
once per created buffer, not on render/reuse. Showing the split uses a non-entering
window open, preserving the main terminal's COMMAND/INSERT mode. Main gutters
stay off; a closed/misidentified main window is recreated to the sidebar's right.

`t3.attach_in(win, id)` reuses a live client by deterministic name or
`t3.thread` label, or starts it at that window's size. Switching drops the old
hidden viewer, never its core client; viewers still shown elsewhere are left
alone. COMMAND/INSERT maps remain the popover's maps. COMMAND `q` checks the
**current window's** `envi_t3_main` flag at keypress time and does nothing there;
the same buffer shown in the popover still hides that float with `q`. INSERT
`q` remains text. There is no buffer-map swapping on window transitions.

### T3 geometry check (`t3layout.lua`)

`:T3Recenter` immediately checks the **current T3 window** and emits one result,
e.g. `T3: 197×53 ok; client checked` or
`T3: re-applied 197×53 (was 180×53); client checked; client reflowed`.
No keymap is installed. Automatic checks are silent and trail attach/popover
open, focus return, `WinResized`/`VimResized` and sidebar show/hide by 150 ms.
There is no repeating timer, restart, temporary width or text-position heuristic.

**Ownership: most recently focused viewer wins.** Only the current window in
an editor that has not received `FocusLost` can run a check. Leaving its
window/buffer, losing editor focus or changing its geometry invalidates pending
async reads/replies. Hidden/background views never assert their sizes through
this loop. A shared client has one width, not independent layouts per viewer;
passive views can therefore show wrapping for the controlling view's width.
Existing hc/Neovim automatic resize behavior remains; other integrations that
ignore focus are not made read-only by this module.

The check measures usable cells (`getwininfo().textoff` is subtracted; layout
main disables number, sign, fold and status-column gutters). It asynchronously
runs `hc get <address> --json` with a 1 s deadline. A mismatch resends those
**real** dimensions with `jobresize(terminal_job_id, cols, rows)` to the
`hc attach` PTY created by `term.lua`. Each attempt has one delayed confirmation;
at most two resize attempts run per settle. No signal or size sequence is sent
to the client program. Same-size `jobresize` may not send SIGWINCH; when another
viewer owns the core width, hc restores this viewer's cached dimensions on its
next input, which is the following harmless private layout-check action.

The client receives `ESC[>777;9;<id>u`, with a fresh decimal id in 1..999999999.
Its fixed reply is
`ESC]7503;envi-t3-layout=<id>;cols=<C>;rows=<R>;frozen=<F>;reflowed=<0|1>ESC\\`.
The `TermRequest` handler accepts Neovim's stripped terminator and correlates
buffer, request, invoker window and unchanged geometry. A reply reports whether
this request reflowed history. If the core had not converged before action 9,
one final read confirms the input-driven ownership handoff (never another
resize). Missing replies time out after 1 s: no retry, restart or automatic
notification; the manual result says `client did not answer (older client)`.
PTY read errors and nonconvergence are reported honestly by the manual command.
Client-width disagreements and PTY failures append dimensions/request ids only
to `stdpath("state")/hcmux/t3-layout.log`, never terminal contents or server errors.
Client action 9/history reflow lives in `tools/t3-thread`, separately from this
Neovim check; old clients still benefit from the PTY handoff.

**After a history rebuild:** Neovim terminal buffers keep their old scrollback
on CSI 3J. A valid `reflowed=1` reply (matching action-9 id, or unsolicited
`envi-t3-layout=0`) marks that terminal buffer stale. After a 100 ms trailing
debounce the **current** viewer gets a fresh terminal buffer and
`hc attach --history 2000` replay for the same core address, in the same window.
On focus entry replay waits for the pending geometry check and a completion at
the focused width, coalescing a stale background notification with that check's
rebuild. A delayed completion for another width schedules a normal bounded check
rather than replaying obsolete geometry. After replay a single immediate action-9
handoff (not another resize/settle cycle) makes the fresh attachment authoritative.
Opening the popover when the client is already visible creates its own attachment
PTY (`term.attach`'s opt-in `separate` option), not a second window on the same
terminal job. Otherwise Neovim can resize the shared old job to its remaining
background window during replacement, racing even the immediate input handoff.
The core client is still shared; only the local viewer/channel is independent. A real later
same-width rebuild still refreshes; there is no width-based permanent suppression.
No program is started/restarted/killed. Other windows sharing the old buffer
keep it until entered; hidden buffers refresh on `BufWinEnter`. `FocusLost`
editors also wait. The old viewer buffer is wiped only when no window shows it.
No temporary `'scrollback'` changes race new output.

Reattachment reinstalls T3's maps/handlers, keeps the window role, winbar,
colours and sidebar selection, follows the rebuilt history at the bottom, and
preserves INSERT vs COMMAND. It deliberately replaces the old scroll anchor
and terminal selection. Per-view history is limited to hc's existing 2000-line
replay. An ordinary old client that never reports reflow never takes this path.
`layout-rebuild-core.lua` proves the complete real private-core/embedded-Neovim
boundary: old markers disappear from the **whole** fresh buffer, new markers
remain, both modes survive, and Esc-to-bar / Ctrl-] still work. Each run leaves
a private empty core running for REP cleanup and records its PID/socket under
`.agent/h2/rebuild-core-<pid>.json`; all HC/XDG paths are isolated.

INSERT `<Esc>` and `<C-]>` both go to COMMAND and never forward a raw Esc to the client: they send the
private `dismiss` control (`ESC[>777;6u`, `tools/t3-thread/control.mjs`), which closes a dialog, the model picker
or a menu and never interrupts. COMMAND `<C-]>` returns to INSERT (a toggle); COMMAND `<Esc>` is a no-op.

Colours (separate from the black bars above, which come from the viewer's opening sequence): a popover client is told
the popover's own colours (the hub's `ui.fg`/`ui.popover`), both from its first byte (`terminal.run` display,
`term.open{display}`) and as its buffer's OSC 10/11 answers, so a program that asks for its background gets the one
it is shown on. These answers no longer depend on which window has focus (`nvim_get_hl(link = false)` resolves through
the focused window's `winhighlight`). On every popover open, switch and theme change, and
on `attach_in`, the buffer's answers are re-resolved from what that window shows (the T3 remap, or the editor's
`Normal` when it has none, e.g. an untinted main pane), so a reused buffer never keeps another view's colours.
When a view stops showing the client (COMMAND `q`, closing the window, or switching that window to another thread)
the answers follow the view that remains, the focused one if it shows the client; with no view left they keep the
last value until the next attach.
With a missing/invalid hub a new popover keeps the editor's `Normal`; a shown window keeps its look. Other terminals
answer with the global `Normal`/`Cursor`, whichever window has focus. Already printed history keeps its colours.

T3 sets `vim.t.hcmux_session_skip = true`. The generic session serializer omits
opted-out tab blocks and their exclusive buffers from the saved Vim script,
without closing/recreating any live tab/window. Ordinary tabs and shared buffers
are preserved; if every tab is opted out it refuses to replace saved state.
After detach/reload T3 is absent; `go("T3")` creates it again on demand. Core
clients remain alive and can be reattached. If only T3 is left, Detach still
quits cleanly, leaving the previous saved editor layout untouched (the holder
is not released by a write; its exited pid is detected on the next attach). Session detach/reload, commands and
terminal restoration are otherwise unchanged.

Headless checks: `nvim/tools/t3-thread/test/run-lua.sh` runs every Lua suite (or the named ones, e.g.
`run-lua.sh layout sidebar`) and exits nonzero if one fails. A bare `nvim --headless '+luafile …' +qa` exits 0 even
when the suite throws, so don't gate on it. `scrollback-strikes.lua` opens real popovers (AGENT slot and direct
route) in an embedded Neovim with an RGB UI and checks colour negotiation, resize/hide/switch identities and keys;
its viewer is a synthetic stand-in for `hc attach` (it paints with the negotiated colour itself, so it tests the
negotiation protocol, not the black-bar cause), never a real core or thread. `scrollback-lifecycle.lua` checks the
answers at reopen, main-pane (hide, close, switch-away in both directions), theme-refresh, fresh-viewer and
restart boundaries, before any further attach. `viewer-pen.lua` runs the real
viewer command with `hc` swapped for `support/fake-hc-attach.sh` (hc's captured opening sequence) and checks that
no history cell is black, in the T3 popover and in an ordinary terminal split.

### T3 status and update (`t3update.lua`)

**Premise: the local desktop.** Both commands assume that the endpoint (`T3_URL`, default
`http://127.0.0.1:3773`) and the desktop home (`$T3CODE_HOME`, trimmed, default `~/.t3`) describe the same backend,
the one the local T3 Code desktop runs. Remote or proxied endpoints are not supported. When `server-runtime.json`
names a port that differs from the endpoint's, `:T3Status` says `endpoint and desktop home disagree (port X vs Y)`
(endpoint, then home) and `:T3Update` refuses with the same text.

`:T3Status` prints one asynchronous notice, e.g.
`T3: server up · v0.1.11 pid 4242 since 2026-11-18T02:33:13Z · no update in progress · 7 client buffers, 7 client processes running`.
It probes `/.well-known/t3/environment` (2 s), reads only `serverVersion`, `pid`, `startedAt` and `port` from
`$T3CODE_HOME/userdata/server-runtime.json`, and reports the desktop's update marker
`$T3CODE_HOME/runtime/desktop-update-in-progress`. Files are read with bounded async libuv reads, never on the UI
loop. Notices never print the endpoint URL, which may carry credentials. Buffers are counted per buffer, processes
once per core address (the popover and the main pane can view one client). "Running" means the client's herdr-core
process is alive, not that its websocket is connected.

**One observation order** serves status, preflight and the watch: [probe] → marker → runtime → marker. The marker is
read last, and also before the runtime, so a marker that appears while the runtime is read is seen; a decision is
made only in the callback of that last read.

**Marker contract** (shared with the desktop's own waiters): numeric `{startedAt, expiresAt}` is in progress until
`expiresAt`, compared in wall-clock milliseconds; anything else (malformed, partial, unreadable) is in progress until
mtime + 60 s, including a record larger than the 64 KiB read limit (never a decoded prefix); an expired marker
counts as absent, and so does one removed while it is being read.

`:T3Update` starts the **desktop's own** update flow and never stands in for it: envi never writes or removes the
update markers, never stops or restarts the server and never runs `t3 update` (that is for the CLI/service
install).

1. **Preflight** refuses when an update is in progress, or when, after a fresh probe, the server is unreachable,
   its pid is unknown or the ports disagree. Running threads come from `t3side.feed_state()`, which is live only
   for a valid frame of the current sidebar feed job: with running threads it asks
   `N running thread(s) will be interrupted … y/n`; with no live feed (not started, only the render seed, failed or
   restarting) it says `running threads unknown (sidebar feed not running)` and still asks. After `y` it probes and
   validates again and takes that pid as the baseline, so nothing that changed during the question is trusted.
2. **Trigger:** `osascript` activates T3 Code and clicks its app menu's `Check for Updates…` through System
   Events. App, process, menu and item prefix live in `M.config.app`. The user answers the desktop's dialogs
   (Download / Restart / Later).
3. **Watch:** an fs watcher on `runtime/` plus a 2 s timer. A dedicated deadline timer (10 min) ends the run
   regardless of poll cadence; every async stage that returns after it stops without output. At most one probe
   starts per 2 s and one async step runs at a time. Success is decided on the probed observation: no marker in
   progress, the same new pid in `server-runtime.json`, its port (when published) equal to the endpoint's, and a
   reachable server: `T3 updated: <old> → <new>` or `T3 restarted (same version …)`.
   An expired marker over a readable baseline pid with a failed probe is reported once as `update stalled`, and
   the watch continues. Unknown or contradictory state keeps watching. No marker within 3 min reports
   `no update started`. Every end closes all three handles; late results are dropped.
4. **After:** a notice names the client processes still running and those that are not, with `:T3Restart` for a
   stuck one. Nothing is restarted automatically.

A System Events failure gives one message naming the missing permission (Accessibility, or Automation for System
Events) and is not retried. Tests: the `t3update-*.lua` suites stub `vim.system` (curl and osascript never run)
and `jobstart` (no feed starts), and use a temporary `T3CODE_HOME`; `support/t3update-fixture.lua` is their shared
helper.

## AGENT mode (`hcmux.agent`)

`<leader>a` opens a centred, approximately 90% × 85% popover; the next key
is buffer-local, so `<leader>a1`, `<leader>ai`, and `<leader>a/` need no extra
global mappings or prefix timeout. Lualine reads `agent.active` while either
view is open. `toggle()`, `open("board" | "search")` (board by default), and
`close()` are the public API; opening search explicitly starts INSERT.

The board is nine numbered cards, left-to-right/top-to-bottom. It resolves the
T3 project by exact normalized session-root/workspace path (git root of cwd
without a session root), excluding archived and unlisted rows. Unmarked slots
show a dimmer `auto` tag: pinned first, then the sidebar's working, attention/
error, unseen done, newest-activity order. Settled threads never auto-fill.
Fixed marks override auto slots; their number is an emphasised selection-colour
chip beside a pin-like `⚑` glyph. Auto labels and unselected borders are dimmed;
the selected card retains its accent border. Marking a thread again moves its mark.
`m` prompts and reads the slot digit directly, with no mapping timeout; `Esc`
cancels. This works even when typing more slowly than LazyVim's `timeoutlen`. A missing,
archived, unlisted, or out-of-project marked thread remains `gone` until cleared.
Clearing removes the mark, not the thread; the slot may immediately auto-fill.

| Board key | Action |
|---|---|
| `1`–`9` | open that slot in the T3 popover; close AGENT |
| `h j k l` / arrows | select card |
| `Enter` / `o` | open selected thread |
| `i` | blank new thread from project root, in T3 **COMMAND** mode |
| `/` | search, **INSERT** at query end |
| `m1`–`m9` | mark selected thread into slot N (move existing mark) |
| `x` | clear selected slot's mark |
| `Tab` | search in NORMAL, preserving query |
| `R` | restart/refresh the shared feed |
| `?` | key help |
| `q` / `Esc` / `<leader>a` | close |

Search has a full-width rounded input box with a search glyph, an empty
`Search threads…` placeholder, and a right-aligned filtered/total hit count.
Its border uses the working accent in INSERT and muted branch colour in NORMAL.
The query remains the only editable row of the same buffer; border, placeholder,
and count are drawn as chrome/virtual overlays, not editable query text. There
is no second input window or alternate key-dispatch path.

Search fuzzy-matches titles live (`matchfuzzypos`) with character highlights.
All listed project threads participate, including settled: unsettled first,
then fuzzy score when searching, then newest interaction. Cards page to keep
the selection visible; the cursor is confined to the query or selected card's
first content line. Only the query is editable, with card/prompt restoration
on text changes and a nonmodifiable buffer in NORMAL.

| Search mode | Key | Action |
|---|---|---|
| INSERT | type | live fuzzy filtering |
| INSERT | `Ctrl-n/p` / Down/Up | select next/previous hit |
| INSERT | `Enter` | open hit; close AGENT |
| INSERT | `Esc` | NORMAL; keep pane open |
| NORMAL | `j/k` / Down/Up, `gg/G` | select hit / first / last |
| NORMAL | `Enter` / `o` | open hit; close AGENT |
| NORMAL | `m1`–`m9`, `x` | mark hit / clear its mark |
| NORMAL | `i` / `a` / `/` | INSERT at query end |
| NORMAL | `Tab` | board |
| NORMAL | `?`, `q` | help / close |
| NORMAL | `Esc` | stay in NORMAL |

Marks use versioned core document `envi-agent.<session>`, shape
`{ "slots": { "1": "<thread-id>", "9": "<thread-id>" } }` (only marked slots).
Core names allow at most 32 bytes: long/invalid session names use
`envi-agent.<first-21-hex-of-sha256(session)>`. Failed/conflicting saves warn and
leave local marks unchanged; reopen to reload rather than overwriting a newer
document. Without a session, marks stay in memory per root, never in a document.

AGENT and the sidebar share **one** `threads.mjs` process. `t3side.snapshot()`
returns a defensive snapshot copy plus the current safe error; `subscribe(fn)`
immediately calls `fn(snapshot, error)` and returns an unsubscribe function.
`start()` ensures the job; closing AGENT only unsubscribes. The sidebar does not
replace an already-live snapshot with fixture content when first created.
`presentation` exports its existing highlights, clean/truncate, age, harness,
and recent-order helpers so both surfaces share colours/order. T3's additive
`open(id, { mode = "command", cwd = "/project/root" })` option leaves all
ordinary opens, COMMAND/INSERT maps, and client lifecycles unchanged.

`?` opens a centred, two-column key/action help float grouped by Board, Search
INSERT, and Search NORMAL. `q`, `Esc`, or `?` dismisses help only; closing AGENT
also cleans up help. Both floats recenter on resize. At short heights help uses
native scrolling instead of truncating the action text.

Additional mocked checks: `agent`, `agent-state`, `agent-command`, `agent-polish` using the same
headless command as above. No headless test opens a real thread or terminal.

## PR viewer (`hcmux.prs`)

The PR board follows AGENT's rounded popover/card presentation and the active
hub palette. Public API: `toggle()`, `open({ repo = "owner/repo", scope =
"Repo" | "Review" | "Mine" | "Involved" })`, `close()`, and boolean `active`.
Options are optional. Keybinder owns global mappings and lualine integration;
this module installs only buffer-local keys. `active` stays true while a board
child view or its hunk float is focused. Closing the board turns it false but
leaves its review processes/drafts alive.

Scopes are Repo (session origin), Review (requested from me), Mine (authored by
me), and Involved. Repo is the default if nonempty, otherwise Involved. Tabs show
counts (up to 100 open PRs per scope). Requested reviews lead, then non-drafts,
then newest activity. Cached scope cards appear immediately during refresh;
network/rate-limit failures retain them. Search scopes render sparse rows first,
then enrich through `gh pr view` with at most four concurrent view processes
across the module, reusing detail results by URL/`updatedAt`. Authentication stays
inside `gh`; this code never reads or logs tokens.

Cards show checks (green pass/red fail/yellow pending), review decision, draft,
branch direction, diff statistics, comment count, `◉ hunk` for a live review and
`✎ N` for captured drafts (`N drafted` after hunk exits). At 140+ editor columns,
a Markdown details pane sits on the right; below that, `K` opens an overlay.
Details include labels, reviewers, checks/durations, and body. The search field
is a separate boxed one-line scratch buffer with completion and autopairs off;
fuzzy matching uses number, title, branch, author and repository.

| Board key | Action |
|---|---|
| `j` / `k`, arrows | Next / previous card |
| `gg` / `G`, `Ctrl-d` / `Ctrl-u` | First / last, page down / up |
| `Enter` / `l` | Review selected PR; re-show its existing live hunk |
| `/` | Search in INSERT; type to fuzzy-filter |
| Search INSERT `Esc` / `Enter` | Return to board NORMAL / review top hit |
| `Tab` / `Shift-Tab` | Next / previous scope |
| `K` | Narrow-editor details overlay |
| `o` / `y` | `gh pr view --web` / yank URL to `+` |
| `c` | Checks float; `Enter` opens selected check's HTTPS log URL |
| `r` / `R` | Refresh / pick Repo scope repository |
| `s` | Confirm review submission (comment / approve / request changes) |
| `x` | End this PR's hunk and discard drafts, with `y/n` confirmation |
| `?` | Help; `?`, `q`, `Esc` dismiss help only |
| `q` / NORMAL `Esc` | Close current overlay or board |
| Hunk TERMINAL `Ctrl-q` | Capture comments, hide the float, return to board |

No printable hunk-buffer keys are mapped: hunk's own `q` and comment editor
remain intact. `Ctrl-q` is not assigned in hunk 0.21.1's built-in key bindings.
Board close hides any visible owned hunk rather than ending it; re-opening the
same PR reuses the same buffer/process. `x`, successful **real** submit, and
`VimLeavePre` end only hunk terminals this module started. No other terminals
are enumerated/killed. These terminals use `session=false`, `listed=false` and
are not restored by the generic session manager.

### Diff sources and themes

The session root and known T3 project checkout paths are checked against their
GitHub origin. A matching local checkout runs only
`git fetch --no-tags --refmap= origin refs/pull/N/head` (objects/FETCH_HEAD, no
branch, checkout, tags or tracking ref updates). The fetched head must equal the
API head; `git merge-base baseRefOid headRefOid` supplies the first revision for
`hunk diff <merge-base> <head>`. Missing base objects/fetch failure fall back to a
patch; there is no extra fetch or local branch mutation. Otherwise `gh pr diff`
is saved at `stdpath("cache")/envi-pr/owner-repo-N.diff` and opened with
`hunk patch <path>`. Hunk runs in the matched checkout or the session root for
patch input. Without hunk, a read-only diff buffer is shown instead.

Hunk 0.21.1 bundles the relevant names `nord`, `gruvbox-dark-hard`,
`gruvbox-dark-medium`, `gruvbox-dark-soft` (alongside its other Shiki themes).
Hub **nord → hunk nord**; hub **gruvbox-dark → hunk gruvbox-dark-hard** (the hub's
hard dark background). Unknown hub names omit `--theme`, using hunk's default.
Every launch uses `--no-transparent-bg`; Neovim's surrounding terminal float
uses the hub's popover/background/foreground/border tokens.

### Inline comments, capture and submission

Each launch inherits a unique `TERM_SESSION_ID` marker; hunk publishes it in
`session list --json`'s `terminal.locations`. Only a unique exact match is used,
then all session commands use its exact session ID (never repo-based guessing).
If identification fails, the diff remains usable and a notice explains that
capture/import is unavailable. The module does not start or restart a daemon;
hunk's own daemon connection must work.

Current GitHub inline comments are loaded with paginated `gh api`, then applied
as agent notes with GitHub login, first-line summary, full body and comment URL.
Outdated comments without a current line are skipped, not mapped to an obsolete
`original_line`; notes absent from the loaded diff can be rejected by hunk and
produce a notice. Imported notes never become submit candidates: capture uses
`comment list --type user --json` only.

Live user comments are captured about once a second, on `Ctrl-q`, board focus,
and before `s`. Snapshots include PR, head SHA, capture time and notes, both in
memory and `stdpath("cache")/envi-pr/owner-repo-N.comments.json`. This is a
**last successful snapshot**, not a guarantee to capture a comment saved just
before hunk's own `q`. Prefer `Ctrl-q`, which keeps hunk alive. If hunk has closed,
the confirmation says `hunk closed; using comments captured at HH:MM:SS`.
There is no automatic cross-Neovim draft recovery from cache in this version.

`newRange` maps to GitHub `RIGHT`, `oldRange` to `LEFT`. Inclusive multiline
ranges set `start_line`/`start_side` and ending `line`/`side`. Missing, dual-sided,
invalid or reversed anchors are listed in the confirmation and **block every
submit action**; fix/remove them in hunk. The head is fetched afresh before the
confirmation and again after choosing an event; any change refuses submission.
The review body includes `commit_id` so it is tied to the captured head.

Confirmation keys: `c` → `COMMENT`, `a` → `APPROVE`, `r` → `REQUEST_CHANGES`;
`Esc` cancels with no write. Only this confirmed path can POST a review.
`ENVI_PR_DRY_RUN=1` instead writes `stdpath("cache")/envi-pr/last-review.json`,
never invokes the GitHub write command, and **preserves** hunk/drafts since
nothing was actually submitted. Example body:

```json
{"event":"COMMENT","commit_id":"<captured-head-sha>","comments":[{"path":"a.lua","body":"Fix this","line":12,"side":"RIGHT"}]}
```

Headless suites: `prs-gh`, `prs`, `prs-states`, using fake `gh`/`git`/`hunk`/`hc`
executables and mocked terminal launches. Tests set dry-run and isolate caches.
`ENVI_PR_NO_BROWSER=1` suppresses both check-log `vim.ui.open` calls and PR
`gh pr view --web` calls, notifying the URL instead. All PR test suites set this
guard and dry-run; browser functions are also stubbed as defense in depth.
REP owns interactive Herdr E2E; headless UI tests are not that proof.

## File-first whiteboard (`hcmux.board`)

`require("hcmux.board").open("/absolute/design.wb.md", { bindings = {
repo = "/absolute/trusted/git/root" } })` opens a native, read-only 90% × 85%
popover. Bindings are optional explicit host trust, never authored paths or cwd
inference. `.toggle()` closes/reopens the last board, `.close()` is idempotent,
`.refresh()` retries and `.active` remains true in owned source/help overlays.
Same-path open focuses/reuses; a different path replaces the owned view. The
module owns one direct non-PTY Node worker over private bounded/chunked NDJSON,
not an hc terminal or T3 client. No global mappings/commands are installed;
keybinder owns leader/command/statusline integration. `User EnviBoard` provides
`data.buf` once per board buffer.

Native motion/search/yank work. `[s`/`]s` jump headings; Tab outlines; `s` finds
exact Mermaid source; Enter on a source record opens immutable commit bytes in
a read-only child; `e` opens the board file as an ordinary editable buffer at
its original source line, preserving modified and terminal/non-file invokers in their own panes. `R` refreshes, `?`
helps, `q` closes. Navigation Esc stays; q/Esc in a child dismiss only the child.
Leaving focus keeps the view open. Resize recenters; live theme-hub changes and
ColorScheme touch only `EnviBoard*`. Invalid saves retain last good **STALE**
content; deleted/recreated and atomic-save files recover. Close/WinClosed/wipe/
VimLeavePre clean only the exact owned worker/watchers, returning a valid invoker.

The source file remains truth: JSON envelope, stable markers, inert Markdown,
original Mermaid plus explicitly approximate pinned `merminal 0.1.0` subset,
and in-file thread attachment states. Missing/unsupported renderer and unbound
pins remain visible with reasons. No links/scripts/resources execute; no fetch,
checkout, network, browser, mutation/import/rich output, or Whiteboard.app changes.
Current checkout freshness is unknown, never old commit labels over current bytes.
The macOS renderer uses Seatbelt plus CPU/deadline/output bounds and sampled RSS,
not a hard instantaneous memory cap. Other OSes retain source until isolation is
proven. See `nvim/tools/envi-board/README.md` for install/CLI, subset matrix,
agent authoring, exact pins, trust and protocol. Mocked `test/board.lua` and real
private-worker `test/board-live.lua` are headless adapter checks, not REP's manual
Herdr E2E. They never contact hc/T3/network or launch a browser.

## Approved remote shell (`hcmux.remote`)

`require("hcmux.remote").setup()` registers `:EnviRemote`: an approved-host picker
whose source is local `envi-remote hosts` (private policy, never SSH config).
`pick()` opens that picker; `open("approved-id")` is the validated argv-only
adapter. Put `remote/bin/envi-remote` on the **local** PATH manually and configure
`~/.config/envi-remote/hosts.json` as described in `remote/README.md`.
No global keymap or plugin-spec wiring is installed by this lane; keybinder/REP
owns calling setup from the existing integration entrypoint. Until then use
`:lua require("hcmux.remote").setup()` once in the local editor.

The action starts `{ "envi-remote", id }` via `hcmux.term.open` in a vsplit.
It never constructs a shell command, exports local cwd as a remote path, guesses
remote process status, or replays commands on restore. The existing `hc://`
restore path reattaches the **local** client; losing that client requires an
explicit new invocation. Only the known minimal-profile label is added; transport
and remote lifecycle are CLI-owned. This lane supports explicit approved SSH,
not yet Mosh or remote tmux. Mock-only check: `nvim --headless -u NONE
'+luafile nvim/tools/t3-thread/test/remote.lua' +qa`.
