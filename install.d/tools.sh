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
    # type -P: an executable file on PATH, never a shell function or alias.
    path="$(type -P "$name" 2>/dev/null || true)"
    if [ -z "$path" ]; then
        TOOL_ERR="$name missing"
        return 1
    fi
    # A relative PATH entry is made absolute now, before any cd (logical pwd,
    # so a virtualenv's bin/python3 link keeps its own name and directory).
    case "$path" in
        /*) ;;
        *) path="$(cd -- "$(dirname -- "$path")" && pwd)/${path##*/}" ;;
    esac
    # The stock shim by file identity, so /usr/bin//git or a link to the shim
    # is recognised too.
    if [ "$OS" = Darwin ] && { [ "$name" = git ] || [ "$name" = python3 ]; } &&
        [ "$path" -ef "/usr/bin/$name" ]; then
        dev="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
        bin="$( (cd -- "$dev/usr/bin" 2>/dev/null && pwd -P) || true)"
        if [ -z "$dev" ] || [ -z "$bin" ] || [ ! -f "$bin/$name" ] || [ ! -x "$bin/$name" ] ||
            [ "$bin/$name" -ef "/usr/bin/$name" ]; then
            TOOL_ERR="$name: $path is an xcrun shim, and the developer dir from xcode-select -p (${dev:-none}) has no usr/bin/$name; run xcode-select --install, or sudo xcode-select -s <developer dir>"
            return 1
        fi
        path="$bin/$name"
    fi
    printf -v "$2" '%s' "$path"
}

git_quiet() {      # drop inherited legacy tracing; switch every Trace2 target off
    local var
    for var in $(env | sed -n 's/^\(GIT_TRACE[A-Za-z0-9_]*\)=.*/\1/p'); do
        unset "$var"
    done
    export "${GIT_OFF[@]}"
    export GIT_OPTIONAL_LOCKS=0   # no opportunistic index refresh either
}

# Every git call the installer makes. core.fsmonitor=false on the command line
# beats any config scope, in both its boolean and its hook-path form, so no
# call starts the fsmonitor daemon or writes its state under .git (F16).
git_ro() {
    "$GIT_BIN" -c core.fsmonitor=false "$@"
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
