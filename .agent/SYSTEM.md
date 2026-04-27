# Dotfiles System Journal

## Overview
Personal dotfiles repository for Michael Casas (mcasa_atlantis). Managed via a bare git repo at `~/.dotfiles` with symlink-based activation.

## Platform
- Primary: macOS (Apple Silicon, Homebrew at `/opt/homebrew`)
- Historical: WSL (Ubuntu), generic Linux/Arch

## Shell Transition
- **Previous**: zsh + Oh My Zsh
- **Current**: fish (installed via Homebrew at `/opt/homebrew/bin/fish`)
- Rationale: fish has better UX out of the box; zshrc was bloated with Oh My Zsh boilerplate

### Set fish as default shell
```bash
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish
```
> Run both commands, then open a new terminal. `exec fish` will no longer be needed.

## Repository Structure
```
fish/config.fish            -> ~/.config/fish/config.fish
nvim/                       -> ~/.config/nvim (LazyVim-based)
  lua/plugins/opencode.lua  # Multi-tool AI session manager (OpenCode, Codex, Claude, Kiro)
tmux/tmux.conf              -> ~/.tmux.conf
git/.gitconfig              -> ~/.gitconfig
starship/starship.toml      -> ~/.config/starship.toml
setup.sh                    # Symlink installer
```

## Prompt
- **Starship** (Rust-based, cross-shell prompt)
- Config: `starship/starship.toml` with Gruvbox Dark palette
- Auto-detects git, language versions, Docker context, conda envs

## Key Migrations
- **nvim**: Migrated from old vimscript init.vim + lsp.lua to LazyVim (lua-based)
- **shell**: Migrated from zsh to fish; translated PATH, aliases, and env vars
- **tmux**: Config uses TPM with resurrect + continuum + tmux-fzf + tmux2k
- **tmux2k**: Gruvbox-themed status bar with session, git, cpu, ram, battery, time
- **tmux default shell**: Changed from zsh to fish for all new panes/windows
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

## Setup Commands
```bash
# Install dependencies
brew install fish starship pyenv nvm fzf bash

# Activate dotfiles
bash ~/.dotfiles/setup.sh

# Set fish as default shell
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish

# Install tmux plugins (after adding new ones to tmux.conf)
# Press prefix + I (capital I) inside tmux
```

## Commit History
- `5ea1313` feat!: symlinks and base config restored — Initial migration from zsh to fish, LazyVim annex, tmux.conf fix, setup.sh creation
- `a7905b7` feat: add starship prompt config — Install Starship via Homebrew, add Gruvbox-themed starship.toml, wire into setup.sh
- `09e8c31` feat(tmux): direct Option key window navigation — Add M-0/1/2/3 for window switching, M-m toggle, lower escape-time
- `9680f28` feat(tmux): pane traversal, resize, and split keybindings — Add M-hjkl, C-M-arrows, C-M-h/v
- `ee12504` feat(nvim): Option bracket buffer cycling
- `96e78b1` feat(nvim): neo-tree width reduction + explicit split keymaps
- `6cf8712` feat(tmux): add tmux-fzf session manager popup
- `69dc8dc` feat(tmux): add tmux2k status bar + default-shell fish
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

## Notes
- `bass` plugin needed for nvm compatibility in fish (or migrate to nvm.fish)
- Old shell/config.fish preserved in git history but replaced by fish/config.fish
- Old nvim/init.vim replaced by LazyVim lua config
