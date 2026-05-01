# Dotfiles System Journal

## Overview
Personal dotfiles repository for Michael Casas (mcasa_atlantis). Managed via a bare git repo at `~/.dotfiles` with symlink-based activation.

## Platform
- Primary: macOS (Apple Silicon, Homebrew at `/opt/homebrew`)
- Historical: WSL (Ubuntu), generic Linux/Arch

## Shell Transition
- **Previous**: zsh + Oh My Zsh → fish (via Homebrew)
- **Current**: bash 5.3 (installed via Homebrew at `/opt/homebrew/bin/bash`)
- Rationale: bash is the POSIX standard; better compatibility with existing scripts, CI, and remote environments. Starship provides identical prompt visuals across shells.

### Set bash as default shell
```bash
sudo sh -c 'echo /opt/homebrew/bin/bash >> /etc/shells'
chsh -s /opt/homebrew/bin/bash
```
> Run both commands, then open a new terminal. `exec bash` will no longer be needed.

## Repository Structure
```
bash/.bashrc                -> ~/.bashrc
bash/.bash_profile          -> ~/.bash_profile
nvim/                       -> ~/.config/nvim (LazyVim-based)
  lua/plugins/opencode.lua  # Multi-tool AI session manager (OpenCode, Codex, Claude, Kiro)
tmux/tmux.conf              -> ~/.tmux.conf
git/.gitconfig              -> ~/.gitconfig
starship/starship.toml      -> ~/.config/starship.toml
claude/settings.json        -> ~/.claude/settings.json  # Claude Code config + statusline
claude-swap/                -> ~/.claude-swap            # claude-swap profile store
_claude-swap/               # standalone claude-swap source repo (ignored by parent git)
setup.sh                    # Symlink installer
```

## Prompt
- **Starship** (Rust-based, cross-shell prompt)
- Config: `starship/starship.toml` with Gruvbox Dark palette
- Auto-detects git, language versions, Docker context, conda envs

## Bash UX Enhancements
Bash by default is bare compared to fish. Three plugins close the gap:

### ble.sh (Bash Line Editor)
Fish-like line editing for bash: syntax highlighting, auto-suggestions, menu completion, vim/emacs keymaps.
- **Install**: `~/.local/share/blesh/ble.sh` (single tarball, no runtime deps)
- **Config**: `bash/.blerc` → `~/.blerc`
- **Features enabled**:
  - `complete_auto_complete=1` — auto-suggest from history/completions
  - `complete_menu_complete=1` — menu-style tab completion
  - `complete_auto_history=1` — auto-fill common prefixes
  - `highlight_syntax=1` — command/argument/string syntax coloring
  - `highlight_filename=1` — file type coloring
   `highlight_variable=1` — variable name coloring
  - `prompt_ps1_transient=trim` — clean prompt after Enter (starship owns the prompt)

### bash-completion@2
Tab completions for common CLI tools (git, docker, brew, npm, etc.). Bash 5+ requires `@2`; the old `bash-completion` formula is for bash 3.2.
- **Source**: `/opt/homebrew/etc/profile.d/bash_completion.sh`

### fzf bash bindings
Fuzzy history search (`Ctrl-R`), fuzzy file/path completion (`Ctrl-T`, `Alt-C`), and trigger-based completion (`**<Tab>`).
- **Source**: `/opt/homebrew/opt/fzf/shell/key-bindings.bash` + `completion.bash`

## Key Migrations
- **nvim**: Migrated from old vimscript init.vim + lsp.lua to LazyVim (lua-based)
- **shell**: Migrated fish → bash 5.3 (Homebrew); translated PATH, aliases, functions, and env vars. Prompt remains identical via starship.
- **tmux**: Config uses TPM with resurrect + continuum + tmux-fzf + tmux2k
- **tmux2k**: Gruvbox-themed status bar with session, git, cpu, ram, battery, time
- **tmux default shell**: Changed to bash for all new panes/windows
- **nvim colorscheme**: Gruvbox Dark Hard (`ellisonleao/gruvbox.nvim`)
- **nvim + AI Session Manager**: Higher-order `snacks.nvim` picker factory supporting OpenCode, Codex, Claude, and Kiro with buffer tracking and unified tool selector

