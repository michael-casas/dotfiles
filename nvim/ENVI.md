# envi: the production nvim

envi is the agentic Neovim configuration: nvim as a terminal multiplexer and
session manager on top of **herdr-core** (`hc`), with agents one key away. It
is the daily nvim: the default profile, running the `~/.dotfiles` checkout of
`main`. Changes are developed in worktrees, each under its own dev profile, and
reach production when they merge.

## The setup

### Production

| Part | Where |
|---|---|
| Config | `~/.dotfiles/nvim`, the main checkout (`~/.config/nvim` points there). Uncommitted edits in `~/.dotfiles/nvim` are part of production too |
| nvim profile | the default one (`NVIM_APPNAME` unset): state in `~/.local/state/nvim`, plugins in `~/.local/share/nvim` |
| Command | `envi` (`~/.local/bin/envi` points to `~/.dotfiles/nvim/bin/envi`) |
| Session | `envi` attaches to the herdr-core session **`dotfiles`**, running in `~/.dotfiles` |
| T3 credential | `~/.local/state/envi/t3-session.json`, read and written by every T3 client whatever the profile. It stays there; never print it |

`envi` with no arguments opens the session. `envi <file>` opens files with no
session. `envi ls` and `envi kill <name>` manage sessions. Inside, `:detach` or
`:qd` leaves; everything keeps running in herdr-core. `:reload` (or `:Reload`)
detaches and starts envi again on the same session, so config, plugin and
launcher changes take effect. It asks first about unsaved buffers.
`ENVI_SESSION=<name> envi` picks another session.

A plain `nvim` is the same config and profile without the launcher: `nvim`
attaches the folder's session, `nvim <file>` is a plain editor, and `:reload`
there says to `:qd` and run `envi`. `envi` always runs production, even when
started inside a dev nvim.

### Development: `envi-dev`

Work happens in a worktree (a Treehouse slot). `envi-dev` runs that worktree's
`nvim/` without touching production:

```sh
cd <worktree> && envi-dev          # or: envi-dev <worktree>, or ENVI_DEV=<worktree> envi
envi-dev <worktree> path/to/file   # files, no session
ENVI_SESSION=e2e-x envi-dev        # another session: dev-e2e-x
```

| Part | Where |
|---|---|
| nvim profile | `NVIM_APPNAME=envi-dev/<slot>`, one per worktree. `<slot>` is `slot<N>` (its Treehouse slot) or its folder name, reduced to `a-z 0-9 -` (12 characters at most), plus the CRC of its exact path in 8 hex digits, e.g. `slot3-1a2b3c4d`; it is printed at start. Two worktrees never share one. A worktree path containing a control character (tab, newline, any byte 0x01-0x1F or 0x7F) is refused at launch; spaces and non-ASCII names work. A relative path is taken from the current folder (`CDPATH` is ignored) |
| Config | `~/.config/envi-dev/<slot>` points to `<worktree>/nvim`. An existing link to another worktree is never repointed |
| State | `~/.local/state/envi-dev/<slot>` (its own shada, undo, swap), and `~/.cache/envi-dev/<slot>`. Every dev folder and each of its ancestors up to `$HOME` (the XDG homes included) must be a real folder, never inside a production profile, with no link inside the state and cache folders: anything that could route writes into production is refused before nvim starts |
| Plugins | shared on purpose: `~/.local/share/envi-dev/<slot>` points to `~/.local/share/nvim` (a link anywhere else is refused) |
| Session | `dev-<slot>`, running in the worktree. Dev sessions live in their own herdr-core namespace: documents `nvsdev.<name>`, index `nvsdev-index`, terminal label `herdr.nvsdev`. A dev nvim never reads or writes a production session, even one named `dev-…`, and never adopts a production terminal (nor production a dev one). Names start with `dev-` (added if missing), at most 25 characters |
| Launcher | the worktree's own `nvim/bin/envi`, so launcher changes are developed there too. `:reload` comes back in the same dev profile and session. Its `nvim/bin/envi` and `hcmux/session.lua` must each declare exactly one comment line `envi-dev-protocol: 2` (any other value, or none, is refused before its code runs): rebase an older worktree onto main |

