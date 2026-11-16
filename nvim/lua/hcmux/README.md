# hcmux: nvim as a multiplexer on herdr-core

Terminal buffers in nvim are **views** onto herdr-core (`hc`) terminals. The
programs (shells, Claude, Codex, pi, …) run in herdr-core, not in nvim.

- Closing a buffer, closing a window or quitting nvim leaves them running.
- Reopening nvim in the same folder brings the whole layout back from its
  herdr-core session (see Sessions). Terminals attach when shown and replay
  2000 lines of scrollback.
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
| edit, split, open tabs, start terminals | saved automatically, 1.5 s after things settle and on idle |
| `:detach` or `:qd` (also `:Detach`, `<leader>qd`, `:qa`, `:q` on the last window) | **detach**: the layout is saved, the terminals keep running |
| `:reload` (also `:Reload`), in an nvim started by `envi` | **reload**: detach, then the `envi` launcher starts nvim again on the same session, so config changes take effect |
| nvim crashes or its tab closes | nothing is lost beyond the last 1.5 s |

All of vim's own quit commands keep their meaning: `:q` closes a window (the
last one detaches), and `:wq`, `:qa!` work as usual. `:detach` and `:qd` are the
explicit way to leave a session from anywhere.

- **Two nvims on one session:** the second one says so, shows
  `(read-only)` in the statusline and doesn't save. `:Session take`
  (`<leader>qt`) moves the session to it. The core refuses any save based on
  an old version, so the first nvim then shows `(not saving)`, never
  overwriting. `:Session reload` loads the newer layout.
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
those keys attach and focus its client. Native `j k gg G` move; `R` refreshes.
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

INSERT `<Esc>` and `<C-]>` both go to COMMAND and never forward a raw Esc to the client: they send the
private `dismiss` control (`ESC[>777;6u`, `tools/t3-thread/control.mjs`), which closes a dialog, the model picker
or a menu and never interrupts. COMMAND `<C-]>` returns to INSERT (a toggle); COMMAND `<Esc>` is a no-op.

Colours: a popover client is told the popover's own colours (the hub's `ui.fg`/`ui.popover`), both from its first
byte (`terminal.run` display, `term.open{display}`) and as its buffer's OSC 10/11 answers, so cells painted with the
"default" background match the float rather than the editor. With a missing/invalid hub a new popover keeps the
editor's `Normal`; switching in place keeps the shown window's colours. Other terminals answer with the global
`Normal`/`Cursor`, whichever window has focus. Already printed history keeps the colours it was painted with.

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
route) in an embedded Neovim with an RGB UI and checks history cell colours, resize/hide/switch identities and keys;
its viewer is a synthetic stand-in for `hc attach`, never a real core or thread.

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
