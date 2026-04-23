# Michael Casas
# Fish shell configuration for macOS

# --- Homebrew ---
if test -x /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
end

# --- PATH Management ---
# Bun
fish_add_path /Users/mcasa_atlantis/.bun/bin

# OpenCode
fish_add_path /Users/mcasa_atlantis/.opencode/bin

# LM Studio
fish_add_path /Users/mcasa_atlantis/.lmstudio/bin

# Local bin
fish_add_path $HOME/.local/bin

# Android SDK
set -gx ANDROID_HOME $HOME/Library/Android/sdk
set -gx ANDROID_SDK_ROOT $HOME/Library/Android/sdk
fish_add_path $ANDROID_HOME/emulator
fish_add_path $ANDROID_HOME/platform-tools
fish_add_path $ANDROID_HOME/tools
fish_add_path $ANDROID_HOME/tools/bin

# pyenv
set -gx PYENV_ROOT "$HOME/.pyenv"
fish_add_path $PYENV_ROOT/bin
if command -v pyenv >/dev/null
    pyenv init - | source
end

# nvm (requires bass plugin for fish, or use nvm.fish instead)
set -gx NVM_DIR "$HOME/.nvm"
if test -s "/opt/homebrew/opt/nvm/nvm.sh"
    if type -q bass
        bass source "/opt/homebrew/opt/nvm/nvm.sh"
    else
        # Fallback: manually add the default node version to PATH if it exists
        if test -d "$NVM_DIR/versions/node"
            set -l default_node (ls -1 $NVM_DIR/versions/node | sort -V | tail -1)
            if test -n "$default_node"
                fish_add_path $NVM_DIR/versions/node/$default_node/bin
            end
        end
    end
end

# --- Aliases ---
alias ws="cd ~/Documents/repos/github.com"
alias kiroc="kiro-cli"
alias pip="python3 -m pip"

# --- Editor ---
set -gx EDITOR "nvim"
set -gx VISUAL "nvim"

# --- Pager ---
set -gx GLOW_PAGER "nvim -R -"

# --- Prompt ---
if command -v starship >/dev/null
    starship init fish | source
end

# --- Greeting ---
set fish_greeting

# --- Key Bindings ---
# Accept autosuggestion (gray text) with Tab instead of Right Arrow
# Note: This overrides the default Tab completion pager.
# Use Ctrl+F to trigger completions when needed.
bind \t accept-autosuggestion
