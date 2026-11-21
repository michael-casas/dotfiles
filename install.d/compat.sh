# shellcheck shell=bash
# Compatibility checks, sourced by ./install. Read-only.
# FAIL: the installer cannot work here. warn: a tool is missing or too old;
# the packages phase (step 3) will install it. MANUAL: a person must act.

# Version probes. Some tools write on any start (nvim's log, gh's device id,
# starship's cache) and honour inherited settings such as NVIM_LOG_FILE or
# TMPDIR. So a probe runs under `env -i` with only PATH and the locale passed
# through, and HOME, TMPDIR and every XDG dir set to a private directory under
# a system scratch root (DOTFILES_PROBE_ROOT, default /tmp). That root must lie
# outside every home, XDG root and checkout. No scratch directory: no probe.
PROBE=""          # this run's scratch directory; ./install removes it on exit
PROBE_ERR=""

probe_open() {
    local root="${DOTFILES_PROBE_ROOT:-/tmp}" canon p
    if ! canon="$(cd -- "$root" 2>/dev/null && pwd -P)"; then
        PROBE_ERR="scratch root $root does not exist"
        return 1
    fi
    for p in "$HOME" "$ACCOUNT_HOME" "$XDG_CONFIG_HOME" "${XDG_CACHE_HOME:-}" "${XDG_DATA_HOME:-}" \
        "${XDG_STATE_HOME:-}" "${XDG_RUNTIME_DIR:-}" "$CHECKOUT" "$BASE"; do
        if [ -z "$p" ]; then continue; fi
        p="$( (cd -- "$p" 2>/dev/null && pwd -P) || printf '%s' "$p")"
        case "$canon/" in
            "${p%/}"/*) PROBE_ERR="scratch root $canon is inside $p"; return 1 ;;
        esac
    done
    if ! PROBE="$(mktemp -d "$canon/dotfiles-probe.XXXXXX" 2>/dev/null)"; then
        PROBE=""
        PROBE_ERR="cannot create a directory under $canon"
        return 1
    fi
}

probe_close() {
    if [ -n "$PROBE" ]; then rm -rf -- "$PROBE"; fi
}

version_of() {    # version_of <executable>: first dotted number of its --version
    local dir
    if [ -z "$PROBE" ] || ! dir="$(mktemp -d "$PROBE/probe.XXXXXX" 2>/dev/null)"; then
        return 2
    fi
    # GIT_OFF too: env -i drops the switched-off Trace2 targets, and git config
    # could set them again.
    { env -i PATH="$PATH" LC_ALL=C HOME="$dir" TMPDIR="$dir" XDG_CONFIG_HOME="$dir" \
        XDG_CACHE_HOME="$dir" XDG_DATA_HOME="$dir" XDG_STATE_HOME="$dir" XDG_RUNTIME_DIR="$dir" \
        "${GIT_OFF[@]}" "$1" --version 2>&1 </dev/null || true; } | head -n 1 |
        sed -n 's/[^0-9]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{1,\}\).*/\1/p'
    rm -rf -- "$dir"
}

version_ge() {    # version_ge 3.2.57 3.2: true when $1 >= $2
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
        for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
        exit 0 }'
}

need() {          # need <status-if-bad> <command> <minimum or ""> <why>; sets NEED_OK
    local bad="$1" cmd="$2" min="$3" why="$4" exe="" v shown=""
    NEED_OK=0
    if ! resolve_tool "$cmd" exe; then
        report "$bad" tools "$TOOL_ERR ($why)"
        return
    fi
    case "$cmd" in git|python3) shown=" ($exe)" ;; esac   # the ones the installer runs
    if [ -z "$min" ]; then               # presence is all that matters; do not start it
        report ok tools "$cmd present"
        NEED_OK=1
        return
    fi
    if ! v="$(version_of "$exe")"; then
        report "$bad" tools "$cmd version probe failed: ${PROBE_ERR:-no private scratch directory}"
        return
    fi
    if [ -z "$v" ] || ! version_ge "$v" "$min"; then
        report "$bad" tools "$cmd ${v:-unknown version} is older than $min ($why)$shown"
    else
        report ok tools "$cmd $v$shown"
        NEED_OK=1
    fi
}

compat_check() {
    local arch brew prefix
    probe_open || true      # on failure every version probe reports PROBE_ERR
    arch="$(uname -m)"
    # shellcheck disable=SC1091
    case "$OS" in
        Darwin) report ok system "macOS $(sw_vers -productVersion 2>/dev/null) $arch" ;;
        Linux) report ok system "Linux $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-}") $arch" ;;
        *) report FAIL system "$OS is not supported (macOS and Linux only)" ;;
    esac
    case "$arch" in x86_64|arm64|aarch64) ;; *) report warn system "untested architecture $arch" ;; esac

    if version_ge "${BASH_VERSION%%[^0-9.]*}" 3.2; then
        report ok bash "running ${BASH_VERSION%%(*} ($BASH)"
    else
        report FAIL bash "running ${BASH_VERSION}; 3.2 or newer is required"
    fi
    need FAIL python3 3.7 "dotbot needs Python 3.7+"
    # shellcheck disable=SC2034  # read by links_check, which then runs no Python
    if [ "$NEED_OK" -ne 1 ]; then PYTHON_BIN=""; fi
    need FAIL git 2.13 "the checkout and its guards need it"

    if [ "$OS" = Darwin ]; then
        brew="$(command -v brew 2>/dev/null || true)"
        for prefix in /opt/homebrew /usr/local; do
            if [ -z "$brew" ] && [ -x "$prefix/bin/brew" ]; then brew="$prefix/bin/brew"; fi
        done
        if [ -z "$brew" ]; then
            report MANUAL packages "Homebrew not found; install it from https://brew.sh (the packages phase will, from step 3)"
        else
            prefix="$(dirname -- "$(dirname -- "$brew")")"
            # Not `brew --version`: it writes ~/Library/Caches/Homebrew.
            report ok packages "Homebrew at $prefix"
            PATH="$PATH:$prefix/bin"   # so the tool checks below see Homebrew's tools
            if [ "$arch" = arm64 ] && [ "$prefix" != /opt/homebrew ]; then
                report warn packages "Homebrew at $prefix on Apple silicon; /opt/homebrew is the native prefix"
            fi
        fi
    elif [ "$OS" = Linux ]; then
        if command -v apt-get >/dev/null 2>&1; then
            report ok packages "apt-get present (the packages phase covers macOS only)"
        else
            report warn packages "no apt-get; install the tools below with your package manager"
        fi
    fi

    need warn nvim 0.11 "envi uses Neovim 0.11 APIs"
    need warn node 22 "nvim/tools declare node >=22"
    local tool
    for tool in starship fzf fd rg jq gh shellcheck; do
        need warn "$tool" "" "used by the shell and editor configs"
    done
}
