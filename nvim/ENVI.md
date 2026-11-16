# envi: experimental nvim

envi is where the agentic Neovim configuration is developed: nvim as a terminal
multiplexer and session manager on top of **herdr-core** (`hc`), with agents
one key away. It runs from a stable worktree, so the daily `nvim` stays
untouched until a change is committed and merged.

## The setup

| Part | Where |
|---|---|
| Worktree (stable; all edits happen here) | `~/.dotfiles/.treehouse/.dotfiles-0c8f72/2/.dotfiles` |
| Branch | `envi/main` (local, no upstream). The lease holder is `claude-hcmux` |
| nvim profile | `NVIM_APPNAME=envi`: `~/.config/envi` points to the worktree's `nvim/`; `~/.local/share/envi` points to `~/.local/share/nvim` (plugins are shared) |
| Command | `envi` (`~/.local/bin/envi` points to `nvim/bin/envi`) |
| Session | `envi` attaches to the herdr-core session **`dotfiles`**, running in `~/.dotfiles` |

`envi` with no arguments opens the session. `envi <file>` opens files with no
session. `envi ls` and `envi kill <name>` manage sessions. Inside, `:detach` or
`:qd` leaves; everything keeps running in herdr-core. `:reload` (or `:Reload`)
detaches and starts envi again on the same session, so config, plugin and
launcher changes take effect. It asks first about unsaved buffers.

## Keys added for envi

