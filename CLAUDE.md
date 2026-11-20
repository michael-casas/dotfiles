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
# Install dependencies (Herdr is installed separately from https://herdr.dev)
brew install bash bash-completion@2 starship pyenv nvm fzf fd neovim

# Homebrew Bash is the canonical login shell
sudo sh -c 'echo /opt/homebrew/bin/bash >> /etc/shells'
chsh -s /opt/homebrew/bin/bash
```

## Repository Structure

- `setup.sh` — Symlink installer
- `bash/.bashrc` — Shell (Homebrew Bash, the canonical login shell; machine-local values go in `~/.config/bash/local.bash`)
- `nvim/` — Editor (LazyVim)
- `herdr/config.toml` — Daily multiplexer (Bash login shells)
- `git/.gitconfig` — Git config
- `starship/starship.toml` — Prompt
- `.agent/SYSTEM.md` — Full documentation

