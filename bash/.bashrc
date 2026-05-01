# Michael Casas
# Bash configuration for macOS
# Note: migrated from fish; prompt is identical via starship

# --- Kiro CLI pre block. Keep at the top of this file. ---
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/bashrc.pre.bash" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/bashrc.pre.bash"

# --- Homebrew ---
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# --- PATH Helper ---
path_prepend() {
    if [[ -d "$1" ]] && [[ ":$PATH:" != *":$1:"* ]]; then
        export PATH="$1:$PATH"
    fi
}

# --- PATH Management ---
# Bun
path_prepend "$HOME/.bun/bin"

# OpenCode
path_prepend "$HOME/.opencode/bin"

# LM Studio
path_prepend "$HOME/.lmstudio/bin"

# Local bin
path_prepend "$HOME/.local/bin"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
path_prepend "$ANDROID_HOME/emulator"
path_prepend "$ANDROID_HOME/platform-tools"
path_prepend "$ANDROID_HOME/tools"
path_prepend "$ANDROID_HOME/tools/bin"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$PYENV_ROOT/bin"
if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init -)"
fi

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]] && source "/opt/homebrew/opt/nvm/nvm.sh"
[[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ]] && source "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# --- Bash Completion ---
[[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"

# --- ble.sh (Bash Line Editor) ---
# Fish-like syntax highlighting, auto-suggestions, and menu completion for bash.
# Configuration lives in ~/.blerc (auto-read by ble.sh on init).
[[ -f ~/.local/share/blesh/ble.sh ]] && source ~/.local/share/blesh/ble.sh

# --- fzf ---
# Fuzzy finder key bindings and completions
if [[ -f /opt/homebrew/opt/fzf/shell/key-bindings.bash ]]; then
    source /opt/homebrew/opt/fzf/shell/key-bindings.bash
fi
if [[ -f /opt/homebrew/opt/fzf/shell/completion.bash ]]; then
    source /opt/homebrew/opt/fzf/shell/completion.bash
fi

# --- Aliases ---
alias ws='cd ~/Documents/repos/github.com'
alias kiroc='kiro-cli'
alias pip='python3 -m pip'
alias v='nvim'
alias claude-opus='~/.local/bin/claude-opus'
# fd: always show hidden files; exclusions live in ~/.config/fd/ignore
alias fd='fd --hidden'

# --- Support Agent (OpenCode serve) ---
support-serve() {
    if [[ -n "$TMUX" ]]; then
        tmux new-window -n "support" "opencode serve --port 4096 --hostname 127.0.0.1"
    else
        echo "Start tmux first, then run support-serve"
        return 1
    fi
}

ask() {
    local server_url="http://localhost:4096"

    # Check if server is running
    if ! curl -s "$server_url/global/health" > /dev/null 2>&1; then
        echo "Support server not running. Start it with: support-serve"
        return 1
    fi

    # Find existing Support session
    local sessions
    sessions=$(opencode session list --format json 2>/dev/null)
    local session_id
    session_id=$(echo "$sessions" | jq -r '[.[] | select(.title == "Support")] | sort_by(.updated) | last | .id // empty' 2>/dev/null)

    if [[ -n "$session_id" ]]; then
        opencode run --attach "$server_url" --agent Support --session "$session_id" "$@"
    else
        opencode run --attach "$server_url" --agent Support --title "Support" "$@"
    fi
}

# --- Django Systems Architect Agent (OpenCode serve on port 2313) ---
# Auto-start the long-lived server if not already running
if ! pgrep -f "opencode serve --port 2313" > /dev/null 2>&1; then
    nohup opencode serve --port 2313 --hostname 127.0.0.1 > /dev/null 2>&1 &
fi

# --- Editor ---
export EDITOR=nvim
export VISUAL=nvim

# --- Pager ---
export GLOW_PAGER="nvim -R -"

# --- Prompt ---
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

# --- Kiro CLI post block. Keep at the bottom of this file. ---
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/bashrc.post.bash" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/bashrc.post.bash"