## Machine-Specific Configs
- Android SDK paths (`~/Library/Android/sdk`)
- pyenv root (`~/.pyenv`)
- nvm (`~/.nvm` via Homebrew)
- Bun (`~/.bun`)
- OpenCode (`~/.opencode`)
- LM Studio (`~/.lmstudio`, local API at `localhost:1234`)
- LM Studio (`~/.lmstudio`)

## Dependencies
- `bash` — shell (Homebrew 5.3+)
- `starship` — prompt
- `bash-completion@2` — tab completions for common CLI tools (bash 5+ compatible)
- `ble.sh` — Bash Line Editor; fish-like syntax highlighting, auto-suggestions, menu completion
- `pyenv` — Python version manager
- `nvm` — Node version manager
- `fzf` — fuzzy finder
- `fd` — fast file finder (required by snacks.nvim explorer)
  - Global ignore file: `fd/ignore` → `~/.config/fd/ignore` (excludes `node_modules/`, `dist/`, `build/`, `.git/`, etc.)
- `pgcli` — enhanced PostgreSQL CLI with syntax highlighting + autocomplete

## Setup Commands
```bash
# Install dependencies
brew install bash bash-completion@2 starship pyenv nvm fzf fd pgcli

# Install ble.sh (fish-like line editing for bash)
mkdir -p ~/.local/share
curl -L https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJf - -C ~/.local/share
mv ~/.local/share/ble-nightly ~/.local/share/blesh
```

## Commit History
- `5ea1313` feat!: symlinks and base config restored — Initial migration from zsh to fish, LazyVim annex, tmux.conf fix, setup.sh creation
- `a7905b7` feat: add starship prompt config — Install Starship via Homebrew, add Gruvbox-themed starship.toml, wire into setup.sh
- `09e8c31` feat(tmux): direct Option key window navigation — Add M-0/1/2/3 for window switching, M-m toggle, lower escape-time
- `9680f28` feat(tmux): pane traversal, resize, and split keybindings — Add M-hjkl, C-M-arrows, C-M-h/v
- `ee12504` feat(nvim): Option bracket buffer cycling
- `96e78b1` feat(nvim): neo-tree width reduction + explicit split keymaps
- `6cf8712` feat(tmux): add tmux-fzf session manager popup
- `69dc8dc` feat(tmux): add tmux2k status bar + default-shell bash
- `2b3fb42` feat(nvim): set Gruvbox Dark Hard as LazyVim colorscheme
- `a540f56` style(ghostty): apply Gruvbox Dark Hard theme and terminal settings

## AI Session Manager (nvim)
Higher-order `snacks.nvim` picker factory (`ai_session_picker`) that parameterizes session management for any CLI tool. Each tool gets its own picker source (`{tool}_sessions`) plus a unified tool selector (`ai_tools`).

### Supported Tools
| Tool | Binary | List API | Attach | Delete |
|---|---|---|---|---|
| **OpenCode** | `~/.opencode/bin/opencode` | `session list --format json` | `-s <id>` | `session delete <id>` |
| **Codex** | `codex` | Read `~/.codex/session_index.jsonl` | `resume <id>` | Not supported |
| **Claude** | `claude` | Read `~/.claude/sessions/*.json` | `-r <id>` | Not supported |
| **Opus** | `claude-opus` | Read `~/.claude-opus/sessions/*.json` | `-r <id>` | Not supported |
| **Kiro** | `kiro-cli` | `chat --list-sessions -f json` | `chat --resume-id <id>` | `chat --delete-session <id>` |
| **Docker AI** | `docker ai` | Not supported (no sessions) | Opens TUI directly | Not supported |

### Architecture
- **Factory**: `ai_session_picker(config)` returns a full `snacks.picker.Config` table
- **Buffer tracking**: Each tool uses a namespaced buffer variable (`b:{tool}_session_id`)
- **Visual state**: `[BUF]` = already open in a buffer; `[SES]` = available but not open
- **Window behavior**: New sessions open in a full-page terminal buffer (`enew`) taking the current window
- **Split variants**: `split_cmd` variable controls window split — `vsplit`, `split`, or `enew`

