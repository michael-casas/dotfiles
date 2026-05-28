#!/usr/bin/env bash
# pkg-check.sh — Pre-validation for dotfiles dependencies
# Usage: ./pkg-check.sh
#
# Architecture:
#   1. Detect platform → select package manager mapping
#   2. Iterate declarative package registry → check each
#   3. Report categorized results → generate install commands

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
C_RED='\033[0;31m'
C_GRN='\033[0;32m'
C_YLW='\033[1;33m'
C_BLU='\033[0;34m'
C_CYN='\033[0;36m'
C_BLD='\033[1m'
C_RST='\033[0m'

_h()   { echo -e "\n${C_BLD}${C_BLU}▶ $1${C_RST}"; }
_ok()  { echo -e "  ${C_GRN}✓${C_RST} $1"; }
_ko()  { echo -e "  ${C_RED}✗${C_RST} $1"; }
_warn(){ echo -e "  ${C_YLW}⚠${C_RST} $1"; }
_info(){ echo -e "  ${C_CYN}ℹ${C_RST} $1"; }

# ── Platform Detection ──────────────────────────────────────────────────
detect_platform() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == linux-gnu* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

detect_pkg_manager() {
    if command -v brew &>/dev/null; then echo "brew"; return; fi
    if command -v apt-get &>/dev/null; then echo "apt"; return; fi
    if command -v pacman &>/dev/null; then echo "pacman"; return; fi
    if command -v dnf &>/dev/null; then echo "dnf"; return; fi
    if command -v apk &>/dev/null; then echo "apk"; return; fi
    echo "none"
}

# ── Package Manager Registry ────────────────────────────────────────────
# Maps manager name → install command template
declare -A PKG_INSTALL=(
    [brew]="brew install"
    [apt]="sudo apt-get install -y"
    [pacman]="sudo pacman -S --noconfirm"
    [dnf]="sudo dnf install -y"
    [apk]="sudo apk add"
)

# ── Package Registry ────────────────────────────────────────────────────
# Format per entry (pipe-delimited):
#   key|display_name|binary|category|required|check_type|pkg_brew|pkg_apt|pkg_pacman|pkg_dnf|special_cmd
#
# check_type:
#   bin        — command -v binary
#   ver:5      — command -v + major version >= N
#   dir:path   — directory or executable exists
#   skip       — handled by special_cmd only
#
# special_cmd:
#   non-empty  — manual install command shown instead of package manager
#   empty      — use package manager

declare -a PKGS=(
    # Core
    "git|Git|git|core|true|bin|git|git|git|git|"
    "bash|Bash (5.3+)|bash|core|true|ver:5|bash|bash|bash|bash|"
    "fish|Fish Shell|fish|core|true|bin|fish|fish|fish|fish|"
    "nvim|Neovim|nvim|core|true|bin|neovim|neovim|neovim|neovim|"
    "tmux|Tmux|tmux|core|true|bin|tmux|tmux|tmux|tmux|"
    "starship|Starship Prompt|starship|core|true|bin|starship|starship|starship|starship|"
    "fzf|fzf (fuzzy finder)|fzf|core|true|bin|fzf|fzf|fzf|fzf|"
    "fd|fd (fast file finder)|fd|core|true|bin|fd|fd-find|fd|fd|"

    # Shell enhancements
    "bash_completion|bash-completion|bash_completion|shell|false|file:/opt/homebrew/etc/profile.d/bash_completion.sh,/usr/share/bash-completion/bash_completion,/etc/bash_completion|bash-completion@2|bash-completion|bash-completion|bash-completion|"
    "ble_sh|ble.sh (Bash Line Editor)|ble.sh|shell|false|dir:~/.local/share/blesh/ble.sh|||||mkdir -p ~/.local/share && curl -L https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJf - -C ~/.local/share && mv ~/.local/share/ble-nightly ~/.local/share/blesh"

    # Language managers
    "pyenv|pyenv (Python version manager)|pyenv|lang|false|bin|pyenv|pyenv|pyenv|pyenv|"
    "nvm|nvm (Node version manager)|nvm|lang|false|dir:~/.nvm|nvm|nvm|nvm|nvm|curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
    "node|Node.js|node|lang|true|bin|node|nodejs|nodejs|nodejs|"
    "npm|npm|npm|lang|true|bin|npm|npm|npm|npm|"

    # Database / tools
    "pgcli|pgcli (PostgreSQL CLI)|pgcli|db|false|bin|pgcli|pgcli|pgcli|pgcli|"
    "taplo|taplo (TOML LSP)|taplo|db|false|bin|taplo|taplo|taplo|taplo|"

    # Utilities
    "curl|cURL|curl|util|true|bin|curl|curl|curl|curl|"
    "jq|jq (JSON processor)|jq|util|false|bin|jq|jq|jq|jq|"
    "tar|tar|tar|util|true|bin|tar|tar|tar|tar|"
    "xz|xz (compression)|xz|util|false|bin|xz|xz-utils|xz|xz|"

    # AI / CLI tools (optional)
    "opencode|OpenCode CLI|opencode|ai|false|dir:~/.opencode/bin/opencode|opencode|opencode|opencode|opencode|"
    "codex|Codex CLI|codex|ai|false|bin|codex|codex|codex|codex|"
    "claude|Claude Code|claude|ai|false|bin|claude-code|claude-code|claude-code|claude-code|"
    "kiro|Kiro CLI|kiro-cli|ai|false|bin|kiro-cli|kiro-cli|kiro-cli|kiro-cli|"
    "docker|Docker|docker|ai|false|bin|docker|docker.io|docker|docker|"

    # Optional
    "bun|Bun runtime|bun|opt|false|bin|bun|bun|bun|bun|"
    "pnpm|pnpm|pnpm|opt|false|bin|pnpm|pnpm|pnpm|pnpm|"
    "ghostty|Ghostty terminal|ghostty|opt|false|bin|ghostty||||"
)

