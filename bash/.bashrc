# Michael Casas
# Bash configuration for macOS

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

# Obsidian CLI app bundle binary
path_prepend "/Applications/Obsidian.app/Contents/MacOS"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
path_prepend "$ANDROID_HOME/emulator"
path_prepend "$ANDROID_HOME/platform-tools"
path_prepend "$ANDROID_HOME/tools"
path_prepend "$ANDROID_HOME/tools/bin"

# PostgreSQL 18 (keg-only, not symlinked by brew)
path_prepend "/opt/homebrew/opt/postgresql@18/bin"
export LDFLAGS="-L/opt/homebrew/opt/postgresql@18/lib"
export CPPFLAGS="-I/opt/homebrew/opt/postgresql@18/include"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$PYENV_ROOT/bin"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init --no-rehash -)"
fi

# nvm
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  source "$NVM_DIR/nvm.sh"
  nvm use --silent default >/dev/null
  # Homebrew may precede an inherited NVM path; NVM must win command lookup.
  export PATH="$NVM_BIN:$PATH"
fi
[[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ]] && source "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
path_prepend "$PNPM_HOME/bin"

# Antigravity IDE
path_prepend "$HOME/.antigravity-ide/antigravity-ide/bin"

# Grok CLI
path_prepend "$HOME/.grok/bin"

# Java / Maestro
# Homebrew's versioned JDK is keg-only, so point tools at its stable path.
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
path_prepend "$JAVA_HOME/bin"

# --- Bash Completion ---
[[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"

# --- ble.sh (Bash Line Editor) ---
# Syntax highlighting, auto-suggestions, and menu completion for Bash.
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

# OpenClaw completion
[[ -f "$HOME/.openclaw/completions/openclaw.bash" ]] && source "$HOME/.openclaw/completions/openclaw.bash"

# --- Global Env (loaded into every bash shell) ---
if [[ -f "$HOME/.dotfiles/.env" ]]; then
  set -a
  source "$HOME/.dotfiles/.env"
  set +a
fi
unset CLAUDE_CODE_OAUTH_TOKEN

# --- Codex thread to Herdr pane context ---
# ChatGPT's App Server can execute a thread that is also attached to a Herdr
# pane. Resolve only that exact saved thread mapping; never use the focused pane
# or set a global Herdr identity.
if [[ -n "${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}" ]] &&
  [[ -r "${CODEX_HOME:-$HOME/.codex}/scripts/codex-herdr-thread-env.sh" ]]; then
  source "${CODEX_HOME:-$HOME/.codex}/scripts/codex-herdr-thread-env.sh"
fi

# --- Machine-local overrides (untracked) ---
# Host- and work-specific values stay out of this public repo, in
# ~/.config/bash/local.bash. For example:
#   export ESTIMATING_DIRECTORY_HOME="$HOME/Desktop/<work OneDrive>/ESTIMATING"
#   export ANTHROPIC_BASE_URL="http://<proxy host>:<port>"
if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/bash/local.bash" ]]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/bash/local.bash"
fi

# --- direnv (per-directory overrides) ---
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi

# --- Aliases ---
alias ws='cd ~/Documents/repos/github.com'
alias kiroc='kiro-cli'
alias pip='python3 -m pip'
alias v='nvim'
alias claude-opus='~/.local/bin/claude-opus'
alias cld='claude --dangerously-skip-permissions'
alias cldc='claude --dangerously-skip-permissions --chrome'
alias clde='env -u ANTHROPIC_BASE_URL -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_MODEL -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY CLAUDE_CONFIG_DIR=$HOME/.config/experimental/claude/config CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 $HOME/.config/experimental/claude/node_modules/.bin/claude --dangerously-skip-permissions'
alias cdxh='codex --yolo -c shell_environment_policy.inherit="all"'
# fd: always show hidden files; exclusions live in ~/.config/fd/ignore
alias fd='fd --hidden'

# Copy the local CLIProxyAPI management key without displaying it.
get-cli-api-key() {
  python3 - <<'PY'
import json
from pathlib import Path
import subprocess
import sys

try:
    key = json.loads((Path.home() / ".local/share/cliproxyapi-v8-runtime/keys.json").read_text())["management"]
    if not isinstance(key, str) or not key.strip():
        raise ValueError("Missing management key")
    subprocess.run(["pbcopy"], input=key, text=True, check=True)
except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
    sys.exit("Could not copy CLIProxyAPI management key; check keys.json and pbcopy.")
print("CLIProxyAPI management key copied to clipboard.")
PY
}

# --- Kali Docker workspace ---
# Usage: kali | kali up | kali down
kali() {
  local compose_file="$HOME/.dotfiles/Kali/docker-compose.yaml"

  case "${1:-}" in
  up)
    shift
    docker compose --file "$compose_file" up --detach --build "$@"
    ;;
  down)
    shift
    docker compose --file "$compose_file" down "$@"
    ;;
  "")
    command ssh kali
    ;;
  *)
    command ssh kali "$@"
    ;;
  esac
}

# --- Support Agent (OpenCode serve) ---
# Run in a dedicated Herdr pane; the server stays in the foreground.
support-serve() {
  command opencode serve --port 4096 --hostname 127.0.0.1
}

ask() {
  if (($# == 0)); then
    echo 'Usage: ask "your question"' >&2
    return 2
  fi

  local output_file exit_code
  output_file=$(mktemp "${TMPDIR:-/tmp}/codex-ask.XXXXXX") || return 1

  command codex exec \
    -m gpt-5.6-luna \
    --ignore-user-config \
    --disable hooks \
    --skip-git-repo-check \
    --yolo \
    -c 'model_reasoning_effort="low"' \
    -c 'service_tier="fast"' \
    --output-last-message "$output_file" \
    -- "$*" >/dev/null 2>&1
  exit_code=$?

  [[ -s "$output_file" ]] && command cat -- "$output_file"
  command rm -f -- "$output_file"
  return "$exit_code"
}

# --- Django Systems Architect Agent (OpenCode serve on port 2313) ---
# Auto-start the long-lived server if not already running
if ! pgrep -f "opencode serve --port 2313" >/dev/null 2>&1; then
  nohup opencode serve --port 2313 --hostname 127.0.0.1 >/dev/null 2>&1 &
fi

# --- Editor ---
export EDITOR=nvim
export VISUAL=nvim

# --- Pager ---
export GLOW_PAGER="nvim -R -"

# --- Prompt ---
# Starship with its Nordic palette (~/.config/starship.toml). The native PS1 is
# the fallback when starship is not installed.
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
else
  PS1='\[\e[38;2;163;190;140m\]\u@\h\[\e[0m\] \[\e[38;2;136;192;208m\]\w\[\e[0m\] \$ '
fi

# --- Kiro CLI post block. Keep at the bottom of this file. ---
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/bashrc.post.bash" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/bashrc.post.bash"
