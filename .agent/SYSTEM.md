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

## Repository Structure
```
.fish/config.fish          -> ~/.config/fish/config.fish
nvim/                       -> ~/.config/nvim (LazyVim-based)
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

## Machine-Specific Configs
- Android SDK paths (`~/Library/Android/sdk`)
- pyenv root (`~/.pyenv`)
- nvm (`~/.nvm` via Homebrew)
- Bun (`~/.bun`)
- OpenCode (`~/.opencode`)
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

## Notes
- `bass` plugin needed for nvm compatibility in fish (or migrate to nvm.fish)
- Old shell/config.fish preserved in git history but replaced by fish/config.fish
- Old nvim/init.vim replaced by LazyVim lua config
