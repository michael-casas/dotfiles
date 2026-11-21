# shellcheck shell=bash
# Tool selection and the one read-only Git path. Sourced by ./install before
# any guard runs.
#
# macOS /usr/bin/git and /usr/bin/python3 are xcrun shims. Any start of one may
# write xcrun's cache in the per-user temp dir, keyed on HOME. So such a shim is
# resolved to the real executable in the developer dir that `xcode-select -p`
# names, and the shim itself is never started: no xcrun lookup, no fallback.
# Any other PATH choice (Homebrew git, a pyenv python) is used as found.

# Trace2 reads its targets from the environment first, so these switch off the
# normal, perf and event targets even when git config sets them.
GIT_OFF=(GIT_TRACE2=0 GIT_TRACE2_PERF=0 GIT_TRACE2_EVENT=0)

# shellcheck disable=SC2034  # TOOL_ERR is read by the callers
resolve_tool() {   # resolve_tool <name> <variable>: on failure, TOOL_ERR says why
    local name="$1" path dev bin
    TOOL_ERR=""
    path="$(command -v "$name" 2>/dev/null || true)"
    if [ -z "$path" ]; then
        TOOL_ERR="$name missing"
        return 1
    fi
    case "$OS:$path" in
        Darwin:/usr/bin/git|Darwin:/usr/bin/python3)
            dev="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
            bin="$( (cd -- "$dev/usr/bin" 2>/dev/null && pwd -P) || true)"
            if [ -z "$dev" ] || [ -z "$bin" ] || [ ! -f "$bin/$name" ] || [ ! -x "$bin/$name" ] ||
                [ "$bin/$name" -ef "$path" ]; then
                TOOL_ERR="$name: $path is an xcrun shim, and the developer dir from xcode-select -p (${dev:-none}) has no usr/bin/$name; run xcode-select --install, or sudo xcode-select -s <developer dir>"
                return 1
            fi
            path="$bin/$name" ;;
    esac
    printf -v "$2" '%s' "$path"
}

git_quiet() {      # drop inherited legacy tracing; switch every Trace2 target off
    local var
    for var in $(env | sed -n 's/^\(GIT_TRACE[A-Za-z0-9_]*\)=.*/\1/p'); do
        unset "$var"
    done
    export "${GIT_OFF[@]}"
}

git_ro() {         # every git call the installer makes
    "$GIT_BIN" "$@"
}

tools_select() {   # set GIT_BIN and PYTHON_BIN; never start an unresolved shim
    if ! resolve_tool git GIT_BIN; then
        echo "install: $TOOL_ERR" >&2
        exit 1
    fi
    git_quiet
    # shellcheck disable=SC2034  # read by compat_check and links_check
    PYTHON_BIN=""
    resolve_tool python3 PYTHON_BIN || true    # compat_check reports why it is empty
}