### Entry Points
| Trigger | Action |
|---|---|
| `:AI` | Open AI tool selector (current window) |
| `:AIV` | Open AI tool selector (vertical split) |
| `:AIH` | Open AI tool selector (horizontal split) |
| `<leader>oai` | Open AI tool selector (current window) |
| `<leader>oaiv` | Open AI tool selector (vertical split) |
| `<leader>oaih` | Open AI tool selector (horizontal split) |
| `<leader>oaic` | Open AI tool selector (current window) |
| `:OpenCode` / `<leader>oc` | OpenCode mode menu |
| `:Codex` / `<leader>od` | Codex mode menu |
| `:Claude` / `<leader>ol` | Claude mode menu |
| `:Opus` / `<leader>oo` | Opus mode menu |
| `:Kiro` / `<leader>ok` | Kiro mode menu |
| `:Docker` / `<leader>og` | Docker AI (Ask Gordon) — no session persistence |
| `:AskAI` / `<leader>oask` | Ask Support agent (popup → terminal buffer) |
| `:AskDjango` / `<leader>ofc` | Ask Django Systems Architect agent (popup → terminal buffer) |
| `<leader>nxg` | Nx generators picker |
| `<leader>nxr` | Nx task runner picker |
| `<leader>osql` | SQL actions (run file / psql shell) — requires `.sql` buffer |
| `<leader>qs` | Search saved nvim sessions |
| `<leader>qS` | Manually save nvim session |

### Flow
1. **Tool Selector** (`:AI`) → pick tool
2. **Mode Menu** → pick `Create New Session` or `Resume Session`
3. **Resume** → session list picker (same as before)

### Window Split Behavior
A shared `split_cmd` variable controls how new terminal buffers are opened. All entry points explicitly set it before launching the picker:
- **Current window** (`enew`) — default for `:AI`, `<leader>oai`, `<leader>oaic`, and direct tool shortcuts
- **Vertical split** (`vsplit`) — `:vAI`, `<leader>oaiv`
- **Horizontal split** (`split`) — `:hAI`, `<leader>oaih`

### Picker Actions (session list)
| Key | Action |
|---|---|
| `<CR>` | Jump to existing buffer, or open new terminal for session |
| `<C-d>` | Delete selected session (if tool supports it) |

### Sorting
Sessions are sorted by `updated` descending (most recent first) across all tools. The factory normalizes timestamps:
- **Numeric ms** (OpenCode, Claude) — used directly
- **ISO 8601 strings** (Codex) — parsed via `vim.fn.strptime`
- **String numbers** — coerced via `tonumber`
- Missing/invalid dates sink to the bottom.

## LazyVim Keymap Regression Fix (2026-04-24)
**Issue:** After pressing `<Esc>` to exit insert mode, quickly pressing `j`/`k` moved the current line instead of moving the cursor. Spamming `<Esc>` prevented it.  
**Root cause:** `ttimeoutlen = 500` in `options.lua`. Terminals encode `Alt-j` as the byte sequence `<Esc>j`. With a 500ms timeout, Neovim waited after `<Esc>` to see if more characters followed. If `j` arrived within that window, Neovim interpreted `<Esc>j` as `<M-j>` — which LazyVim binds to "move line down".  
**Fix:** Reduced `ttimeoutlen` from `500` to `10` in `lua/config/options.lua`. This makes `<Esc>` process immediately, breaking the sequence before the next keystroke arrives. The 10ms delay is imperceptible but sufficient to distinguish standalone `<Esc>` from terminal escape sequences.

## Tmux Keybinding Layers
| Modifier | Key | Action |
|---|---|---|
| `M-0/1/2/3` | number | Switch to window 0/1/2/3 |
| `M-m` | letter | Toggle window 0 ↔ last-window |
| `M-h/j/k/l` | vim | Pane traversal |
| `C-M-↑/↓/←/→` | arrows | Resize pane by 2 cells |
| `C-M-h` | letter | Horizontal split |
| `C-M-v` | letter | Vertical split |

## Conventions
- **Commitlint syntax**: `feat` reserved for new plugins/features only. Default to `fix`, `refactor`, `docs`, or `style` for adjustments.

## Support Agent (OpenCode)
A persistent, quick-Q&A agent backed by a local LM Studio model (Gemma 4). Runs via `opencode serve` to avoid MCP cold boot on every query.