`envi-dev sessions` and `envi-dev kill <name>` manage dev sessions (inside a
worktree). Hot reload in a dev nvim follows the worktree's own commits.

**Cleanup, by hand.** A dev profile outlives its worktree, and there is no
command to remove it. List every profile path (read-only):

```sh
find "${XDG_CONFIG_HOME:-$HOME/.config}/envi-dev" "${XDG_DATA_HOME:-$HOME/.local/share}/envi-dev" \
  "${XDG_STATE_HOME:-$HOME/.local/state}/envi-dev" "${XDG_CACHE_HOME:-$HOME/.cache}/envi-dev" \
  -mindepth 1 -maxdepth 1 -exec ls -ld {} +
```

The config entries are links to their worktrees (`… -> <worktree>/nvim`); a
link whose worktree is gone marks a stale profile. For that `<slot>`, remove
the config link `$XDG_CONFIG_HOME/envi-dev/<slot>`, the data link
`$XDG_DATA_HOME/envi-dev/<slot>` (a link to the shared plugins: remove the
link, never what it points to), and the folders
`$XDG_STATE_HOME/envi-dev/<slot>` and `$XDG_CACHE_HOME/envi-dev/<slot>`. End
its session with `envi-dev kill dev-<slot>` inside any worktree.

**Tests.** `nvim/bin/test/run.sh` proves the launcher, the dev profile and the
cutover in a throwaway `HOME` (a fake `hc`; nothing real is touched).

## Keys added for envi

