#!/usr/bin/env bash
# Dotfiles setup script for macOS
# Run this after cloning the repo to ~/.dotfiles

set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles"

echo "==> Setting up dotfiles from $DOTFILES_DIR"

# --- Retired links ---
# Earlier versions of this script linked tmux and claude-swap. Remove only a
# symlink that still points at exactly the old repository path and whose target
# is gone; real files and links to anything else are left alone.
remove_retired_link() {
    local link="$1" target="$2"
    if [[ -L "$link" && "$(readlink "$link")" == "$target" && ! -e "$link" ]]; then
        echo "==> Removing retired link $link"
        rm "$link"
    fi
}
remove_retired_link "$HOME/.tmux.conf" "$DOTFILES_DIR/tmux/tmux.conf"
remove_retired_link "$HOME/.claude-swap" "$DOTFILES_DIR/claude-swap"
remove_retired_link "$HOME/.local/bin/claude-swap" "$DOTFILES_DIR/_claude-swap/dist/src/cli.js"

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

# --- herdr ---
if [[ -f "$DOTFILES_DIR/herdr/config.toml" ]]; then
    echo "==> Linking herdr config..."
    mkdir -p "$HOME/.config/herdr"
    ln -sf "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"
fi

# --- Claude Code ---
if [[ -f "$DOTFILES_DIR/claude/settings.json" ]]; then
    echo "==> Linking Claude Code settings..."
    mkdir -p "$HOME/.claude"
    if [[ -e "$HOME/.claude/settings.json" && ! -L "$HOME/.claude/settings.json" ]]; then
        BACKUP_PATH="$HOME/.claude/settings.json.backup.$(date -u +%Y%m%dT%H%M%SZ)"
        while [[ -e "$BACKUP_PATH" || -L "$BACKUP_PATH" ]]; do
            BACKUP_PATH="${BACKUP_PATH}.1"
        done
        mv "$HOME/.claude/settings.json" "$BACKUP_PATH"
    fi
    ln -sfn "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
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

# --- Agent Skills ---
SKILLS_SOURCE="$DOTFILES_DIR/skills"
if [[ -d "$SKILLS_SOURCE" ]]; then
    echo "==> Linking dotfiles skills directly into Claude and Agents..."
    python3 "$DOTFILES_DIR/skill-catalog.py" --apply
fi

echo "==> Done!"

echo ""
echo "Next steps:"
echo "  1. Add Bash to /etc/shells:  grep -qxF /opt/homebrew/bin/bash /etc/shells || sudo sh -c 'echo /opt/homebrew/bin/bash >> /etc/shells'"
echo "  2. Change default shell:     chsh -s /opt/homebrew/bin/bash"
echo "  3. Restart your terminal or run: exec /opt/homebrew/bin/bash -l"