### Architecture
1. **`opencode serve --port 4096`** — headless server running in a tmux window named "support"
2. **`ask "prompt"`** (shell) — `opencode run --attach http://localhost:4096 --agent Support --session <id>`
3. **`:AskAI` / `<leader>oask`** (nvim) — popup input → same `run --attach` command in terminal buffer
4. **Session tracking** — `opencode session list --format json` is queried each time; the most recent session titled "Support" is reused. If none exists, a new one is created with `--title "Support"`.

### Why `serve` + `run --attach`?
- `serve` keeps the backend warm (no MCP/LSP cold boot per query)
- `run --attach` creates **local** sessions that appear in `opencode session list`, so they show up in the nvim `:AI` picker alongside other OpenCode sessions
- One-shot `run` returns the answer and exits; follow-ups go to the same session thread

### Entry Points
| Trigger | Action |
|---|---|
| `support-serve` (bash) | Start `opencode serve` in a new tmux window |
| `ask "<prompt>"` (bash) | Send prompt to Support agent via attached server |
| `:AskAI` / `<leader>oask` (nvim) | Popup prompt → terminal buffer with response |

### Start Commands
```bash
# In a tmux session
support-serve

# From anywhere (after server is running)
ask "What's the tmux hotkey for vertical split?"
```

## Django Systems Architect Agent (OpenCode)
A long-lived systems architect agent running via `opencode serve` on port 2313. Auto-starts in bash shell on every new shell session.

### Architecture
1. **`opencode serve --port 2313`** — headless server auto-started by bash config via `nohup` if not already running
2. **`:AskDjango` / `<leader>ofc`** (nvim) — popup input → `opencode run --attach http://localhost:2313 --agent django-systems-architect` in terminal buffer
3. **Session tracking** — same pattern as Support agent: reuses session titled "Django" if exists

### Entry Points
| Trigger | Action |
|---|---|
| Auto-start (bash) | `nohup opencode serve --port 2313 --hostname 127.0.0.1` on shell init |

### Why port 2313?
Hardcoded to avoid collision with Support (4096) and any other services. The bash config checks `pgrep` before starting to prevent duplicate processes.

## Snacks.nvim Explorer Configuration
The explorer (`<leader>e`) and file picker (`<leader>ff`) show **all files including hidden dotfiles**, while excluding common build/dependency directories.

### Mechanism
1. **Fish alias** (`alias fd="fd --hidden"`) — ensures `fd` always surfaces hidden files by default
2. **Global `fd` ignore file** (`~/.config/fd/ignore`) — `fd` reads this automatically. Excludes: `node_modules/`, `dist/`, `build/`, `.git/`, `.next/`, `out/`, `target/`, `coverage/`, `*.log`

This means the explorer shows every file in the directory tree except the ignored noise directories.

## Nx Integration (snacks.nvim pickers)
Lightweight Nx workspace integration without installing telescope-based `nx.nvim`. Uses `snacks.picker` custom sources that shell out to `npx nx`.

### Entry Points
| Trigger | Action |
|---|---|
| `<leader>nxg` | List Nx generators (`nx list`) → run selected in terminal |
| `<leader>nxr` | List Nx projects + targets (`nx show projects`) → run selected in terminal |

### How it works
- Detects Nx workspace by checking `package.json` for `nx` dependency
- Task runner: runs `nx show projects --json`, then `nx show project <name> --json` to enumerate targets
- Generators: parses `nx list` output for `plugin:generator` lines
- Selection opens a terminal buffer running `nx generate` or `nx run`

## PostgreSQL Interactive Workflow (pgcli)
`pgcli` (enhanced psql with syntax highlighting + autocomplete) is used via an interactive nvim workflow. No auto-login files — credentials are prompted per-session and cached in-memory.

### pgcli Features
- **Syntax highlighting** via Pygments (`monokai` theme, Gruvbox-aligned custom colors)
- **Autocomplete** for tables, columns, keywords
- **Multi-line mode** enabled (`multi_line = True`)
- **Less chatty** startup (`less_chatty = True`)
- **Gruvbox color palette** for completion menu, toolbar, table output

### Files
| File | Purpose | In dotfiles? |
|---|---|---|
| `~/.config/pgcli/config` | pgcli theme + behavior config | ✅ `pgcli/config` |
| `~/.pg_service.conf` | Optional named connection profile `[goldseed]` | ✅ `postgres/.pg_service.conf` |

