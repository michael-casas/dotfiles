#!/usr/bin/env bash
# Dotfiles setup script for macOS
# Run this after cloning the repo to ~/.dotfiles

set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles"

echo "==> Setting up dotfiles from $DOTFILES_DIR"

# --- Fish Shell ---
if [[ -d "$DOTFILES_DIR/fish" ]]; then
    echo "==> Linking fish config..."
    mkdir -p "$HOME/.config/fish"
    ln -sf "$DOTFILES_DIR/fish/config.fish" "$HOME/.config/fish/config.fish"
fi

# --- Neovim ---
if [[ -d "$DOTFILES_DIR/nvim" ]]; then
    echo "==> Linking nvim config..."
    mkdir -p "$HOME/.config"
    # Remove old nvim config if it's not a symlink to our dotfiles
    if [[ -d "$HOME/.config/nvim" && ! -L "$HOME/.config/nvim" ]]; then
        echo "    Backing up existing ~/.config/nvim to ~/.config/nvim.backup"
        mv "$HOME/.config/nvim" "$HOME/.config/nvim.backup"
    fi
    ln -sfn "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
fi

# --- Tmux ---
if [[ -f "$DOTFILES_DIR/tmux/tmux.conf" ]]; then
    echo "==> Linking tmux config..."
    ln -sf "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
fi

# --- Git ---
if [[ -f "$DOTFILES_DIR/git/.gitconfig" ]]; then
    echo "==> Linking git config..."
    ln -sf "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
fi

# --- Starship ---
if [[ -f "$DOTFILES_DIR/starship/starship.toml" ]]; then
    echo "==> Linking starship config..."
    ln -sf "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
fi

# --- Ghostty (macOS) ---
if [[ -f "$DOTFILES_DIR/ghostty/config" ]] && [[ "$OSTYPE" == darwin* ]]; then
    echo "==> Linking ghostty config..."
    GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
    mkdir -p "$GHOSTTY_DIR"
    ln -sf "$DOTFILES_DIR/ghostty/config" "$GHOSTTY_DIR/config"
fi

echo "==> Done!"
echo ""
echo "Next steps:"
echo "  1. Add fish to /etc/shells:  sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'"
echo "  2. Change default shell:      chsh -s /opt/homebrew/bin/fish"
echo "  3. Restart your terminal or run: exec fish"
