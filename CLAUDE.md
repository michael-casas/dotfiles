# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

This is a personal dotfiles repository. After cloning to `~/.dotfiles`:

```bash
bash ~/.dotfiles/setup.sh
```

For detailed architecture, tool integration, commit conventions, and keybindings, see `.agent/SYSTEM.md`.

## Key Commands

```bash
# Install dependencies
brew install fish starship pyenv nvm fzf tmux neovim

# Set fish as default shell
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish

# Install tmux plugins (inside tmux)
# prefix + I
```

## Repository Structure

- `setup.sh` — Symlink installer
- `fish/config.fish` — Shell
- `nvim/` — Editor (LazyVim)
- `tmux/tmux.conf` — Multiplexer
- `git/.gitconfig` — Git config
- `starship/starship.toml` — Prompt
- `.agent/SYSTEM.md` — Full documentation

## Commit Format

Use conventional commits: `feat(tool)`, `fix(tool)`, `refactor(tool)`, etc.