# ── Check Engine ────────────────────────────────────────────────────────

check_pkg() {
    local key="$1" binary="$2" check_type="$3"

    case "$check_type" in
        bin)
            command -v "$binary" &>/dev/null
            ;;
        ver:*)
            local min_ver="${check_type#ver:}"
            if ! command -v "$binary" &>/dev/null; then return 1; fi
            local ver
            ver=$("$binary" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
            [[ -n "$ver" ]] && (( "${ver%%.*}" >= min_ver ))
            ;;
        dir:*)
            local path="${check_type#dir:}"
            path="${path/#\~/$HOME}"
            [[ -e "$path" ]]
            ;;
        file:*)
            local paths="${check_type#file:}"
            local found=1
            IFS=',' read -ra path_arr <<< "$paths"
            for p in "${path_arr[@]}"; do
                p="${p/#\~/$HOME}"
                p="${p# }"; p="${p% }"  # trim spaces
                if [[ -f "$p" ]]; then
                    found=0
                    break
                fi
            done
            return $found
            ;;
        skip)
            return 1  # Always reported as missing; handled by special_cmd
            ;;
        *)
            return 1
            ;;
    esac
}

# ── Package Name Resolver ───────────────────────────────────────────────

resolve_pkg_name() {
    local entry="$1" manager="$2"
    local IFS='|'; read -r -a fields <<< "$entry"

    local idx
    case "$manager" in
        brew)    idx=6 ;;
        apt)     idx=7 ;;
        pacman)  idx=8 ;;
        dnf)     idx=9 ;;
        *)       echo ""; return ;;
    esac

    local pkg_name="${fields[$idx]:-}"

    # macOS-only packages fallback to empty on Linux
    if [[ "$manager" != "brew" && -z "$pkg_name" ]]; then
        echo ""
        return
    fi

    # Handle fd-find / fd binary name discrepancy on Debian
    if [[ "$manager" == "apt" && "${fields[0]}" == "fd" ]]; then
        pkg_name="fd-find"
    fi

    echo "$pkg_name"
}

# ── State Collections ───────────────────────────────────────────────────
declare -a MISSING=()
declare -a MISSING_SPECIAL=()

# ── Main Loop ───────────────────────────────────────────────────────────

PLATFORM=$(detect_platform)
PKG_MGR=$(detect_pkg_manager)

_h "🔍 Dotfiles Dependency Check"
echo ""
_info "Platform: ${C_BLD}${PLATFORM}${C_RST}"
_info "Package Manager: ${C_BLD}${PKG_MGR}${C_RST}"

if [[ "$PKG_MGR" == "none" ]]; then
    echo ""
    _warn "No supported package manager found."
    echo "  macOS: Install Homebrew → https://brew.sh"
    echo "  Linux: Ensure apt, pacman, dnf, or apk is available."
    exit 1
fi
echo ""

for entry in "${PKGS[@]}"; do
    IFS='|' read -r key display binary category required check_type _ <<< "$entry"

    if check_pkg "$key" "$binary" "$check_type"; then
        _ok "$display"
    else
        _ko "$display"
        MISSING+=("$entry")
    fi
done

# ── Special: TPM ────────────────────────────────────────────────────────
if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    _ok "TPM (Tmux Plugin Manager)"
else
    _ko "TPM (Tmux Plugin Manager)"
    MISSING_SPECIAL+=("TPM|git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm")
fi

