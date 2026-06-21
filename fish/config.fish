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

# PostgreSQL 18 (keg-only, not symlinked by brew)
fish_add_path /opt/homebrew/opt/postgresql@18/bin
set -gx LDFLAGS "-L/opt/homebrew/opt/postgresql@18/lib"
set -gx CPPFLAGS "-I/opt/homebrew/opt/postgresql@18/include"

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
alias v="nvim"
alias claude-opus="~/.local/bin/claude-opus"
# fd: always show hidden files; exclusions live in ~/.config/fd/ignore
alias fd="fd --hidden"

# --- Support Agent (OpenCode serve) ---
function support-serve
    if test -n "$TMUX"
        tmux new-window -n "support" "opencode serve --port 4096 --hostname 127.0.0.1"
    else
        echo "Start tmux first, then run support-serve"
        return 1
    end
end

function ask
    set -l server_url "http://localhost:4096"

    # Check if server is running
    if not curl -s $server_url/global/health > /dev/null 2>&1
        echo "Support server not running. Start it with: support-serve"
        return 1
    end

    # Find existing Support session
    set -l sessions (opencode session list --format json 2>/dev/null)
    set -l session_id (echo $sessions | jq -r '[.[] | select(.title == "Support")] | sort_by(.updated) | last | .id // empty' 2>/dev/null)

    if test -n "$session_id"
        opencode run --attach $server_url --agent Support --session $session_id "$argv"
    else
        opencode run --attach $server_url --agent Support --title "Support" "$argv"
    end
end

# --- Django Systems Architect Agent (OpenCode serve on port 2313) ---
# Auto-start the long-lived server if not already running
if not pgrep -f "opencode serve --port 2313" > /dev/null 2>&1
    nohup opencode serve --port 2313 --hostname 127.0.0.1 &> /dev/null &
end

# --- Editor ---
set -gx EDITOR nvim
set -gx VISUAL nvim

# --- Pager ---
set -gx GLOW_PAGER "nvim -R -"

# --- Global Env (loaded into every fish shell) ---
function __load_env --argument file
    if not test -f "$file"
        return
    end
    while read -l line
        if test -z "$line"; or string match -q "#*" $line
            continue
        end
        set line (string replace -r '^export\s+' '' $line)
        set -l parts (string split -m 1 '=' $line)
        set -l key (string trim $parts[1])
        set -l val (string trim $parts[2])
        if string match -q '"*"' $val
            set val (string sub -s 2 -e -1 $val)
        else if string match -q "'*'" $val
            set val (string sub -s 2 -e -1 $val)
        end
        set -gx $key $val
    end <$file
end

__load_env $HOME/.dotfiles/.env

# --- direnv (per-directory overrides) ---
if command -v direnv >/dev/null
    direnv hook fish | source
end

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

# pnpm
set -gx PNPM_HOME "/Users/mcasa_atlantis/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

# Added by Antigravity IDE
fish_add_path /Users/mcasa_atlantis/.antigravity-ide/antigravity-ide/bin


# Added by Antigravity CLI installer
set -gx PATH "/Users/mcasa_atlantis/.local/bin" $PATH
