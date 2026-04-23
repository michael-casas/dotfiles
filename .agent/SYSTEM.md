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
- **tmux**: Config uses TPM with resurrect + continuum

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
brew install fish starship pyenv nvm

# Activate dotfiles
bash ~/.dotfiles/setup.sh

# Set fish as default shell
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish
```

## Commit History
- `5ea1313` feat!: symlinks and base config restored — Initial migration from zsh to fish, LazyVim annex, tmux.conf fix, setup.sh creation
- `TBD` feat: add starship prompt config — Install Starship via Homebrew, add Gruvbox-themed starship.toml, wire into setup.sh

## Notes
- `bass` plugin needed for nvm compatibility in fish (or migrate to nvm.fish)
- Old shell/config.fish preserved in git history but replaced by fish/config.fish
- Old nvim/init.vim replaced by LazyVim lua config