| Keys | What |
|---|---|
| `<leader>ha` | **agent**: the AI tool picker (was `<leader>oai`). The chosen tool starts fresh in nvim's cwd, in a vsplit pane of the current herdr-core session. Resuming an old session opens it in the folder it was made in |
| `<leader>hi` | the **REP \| dotfiles** T3 thread in the T3 popover (85%, `hcmux/t3.lua`). It opens or focuses, and switches the shown popover to this thread in place; it never hides. **INSERT** types into the thread; `<Esc>` or `<C-]>` goes to **COMMAND** and never forwards a raw Esc (it sends the TUI's private *dismiss*, which closes a dialog, the model picker or a menu and can't interrupt). **COMMAND**: `i`/`a`/`I`/`A`/`<C-]>` back to INSERT, `j`/`k` scroll, `m` model picker, `c` compact (y/n), `<C-c>` interrupt (y/n), `q` hide (the only way), `<Esc>` no-op. `:T3Restart` restarts the client (needed once for clients started before *dismiss* existed). The T3-layout main pane uses the same keys, except `q` does nothing there |
| `<leader>h?` | **keybinder**: a T3 thread for config changes and questions about envi. It toggles the popover, like `<leader>hi` |
| `<leader>a` | **AGENT** board (`hcmux/agent.lua`): a big popover of this project's T3 threads in a 3x3 grid, slots 1-9. Slots you mark stay put; the rest fill from T3's pinned + sidebar order (dimmed, `auto`; settled threads never auto-fill). Then `1`-`9` (or `hjkl` + `Enter`/`o`) opens that thread in the T3 popover, like `<leader>hi`; `i` starts a new thread in COMMAND; `/` fuzzy-searches thread names in insert mode (Esc → normal, `j`/`k` through the hits, settled and oldest last); `m`+digit marks the selected thread into that slot, `x` clears a mark; `Tab` switches board/search; `R` refresh, `?` help; `q` (or `<leader>a`, or `Esc` on the board) closes. Marks persist per session. lualine reads `AGENT` while it's open |
| `<leader>gp` | **PR viewer** (`hcmux/prs.lua`, replaces LazyVim's Snacks PR picker on this key; `<leader>gP` is still Snacks' all-states picker): a big float of open PR cards via `gh`. `Tab`/`S-Tab` cycle scopes Repo / Review / Mine / Involved (opens on Involved when the session repo has none). `j`/`k`, `gg`/`G`, `<C-d>`/`<C-u>` move; `Enter`/`l` review in **hunk** (a terminal float; `<C-q>` there hides it and returns to the board, keeping drafts; hunk's `q` quits it); `/` fuzzy search (INSERT; `Esc` → NORMAL, `Enter` reviews the top hit); `K` details; `o` browser; `y` yank URL; `c` checks; `r` refresh; `R` pick the Repo-scope repo; `s` submit your hunk comments as a review (confirm first: comment / approve / request changes); `x` discard drafts and end that PR's hunk; `?` help; `q`/`Esc` close. lualine reads `PR` while it's open |
| `<leader>hv` | **layout switcher**: `nvim` or `T3` (`hcmux/layout.lua`). Each layout is its own tab page |
| `<leader>hw` / `:EnviBoard [file]` | **whiteboard** (`hcmux/board.lua`): a read-only 90% × 85% popover rendering a `*.wb.md` board. In a `*.wb.md` buffer it opens (or focuses) that board; elsewhere it closes the shown board, reopens the last one, or asks for a file. `:EnviBoard` completes file names and defaults to the current buffer. Inside (board.lua's keys): normal motions/search/yank; `[s`/`]s` jump headings; `Tab` outline; `s` find the exact Mermaid source; `Enter` on a source record opens its commit bytes read-only; `e` edits the board file at that line; `R` refresh; `?` help; `q` close (`Esc` doesn't close; in a child, `q`/`Esc` dismiss only the child). No repo trust is passed, so source pins stay untrusted unless opened with `bindings.repo` from Lua. lualine reads `BOARD` while it's open |
| `<leader>b` | in the T3 tab, show/hide the thread sidebar from any normal window (buffer-local nowait, so `<leader>b*` buffer keys don't apply there); elsewhere, including the popover, the LazyVim buffer group as before (`<leader>bd`, `<leader>bb`, … unchanged) |
| `<leader>hn` | **help desk**: pi on `j5/gpt-6-luna` in a centered float (65%). It's read-only, fresh each time it starts, and given the live keymaps. `q`/`<Esc>` hide it |
| `<C-\>` + key (normal and terminal mode), `<leader>m` | hcmux: `c v s t` new shell, `w` pick, `d` detach, `x` kill, `hjkl`, `z` zoom, `a` AI tools |
| `<leader>qs` / `qd` / `qr` / `qt` | sessions: pick, detach, rename, take over |

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

1. **Edit only in the worktree.** Never edit `~/.dotfiles` itself. Its
   checkout has the user's own uncommitted work (including Pi additions to
   `opencode.lua`, which apply cleanly on top of this branch).
2. **Reload:** commits reload every running envi on their own (hot reload, see the
   hcmux README); otherwise the user runs `:reload`. It saves and detaches the session, quits
   nvim, and the `envi` launcher (which stays as nvim's parent, writing the
   session name to `$ENVI_RELOAD_FILE`) starts envi again on that session.
   Nothing is lost: the session and terminals persist. It only works in an nvim
   started by `envi`; otherwise `:qd`, then `envi`. For a test run of the
   launcher, `ENVI_SESSION=envi-test envi` picks the session.
3. **Verify end to end by hand, with cua-driver in the Herdr app** (the user's
   standard). Headless tests aren't enough on their own. The full procedure is
   `~/.local/state/envi/charters/e2e-standard.md`. In short:
   - Take the E2E lock: `mkdir ~/.local/state/envi/e2e.lock`.
   - Use cua-driver through executor (`tools.cua_driver.org.default.*`), bound
     to the Herdr window.
   - Open your **own** new tab with the tab bar `+`, then type
     `ENVI_SESSION=e2e-<slug> envi` there. Never use the user's `dotfiles`
     session or anyone else's tab.
   - Drive it only with real keys and clicks (`press_key`, `hotkey`,
     `type_text`, `click`), with a fresh screenshot after each step.
   - Don't drive envi with `nvim --remote-send`, `hc keys` or `hc send`.
     Read-only `hc read` and read-only RPC state are fine as extra evidence.
   - Clean up: `:qa!`, `envi kill e2e-<slug> -f`, close your tab, re-focus the
     user's tab, then release the lock.
4. **Format:** `~/.local/share/nvim/mason/bin/stylua --config-path nvim/stylua.toml nvim/lua/hcmux nvim/lua/plugins`.
5. **Commit only when the user says so,** using Conventional Commits.

Known limits: `:mksession` doesn't keep plain `:terminal` buffers or
neo-tree. Unsaved edits aren't stored. A lone `Ctrl+\` that times out
detaches an `hc attach` view (harmless).

Still to do at merge time: link `~/.local/bin/nvim-session`; repoint
`~/.local/bin/envi` and `~/.config/envi` at `~/.dotfiles`; run `:Lazy clean`
so the lockfile drops auto-session and persistence. The `herdr/app/omarchy`
submodule shows as modified in the worktree; that isn't ours, so leave it alone.

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