### Flow
1. Open a `.sql` file in nvim
2. Press `<leader>osql` → action picker
3. Choose **"Run current file in pgcli"** or **"Launch pgcli shell"**
4. Prompted for: **Host** → **Port** → **User** → **Password**
5. Nvim lists all databases via `psql` non-interactively
6. Select database from snacks picker
7. File runs / shell opens with selected database

### Credential caching
Last-used credentials are cached per nvim session (Lua variable `pg_conn`). Re-running `<leader>osql` pre-fills the previous values — edit or press Enter to reuse.

### Verify
```bash
pgcli
# → launches interactive pgcli (manual connection)
```

## SQL Runner (nvim)
Execute `.sql` files directly from nvim via async `pgcli` jobs with interactive credential flow. Works from **any buffer** — no `.sql` file requirement to open the picker.

### Entry Point
| Trigger | Action |
|---|---|
| `<leader>osql` | Open SQL action picker (universal, like `<leader>oai`) |

### Action Picker
| Option | Behavior |
|---|---|
| ▶ Run current file in pgcli | Prompt credentials → list DBs → select DB → `jobstart` with `PGPASSWORD` env → floating output window |
|  Launch pgcli shell | Prompt credentials → list DBs → select DB → `termopen` with `PGPASSWORD` env → insert mode |

### Notes
- **"Run current file"** requires an open `.sql` file — if not, a toast warns you
- **"Launch pgcli shell"** works from anywhere regardless of current buffer

### Credential Prompts
1. **Host** (default: `localhost`, pre-filled from cache)
2. **Port** (default: `5432`, pre-filled from cache)
3. **User** (default: `postgres`, pre-filled from cache)
4. **Password** (pre-filled from cache)

### Output Window
- Large centered popup (80% width/height)
- Readonly scratch buffer, `filetype=text`
- `q` or `<Esc>` to close
- Shows full command, exit code, stdout/stderr

## Session Persistence (auto-session)
Nvim sessions are automatically saved on `:qall` and restored on startup via `auto-session`.

### Behavior
- **Auto-save**: On `:qall`, session is saved for the current `cwd`
- **Auto-restore**: When nvim starts in a directory with a saved session, it restores buffers, tabs, windows, folds, and terminals
- **Per-directory**: Sessions are keyed by `cwd` — each project gets its own session
- **Suppressed dirs**: `~/`, `~/Downloads`, `/`, `/tmp` — no sessions saved here

### Entry Points
| Trigger | Action |
|---|---|
| `<leader>qs` | Search saved sessions (snacks picker) |
| `<leader>qS` | Manually save nvim session |
| `<leader>qd` | Delete session |
| `:AutoSession search` | Same as `<leader>qs` |
| `:AutoSession restore` | Restore session for current directory |
| `:AutoSession save` | Save session for current directory |

### Session picker actions
| Key | Action |
|---|---|
| `<CR>` | Load selected session |
| `<C-s>` | Swap to alternate session |
| `<C-d>` | Delete selected session |
| `<C-y>` | Copy session |

## Isolated Claude Code Instance (Opus)
A fully isolated `claude-code` instance named **Opus** runs alongside the main `claude` CLI without config collision.

### Mechanism
`claude-code` is a native macOS binary that hardcodes `~/.claude/` as its config directory. True isolation is achieved via a **fake `$HOME` wrapper**:

1. **`~/.claude-opus/`** — isolated config directory (copied `.credentials.json`, `settings.json`)
2. **`~/.claude-opus-home/`** — fake home containing a symlink `.claude -> ~/.claude-opus`
3. **`~/.local/bin/claude-opus`** — wrapper script:
   ```bash
   exec env HOME="${FAKE_HOME}" /opt/homebrew/bin/claude "$@"
   ```
4. **Fish alias**: `claude-opus` → `~/.local/bin/claude-opus`

### Why this works
The binary resolves `~` via `$HOME` at runtime. By substituting `$HOME` with `~/.claude-opus-home`, the binary finds `.claude` inside that directory, which symlinks to the truly isolated `~/.claude-opus/`. The real `~/.claude/` is never touched.