# ── Summary ─────────────────────────────────────────────────────────────

if [[ ${#MISSING[@]} -eq 0 && ${#MISSING_SPECIAL[@]} -eq 0 ]]; then
    echo ""
    _h "✅ All dependencies satisfied"
    echo ""
    _info "Run ${C_BLD}./setup.sh${C_RST} to link your dotfiles."
    exit 0
fi

_h "📦 Missing Dependencies"
echo ""

# Generic category reporter
report_category() {
    local cat_key="$1" cat_label="$2"
    local -a items=()
    for entry in "${MISSING[@]}"; do
        IFS='|' read -r _ _ _ c _ _ <<< "$entry"
        [[ "$c" == "$cat_key" ]] && items+=("$entry")
    done

    [[ ${#items[@]} -eq 0 ]] && return

    echo -e "  ${C_BLD}${cat_label}:${C_RST}"
    for entry in "${items[@]}"; do
        IFS='|' read -r _ display _ _ _ _ <<< "$entry"
        local pkg_name
        pkg_name=$(resolve_pkg_name "$entry" "$PKG_MGR")
        if [[ -n "$pkg_name" ]]; then
            echo -e "    • ${display} → ${C_CYN}${pkg_name}${C_RST}"
        else
            echo -e "    • ${display} → ${C_YLW}(manual install)${C_RST}"
        fi
    done
    echo ""
}

report_category "core"   "🔴 Core (Required)"
report_category "shell"  "🐚 Shell Enhancements"
report_category "lang"   "🌐 Language Managers"
report_category "db"     "🐘 Database Tools"
report_category "util"   "🔧 Utilities"
report_category "ai"     "🤖 AI / CLI Tools"
report_category "opt"    "⚪ Optional"

if [[ ${#MISSING_SPECIAL[@]} -gt 0 ]]; then
    echo -e "  ${C_BLD}Special Installations:${C_RST}"
    for spec in "${MISSING_SPECIAL[@]}"; do
        IFS='|' read -r label cmd <<< "$spec"
        echo -e "    • ${label}"
    done
    echo ""
fi

# ── Install Command Generation ──────────────────────────────────────────

read -rp "Show install commands? [Y/n] " answer
[[ "$answer" =~ ^[Nn]$ ]] && exit 0

echo ""
_h "🚀 Install Commands"
echo ""

# Collect package-manager-installable packages
PM_PACKAGES=()
for entry in "${MISSING[@]}"; do
    IFS='|' read -r _ _ _ category required _ special_cmd <<< "$entry"
    # Skip if no package name for this manager or has special_cmd
    local pkg_name
    pkg_name=$(resolve_pkg_name "$entry" "$PKG_MGR")
    [[ -z "$pkg_name" ]] && continue
    [[ -n "$special_cmd" ]] && continue
    PM_PACKAGES+=("$pkg_name")
done

if [[ ${#PM_PACKAGES[@]} -gt 0 ]]; then
    echo -e "  ${C_BLD}Package Manager:${C_RST}"
    echo ""
    echo -e "    ${C_CYN}${PKG_INSTALL[$PKG_MGR]} ${PM_PACKAGES[*]}${C_RST}"
    echo ""
fi

# Special commands
if [[ ${#MISSING_SPECIAL[@]} -gt 0 ]]; then
    echo -e "  ${C_BLD}Manual / Special:${C_RST}"
    echo ""
    for spec in "${MISSING_SPECIAL[@]}"; do
        IFS='|' read -r label cmd <<< "$spec"
        echo -e "    # ${label}"
        echo -e "    ${C_CYN}${cmd}${C_RST}"
        echo ""
    done
fi

# Special-cmd packages from registry
for entry in "${MISSING[@]}"; do
    IFS='|' read -r _ display _ _ _ special_cmd <<< "$entry"
    [[ -z "$special_cmd" ]] && continue
    echo -e "  ${C_BLD}${display}:${C_RST}"
    echo -e "    ${C_CYN}${special_cmd}${C_RST}"
    echo ""
done

# ── Optional auto-run ───────────────────────────────────────────────────

if [[ ${#PM_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    read -rp "Run package manager install now? [y/N] " run_now
    if [[ "$run_now" =~ ^[Yy]$ ]]; then
        echo ""
        _info "Running: ${C_BLD}${PKG_INSTALL[$PKG_MGR]} ${PM_PACKAGES[*]}${C_RST}"
        echo ""
        eval "${PKG_INSTALL[$PKG_MGR]} ${PM_PACKAGES[*]}"
        echo ""
        _h "✅ Package manager install complete"
        _warn "Run manual/special commands above if any, then re-run ./pkg-check.sh"
    fi
fi

echo ""
