#!/usr/bin/env bash
# Dotfiles setup script for macOS
# Run this after cloning the repo to ~/.dotfiles

set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles"

echo "==> Setting up dotfiles from $DOTFILES_DIR"

# --- Bash Shell ---
if [[ -f "$DOTFILES_DIR/bash/.bashrc" ]]; then
    echo "==> Linking bash config..."
    if [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]]; then
        echo "    Backing up existing ~/.bashrc to ~/.bashrc.backup"
        mv "$HOME/.bashrc" "$HOME/.bashrc.backup"
    fi
    ln -sf "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"
fi

if [[ -f "$DOTFILES_DIR/bash/.bash_profile" ]]; then
    if [[ -f "$HOME/.bash_profile" && ! -L "$HOME/.bash_profile" ]]; then
        echo "    Backing up existing ~/.bash_profile to ~/.bash_profile.backup"
        mv "$HOME/.bash_profile" "$HOME/.bash_profile.backup"
    fi
    ln -sf "$DOTFILES_DIR/bash/.bash_profile" "$HOME/.bash_profile"
fi

if [[ -f "$DOTFILES_DIR/bash/.blerc" ]]; then
    if [[ -f "$HOME/.blerc" && ! -L "$HOME/.blerc" ]]; then
        echo "    Backing up existing ~/.blerc to ~/.blerc.backup"
        mv "$HOME/.blerc" "$HOME/.blerc.backup"
    fi
    ln -sf "$DOTFILES_DIR/bash/.blerc" "$HOME/.blerc"
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

# --- PostgreSQL ---
if [[ -f "$DOTFILES_DIR/postgres/.psqlrc" ]]; then
    echo "==> Linking psql config..."
    ln -sf "$DOTFILES_DIR/postgres/.psqlrc" "$HOME/.psqlrc"
fi

if [[ -f "$DOTFILES_DIR/postgres/.pg_service.conf" ]]; then
    echo "==> Linking pg_service.conf (optional reference)..."
    ln -sf "$DOTFILES_DIR/postgres/.pg_service.conf" "$HOME/.pg_service.conf"
fi

# --- fd (global ignore file) ---
if [[ -f "$DOTFILES_DIR/fd/ignore" ]]; then
    echo "==> Linking fd global ignore..."
    mkdir -p "$HOME/.config/fd"
    ln -sf "$DOTFILES_DIR/fd/ignore" "$HOME/.config/fd/ignore"
fi

# --- pgcli ---
if [[ -f "$DOTFILES_DIR/pgcli/config" ]]; then
    echo "==> Linking pgcli config..."
    mkdir -p "$HOME/.config/pgcli"
    ln -sf "$DOTFILES_DIR/pgcli/config" "$HOME/.config/pgcli/config"
fi

# --- Claude Code ---
if [[ -d "$DOTFILES_DIR/claude-swap" ]]; then
    echo "==> Linking claude-swap profile store..."
    CLAUDE_SWAP_TARGET="$DOTFILES_DIR/claude-swap"
    CLAUDE_SWAP_LINK="$HOME/.claude-swap"
    if [[ -e "$CLAUDE_SWAP_LINK" || -L "$CLAUDE_SWAP_LINK" ]]; then
        CURRENT_TARGET=""
        if [[ -L "$CLAUDE_SWAP_LINK" ]]; then
            CURRENT_TARGET="$(readlink "$CLAUDE_SWAP_LINK")"
        fi
        if [[ "$CURRENT_TARGET" != "$CLAUDE_SWAP_TARGET" ]]; then
            BACKUP_PATH="$HOME/.claude-swap.backup.$(date -u +%Y%m%dT%H%M%SZ)"
            echo "    Backing up existing ~/.claude-swap to $BACKUP_PATH"
            mv "$CLAUDE_SWAP_LINK" "$BACKUP_PATH"
        fi
    fi
    ln -sfn "$CLAUDE_SWAP_TARGET" "$CLAUDE_SWAP_LINK"
fi

# --- claude-swap CLI binary ---
CLAUDE_SWAP_BIN="$DOTFILES_DIR/_claude-swap/dist/src/cli.js"
if [[ -f "$CLAUDE_SWAP_BIN" ]]; then
    echo "==> Linking claude-swap binary..."
    mkdir -p "$HOME/.local/bin"
    ln -sf "$CLAUDE_SWAP_BIN" "$HOME/.local/bin/claude-swap"
    chmod +x "$CLAUDE_SWAP_BIN"
fi

if [[ -f "$DOTFILES_DIR/claude/settings.json" ]]; then
    if [[ -f "$HOME/.claude-swap/state.json" ]]; then
        echo "==> Skipping Claude Code settings link; ~/.claude is managed by claude-swap"
    else
        echo "==> Linking Claude Code settings bootstrap..."
        mkdir -p "$HOME/.claude"
        if [[ -f "$HOME/.claude/settings.json" && ! -L "$HOME/.claude/settings.json" ]]; then
            echo "    Backing up existing ~/.claude/settings.json to ~/.claude/settings.json.backup"
            mv "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup"
        fi
        ln -sf "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
    fi
fi

# --- OpenCode ---
if [[ -d "$DOTFILES_DIR/opencode" ]]; then
    echo "==> Linking opencode config..."
    if [[ -d "$HOME/.config/opencode" && ! -L "$HOME/.config/opencode" ]]; then
        echo "    Backing up existing ~/.config/opencode to ~/.config/opencode.backup"
        mv "$HOME/.config/opencode" "$HOME/.config/opencode.backup"
    fi
    ln -sfn "$DOTFILES_DIR/opencode" "$HOME/.config/opencode"
fi

echo "==> Done!"

echo ""
echo "Next steps:"
echo "  1. Add fish to /etc/shells:  sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'"
echo "  2. Change default shell:      chsh -s /opt/homebrew/bin/fish"
echo "  3. Restart your terminal or run: exec fish"