### Limitations
- Both instances share the same bearer token (copied from main `.credentials.json`)
- Session state is fully isolated: main sessions live in `~/.claude/sessions/`, opus sessions in `~/.claude-opus/sessions/`

## Claude Code Statusline (claudeline)
Claude Code gets a rich ANSI statusline via [claudeline](https://github.com/fredrikaverpil/claudeline) (Go binary, single dependency-free binary).

### What it shows
- **Subscription/provider** — Pro/Max/Team/API/OAuth/Bedrock/Vertex/Foundry
- **Model name** — current Anthropic model (e.g. `sonnet[1m]`)
- **Context window** — 5-char progress bar with color zones (green/yellow/orange/red)
- **Quota usage** — 5-hour and 7-day bars with peak-hour `⚡️` indicator
- **Service status** — fire icons (`🔥▂` / `🔥▄▂` / `🔥▆▄▂`) during Anthropic disruptions
- **Session cost** — estimated spend (`-cost` flag)
- **Working directory** — last path segment (`-cwd` flag)
- **Git branch** — current branch (`-git-branch` flag)
- **Update indicator** — `↑` when a newer claudeline release exists

### Colors
Claudeline uses hardcoded ANSI zones that align well with Gruvbox:
- Smart (green), Dumb (yellow), Danger (orange), Near-compaction (red)
- No explicit "theme" setting — the warm ANSI palette is Gruvbox-compatible by design.

### Installation
```bash
# Download latest release (darwin arm64)
curl -sL "https://github.com/fredrikaverpil/claudeline/releases/latest/download/claudeline_darwin_arm64.tar.gz" | tar -xz -C ~/.local/bin
chmod +x ~/.local/bin/claudeline
```

### Configuration
`claude/settings.json` in dotfiles adds:
```json
{
  "statusLine": {
    "type": "command",
    "command": "claudeline -cwd -git-branch -cost"
  }
}
```

### Codex CLI Statusline
**Skipped.** Codex CLI is a Rust binary with no `settings.json` or plugin interface. There is no native statusline mechanism. A custom tmux segment would require polling `~/.codex/session_index.jsonl` — high effort, moderate value. Revisit if OpenAI adds statusline support upstream.

## Claude Swap
`claude-swap` is a standalone TypeScript CLI for managing Claude Code profiles. During Founder+Advisor review its source lives at `_claude-swap/` as an isolated nested git repository; the parent dotfiles repo ignores that directory and tracks only integration/docs/profile-store artifacts.

### Storage and symlink policy
- Canonical store: `~/.claude-swap`
- Dotfiles store root: `claude-swap/`
- Setup link: `~/.claude-swap -> ~/.dotfiles/claude-swap`
- Invalid typo surface: `~/.claud-swap` is never used; `claude-swap doctor` only warns if it exists.

### Generated artifact law
After profiles are imported, active Claude Code surfaces are generated from named profiles:
```txt
~/.claude/
./.claude/
./CLAUDE.md
```
The source of truth becomes:
```txt
~/.claude-swap/<profile>/global/
./.claude-swap/<profile>/local/
```
`setup.sh` still links `claude/settings.json` as a bootstrap when no `~/.claude-swap/state.json` exists. Once state exists, setup skips direct `~/.claude/settings.json` linking so it does not fight generated active config.

### Safety model
- Destructive operations create timestamped pre-op backups under `~/.claude-swap/backups/`
- Backup IDs use `YYYYMMDDTHHMMSSZ-<profile-or-unknown>-<operation>`
- `swap` moves only the active surfaces it will replace, so partial profiles preserve unrelated config
- `restore` creates a pre-restore backup before restoring another backup
- `rename` updates state references and fails if the target profile already exists
- `--dry-run` reports planned file operations and mutates nothing
- Mutating commands use `~/.claude-swap/.lock`

### Review and move-out workflow
`_claude-swap/` must stay inside dotfiles until automated tests, temp-directory smoke tests, nested repo commit, and Founder+Advisor review are complete. After approval, move it out to its own permanent project directory/repository.

## Notes
- nvm sourced directly in bash via `/opt/homebrew/opt/nvm/nvm.sh` (no bass wrapper needed)
- Old fish/config.fish preserved in git history but replaced by bash/.bashrc
- Old nvim/init.vim replaced by LazyVim lua config