| Keys | What |
|---|---|
| `<leader>ha` | **agent**: the AI tool picker (was `<leader>oai`). The chosen tool starts fresh in nvim's cwd, in a vsplit pane of the current herdr-core session. Resuming an old session opens it in the folder it was made in |
| `<leader>hi` | the **REP \| dotfiles** T3 thread in the T3 popover (85%, `hcmux/t3.lua`). It opens or focuses, and switches the shown popover to this thread in place; it never hides. **INSERT** types into the thread; popover `<Esc>` dismisses a dialog, model picker or menu and enters **COMMAND** in place, without forwarding a raw Esc or interrupting. **COMMAND**: `i`/`a`/`I`/`A` back to INSERT, `j`/`k` scroll, `m` model picker, `c` compact (y/n), `<C-c>` interrupt (y/n), `q` hide (the only way), `<Esc>` no-op. The T3-layout main pane uses the same COMMAND keys, except `q` does nothing there; its INSERT `<Esc>` differs as described below. `:T3Restart` restarts the client; preserve unsent drafts before restarting an older persistent client |
| `<Esc>` in the T3 layout main pane | From **INSERT**, first dismiss an open menu/model picker/dialog/question and stay in INSERT; otherwise show/focus the **thread bar** in NORMAL on the open thread's title. Never interrupt. Dismissing a question preserves its pending request, draft and selected answers; returning to INSERT reveals it again. Older/nonresponding clients fall back after about one second to dismiss + COMMAND in place, not bar navigation. Normal-mode `<Esc>` remains a no-op |
| `<C-]>` in the T3 main pane or popover | Toggle **INSERT** / **COMMAND** in place for native scrolling/selection; never move focus to the thread bar. After a width change, history redraws centred and the focused view reattaches automatically in the same mode (COMMAND scroll position resets to the bottom) |
| `:T3Recenter` | Check the current T3 pane's real size, re-apply it to its viewer if needed, and request client history reflow; report one result (older clients time out without retry or restart). No keymap |
| `:T3Status` | One async notice: whether the T3 server is reachable, its version, PID and start time, whether a desktop update is in progress (seconds left), and the number of envi T3 client buffers and running client processes. No keymap |
| `:T3Update` | Open **T3 Code (Nightly)**'s own **Check for Updates…** menu; answer the desktop dialog yourself (**Download / Restart / Later**). envi asks y/n first if threads are running or the sidebar feed isn't running, then watches and reports **T3 is updating…**, **T3 updated: old → new** / **T3 restarted (same version …)**, **no update started** or **update stalled**. Never stops or restarts the server itself. Requires macOS Accessibility/Automation permission for **System Events**. No keymap |
| `<leader>h?` | **keybinder**: a T3 thread for config changes and questions about envi. It toggles the popover, like `<leader>hi` |
| `<leader>a` | **AGENT** board (`hcmux/agent.lua`): a big popover of this project's T3 threads in a 3x3 grid, slots 1-9. Slots you mark stay put; the rest fill from T3's pinned + sidebar order (dimmed, `auto`; settled threads never auto-fill). Then `1`-`9` (or `hjkl` + `Enter`/`o`) opens that thread in the T3 popover, like `<leader>hi`; `i` starts a new thread in COMMAND; `/` fuzzy-searches thread names in insert mode (Esc → normal, `j`/`k` through the hits, settled and oldest last); `m`+digit marks the selected thread into that slot, `x` clears a mark; `Tab` switches board/search; `R` refresh, `?` help; `q` (or `<leader>a`, or `Esc` on the board) closes. Marks persist per session. lualine reads `AGENT` while it's open |
| `<leader>gp` | **PR viewer** (`hcmux/prs.lua`, replaces LazyVim's Snacks PR picker on this key; `<leader>gP` is still Snacks' all-states picker): a big float of open PR cards via `gh`. `Tab`/`S-Tab` cycle scopes Repo / Review / Mine / Involved (opens on Involved when the session repo has none). `j`/`k`, `gg`/`G`, `<C-d>`/`<C-u>` move; `Enter`/`l` review in **hunk** (a terminal float; `<C-q>` there hides it and returns to the board, keeping drafts; hunk's `q` quits it); `/` fuzzy search (INSERT; `Esc` → NORMAL, `Enter` reviews the top hit); `K` details; `o` browser; `y` yank URL; `c` checks; `r` refresh; `R` pick the Repo-scope repo; `s` submit your hunk comments as a review (confirm first: comment / approve / request changes); `x` discard drafts and end that PR's hunk; `?` help; `q`/`Esc` close. lualine reads `PR` while it's open |
| `<leader>hv` | **layout switcher**: `nvim` or `T3` (`hcmux/layout.lua`). Each layout is its own tab page. In the T3 **thread bar**, NORMAL-mode `j`/`k` move to the next/previous visible thread card's title, skipping headers, blank lines and card metadata; counts work (`3j`/`3k`), clamp at the ends and never wrap or attach a client. `gg`/`G` keep native row navigation to reach disclosure headers. `Enter`/`o` or a left-click on any card row (title, pinned project metadata or branch) opens/focuses that thread in the main T3 pane in **INSERT**, including the already-open thread, and anchors the bar cursor on its title. `Enter`/`o` or a left-click on a project/Settled header toggles its disclosure; blank clicks do nothing. Native drag selection and wheel scrolling remain unchanged; mouse is not enabled automatically. `/` opens the Snacks **Search thread titles** fuzzy picker: full titles across all projects, including collapsed and settled threads, excluding archived/unlisted ones; project and age provide context. Picker `Enter` opens the hit in the main T3 pane (not the popover) and moves the bar cursor to its title if visible; picker `Esc` from INSERT or NORMAL cancels without changing the bar cursor or main client. `R` refreshes the shared feed. All thread-bar mappings are buffer-local |
| `<leader>hw` / `:EnviBoard [file]` | **whiteboard** (`hcmux/board.lua`): a read-only 90% × 85% popover rendering a `*.wb.md` board. In a `*.wb.md` buffer it opens (or focuses) that board; elsewhere it closes the shown board, reopens the last one, or asks for a file. `:EnviBoard` completes file names and defaults to the current buffer. Inside (board.lua's keys): normal motions/search/yank; `[s`/`]s` jump headings; `Tab` outline; `s` find the exact Mermaid source; `Enter` on a source record opens its commit bytes read-only; `e` edits the board file at that line; `R` refresh; `?` help; `q` close (`Esc` doesn't close; in a child, `q`/`Esc` dismiss only the child). No repo trust is passed, so source pins stay untrusted unless opened with `bindings.repo` from Lua. lualine reads `BOARD` while it's open |
| `<leader>b` | in the T3 tab, show/hide the thread sidebar from any normal window (buffer-local nowait, so `<leader>b*` buffer keys don't apply there); elsewhere, including the popover, the LazyVim buffer group as before (`<leader>bd`, `<leader>bb`, … unchanged) |
| `<leader>hn` | **help desk**: pi on `j5/gpt-6-luna` in a centered float (65%). It's read-only, fresh each time it starts, and given the live keymaps. `q`/`<Esc>` hide it |
| `<C-\>` + key (normal and terminal mode), `<leader>m` | hcmux: `c v s t` new shell, `w` pick, `d` detach, `x` kill, `hjkl`, `z` zoom, `a` AI tools |
| `<leader>qs` / `qd` / `qr` / `qt` | sessions: pick, detach, rename, take over |

T3 thread buffers show **T3 updating…** during a desktop update and
**T3 server restarted (<version>)** once afterwards.

Full reference: `nvim/lua/hcmux/README.md`.

## What exists (all uncommitted on `envi/main`)

| File | What it does |
|---|---|
| `nvim/lua/hcmux/core.lua` | the `hc` CLI and JSON-RPC (`hc connect`), the live `hc events` cache, core documents (`doc.get`/`doc.set`) |
| `nvim/lua/hcmux/term.lua` | terminal buffers are views (`hc attach`). Covers splits, tabs, floats, lazy placeholders, answering OSC 10/11/12 color queries, and starting at the window's size and colors |
| `nvim/lua/hcmux/session.lua` | sessions in herdr-core: doc `nvs.<name>` plus `nvs-index`, debounced autosave, quit = detach, `:detach`/`:qd`, `:reload`, read-only/take-over through doc versions |
| `nvim/lua/hcmux/session-bridge.lua` | the `hc://` buffer scheme: saved layouts re-attach to live terminals |
| `nvim/lua/hcmux/picker.lua`, `init.lua` | the picker, `:Hc`, keys, statusline |
| `nvim/lua/hcmux/desk.lua` | the `<leader>h` agents (REP Claude, help desk) |
| `nvim/lua/hcmux/session_cli.lua`, `nvim/bin/nvim-session`, `nvim/bin/envi` | the shell side |
| `nvim/lua/plugins/hcmux.lua` | spec, keys, lualine; persistence.nvim disabled |
| `nvim/lua/plugins/opencode.lua` | the AI session manager now launches through hcmux (`[RUN]` = still running in core) |
| `nvim/lua/plugins/auto-session.lua` | deleted |

## How to iterate

1. **Edit only in a worktree, never in `~/.dotfiles`.** The main checkout
   is production and carries the owner's own uncommitted work. Run your
   worktree with `envi-dev`.
2. **Reload:** commits reload every running envi on their own (hot reload, see the
   hcmux README); otherwise the user runs `:reload`. It saves and detaches the session, quits
   nvim, and the launcher (which stays as nvim's parent, writing the
   session name to `$ENVI_RELOAD_FILE`) starts it again on that session.
   Nothing is lost: the session and terminals persist. It only works in an nvim
   started by `envi` or `envi-dev`; otherwise `:qd`, then `envi`.
3. **Verify end to end by hand, with cua-driver in the Herdr app** (the user's
   standard). Headless tests aren't enough on their own. The full procedure is
   `~/.local/state/envi/charters/e2e-standard.md`. In short:
   - Take the E2E lock: `mkdir ~/.local/state/envi/e2e.lock`.
   - Use cua-driver through executor (`tools.cua_driver.org.default.*`), bound
     to the Herdr window.
   - Open your **own** new tab with the tab bar `+`, then type
     `ENVI_SESSION=e2e-<slug> envi-dev <worktree>` there (session
     `dev-e2e-<slug>`). Never use the user's `dotfiles` session, production
     `envi`, or anyone else's tab.
   - Drive it only with real keys and clicks (`press_key`, `hotkey`,
     `type_text`, `click`), with a fresh screenshot after each step.
   - Don't drive envi with `nvim --remote-send`, `hc keys` or `hc send`.
     Read-only `hc read` and read-only RPC state are fine as extra evidence.
   - Clean up: `:qa!`, `envi-dev kill dev-e2e-<slug> -f`, close your tab, re-focus the
     user's tab, then release the lock.
4. **Format:** `~/.local/share/nvim/mason/bin/stylua --config-path nvim/stylua.toml nvim/lua/hcmux nvim/lua/plugins`.
5. **Commit only when the user says so,** using Conventional Commits.

Known limits: `:mksession` doesn't keep plain `:terminal` buffers or
neo-tree. Unsaved edits aren't stored. A lone `Ctrl+\` that times out
detaches an `hc attach` view (harmless).

## Cutover (one time: envi from slot 2 → production)

REP runs this with the owner, once. `envi-migrate` (in `nvim/bin`) does the
state and link steps. Before its first write it checks:
- no nvim runs (a failed process query also refuses);
- every path it touches (state, staging, backup, `~/.config`, `~/.local/bin`,
  `~/.dotfiles/nvim`) and each ancestor up to `$HOME` is a real folder, outside
  the envi state;
- the production launchers, and every helper they exec (`nvim-session`), are
  executable, what they source is readable, and the production config exists;
- both device ids can be read and match, so the state swap is a rename.

Every helper's failure fails the command, and `APPLIED`/`ROLLED_BACK` are
written only after every step succeeded. The backup
(`~/.backups/envi-migrate-<time>-<id>/`, manifest `format=2`) is complete
before any change: it is built as `<backup>.init` and renamed, and a leftover
`.init` of exactly this tool's form (`envi-migrate-<time>-<id>.init`, holding at
most its manifest; a run killed right at the start) is removed by the next
run. Other folders in `~/.backups` are never touched.
`--dry-run` shows the plan; running it again changes nothing.

**Accepted limitations:** another process changing these files *during* the
run, and hand-edited contents of a backup this tool wrote, are out of scope. Run it once, with the owner present and every editor
closed.

1. **Before.** This branch is merged and `~/.dotfiles` is fast-forwarded to
   `main` (never over the owner's uncommitted work). Review the local edits
   that become production with the owner:
   `git -C ~/.dotfiles status --short -- nvim/`. envi behaves differently after
   the cutover by exactly those edits (for example `nvim/lua/plugins/neo-tree.lua`);
   slot 2 never had them. `~/.dotfiles/nvim/tools/t3-thread/node_modules` must
   exist (else `npm ci` there).
2. **Every nvim closes:** the owner leaves envi with `:qd` (the session and
   its terminals keep running) and closes any plain `nvim` and dev nvim too.
   `pgrep -x nvim` prints nothing.
3. **Migrate:** `~/.dotfiles/nvim/bin/envi-migrate --dry-run cutover`, read it,
   then `~/.dotfiles/nvim/bin/envi-migrate cutover`. It copies
   `~/.local/state/nvim` to a staging folder next to it, lays envi's `shada/`,
   `undo/`, `hcmux/` and `envi-hotreload.*` over the copy (envi's file wins: it
   is the owner's daily editor), then swaps it in; the old folder moves to
   `<backup>/state-nvim`. `~/.local/state/envi` is only read: the T3
   credential, swap files and dev leftovers stay there.
4. **Links** (same command): `~/.config/nvim` → `~/.dotfiles/nvim`,
   `~/.local/bin/envi` → `~/.dotfiles/nvim/bin/envi`, `~/.local/bin/envi-dev` →
   `~/.dotfiles/nvim/bin/envi-dev`; the `~/.config/envi` link is removed.
5. **`envi`** reattaches the `dotfiles` session with its terminals alive
   (`hc ls --label herdr.nvs=dotfiles`). **`:Reload`** comes back on it.
6. **T3 panes reconnect:** the running T3 clients never stop. They keep the
   same credential file and are reattached by name. They still run slot 2's
   `tools/t3-thread`, so leave slot 2 in place while they run. `:T3Restart`
   refuses them as unverified (another `main.mjs` path); close the pane and open
   the thread again to move one onto production code.

**Rollback:** close every nvim, then `~/.dotfiles/nvim/bin/envi-migrate rollback`
(pass a backup, or none: it then takes the only backup not yet rolled back,
and refuses if there are several or one it cannot validate, naming every
candidate and each one's error; an unreadable `~/.backups` also refuses, never
"no backup"). Run it with the cutover's `HOME`, `XDG_STATE_HOME` and
`XDG_CONFIG_HOME`: the manifest records the state and link paths, and rollback
refuses, before any change, a backup made for other ones. It moves the current `~/.local/state/nvim`,
post-cutover edits and all, to `<backup>/rollback-displaced/nvim` (never over
an earlier one), moves `<backup>/state-nvim` back, and restores the links
exactly (`~/.config/envi` → slot 2, `~/.local/bin/envi` through it, no
`envi-dev`). If a link path now holds a real file or folder, rollback fails,
leaves it alone, and can be run again once it is moved aside. An interrupted
cutover or rollback is finished the same way: run `envi-migrate rollback`
again; a new cutover refuses until then. Rollback refuses, without touching
markers or state, a backup without a manifest, with another format, with a
missing or corrupt field, or with a linked or foreign path inside it.
`envi` is then slot 2's envi on its
untouched `envi` profile. Sessions live in herdr-core and are the same either way.

## Where this is going

An agentic Neovim, anchored on herdr-core: nvim is the cockpit, and
herdr-core runs and remembers everything (terminals, agents, sessions).
Likely next steps, decided with the user one at a time:

- Agents as first-class panes: status in the bufferline, jump to the next
  agent that's `blocked`/`done`, and send a selection or diagnostics to an agent.
- More `<leader>h` slots, with agents configured in `desk.lua`.
- The help desk learning new features as they land (it reads this file and
  the README).
- Sessions across machines (`hc --on`, `doc.get on`).

---

## Handoff charter: REP | dotfiles

**Role:** you are the **REP | dotfiles** agent, the user's main agent for
iterating on envi from here on. Another Claude session built everything
above and handed over to you.

**Objective now:** take over this context, and be ready to iterate quickly
with the user on the agentic Neovim configuration.

**Read first:** this file, `nvim/lua/hcmux/README.md`, and skim
`nvim/lua/hcmux/{session,term,desk}.lua` and `nvim/lua/plugins/hcmux.lua`
in the worktree.

**Scope:**
- Edit only in the worktree, on branch `envi/main`.
- Don't commit, merge, push, return the worktree lease, or touch the main
  `~/.dotfiles` checkout unless the user asks.
- Don't `hc kill` terminals you didn't start.
- Don't stop or restart the herdr-core server.

**Validation habit:** the "How to iterate" steps above. A change counts as done
once it has been seen working in a real nvim.

**Deliverable for this message:** reply with
1. a five-line summary of what envi is,
2. `git status --short` of the worktree, to confirm you see the same state,
3. any questions.

Then **stop and wait** for the user's first instruction. Don't start new
work on your own.
