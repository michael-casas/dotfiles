# shellcheck shell=bash
# envi-guard.sh: path guards, dev slot names and the dev protocol check,
# sourced by envi, envi-dev and envi-migrate (each defines die first).
# Every helper fails through die or a non-zero return; none masks an error.

# real_chain <path> <root> [absent-ok]: <path> is a plain path inside <root>,
# <root> is inside $HOME, and every folder from $HOME down to <path> is a real
# folder, never a link. With absent-ok the path may be missing (and so may
# the folders above it, from the first missing one on).
real_chain() {
  local path="$1" root="$2" rest cur
  case "$root/" in "$HOME"/*) ;; *) die "$root is outside \$HOME; refusing" ;; esac
  case "$path/" in "$root"/*) ;; *) die "$path is outside $root; refusing" ;; esac
  case "$path/" in /*) ;; *) die "$path is not an absolute path; refusing" ;; esac
  case "$path/" in */../* | */./* | *//*) die "$path is not a plain path; refusing" ;; esac
  rest="${path#"$HOME"}"
  rest="${rest#/}"
  cur="$HOME"
  while [ -n "$rest" ]; do
    cur="$cur/${rest%%/*}"
    if [ "${rest#*/}" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    if [ -L "$cur" ]; then die "$cur is a link; refusing"; fi
    if [ ! -e "$cur" ]; then
      [ -n "${3:-}" ] && return 0
      die "$cur is missing; refusing"
    fi
    [ -d "$cur" ] || die "$cur is not a folder; refusing"
  done
}

# resolve_dir <path> <variable>: the real path of a folder, read without
# losing a trailing newline. A path with a control byte (0x01-0x1F, 0x7F),
# before or after resolution, is refused rather than round-tripped.
resolve_dir() {
  local _resolved
  case "$1" in *[[:cntrl:]]*) die "$(printf '%q' "$1") contains a control character; refusing" ;; esac
  _resolved="$(cd -- "$1" 2>/dev/null && pwd -P && printf x)" || die "no such folder: $1"
  _resolved="${_resolved%x}"
  _resolved="${_resolved%?}"
  case "$_resolved" in *[[:cntrl:]]*) die "$(printf '%q' "$_resolved") contains a control character; refusing" ;; esac
  printf -v "$2" '%s' "$_resolved"
}

# outside <path> <protected...>: <path> is not inside any protected tree.
outside() {
  local path="$1" p
  shift
  for p in "$@"; do
    case "$path/" in "$p"/*) die "$path is inside $p; refusing" ;; esac
  done
}

# A dev profile slot: [a-z0-9-] (the Treehouse slot, else the folder name)
# and the CRC of the exact real path, so two worktrees never share one.
valid_slot() { [[ "$1" =~ ^[a-z0-9-]{1,12}-[0-9a-f]{8}$ ]]; }
dev_slot() {
  local path="$1" label sum
  label="$(printf '%s' "$path" | sed -n 's|.*/\.treehouse/[^/]*/\([0-9][0-9]*\)/[^/]*$|slot\1|p')" ||
    die "cannot name the dev profile of $path"
  [ -n "$label" ] || label="${path##*/}"
  label="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-' | cut -c1-12)" ||
    die "cannot name the dev profile of $path"
  label="${label#-}"
  label="${label%-}"
  sum="$(printf '%s' "$path" | cksum | awk '{ printf "%08x", $1 }')" || die "cannot checksum $path"
  valid_slot "${label:-wt}-$sum" || die "cannot name the dev profile of $path"
  printf '%s\n' "${label:-wt}-$sum"
}

# dev_protocol_ok <file>: exactly one "envi-dev-protocol: N" comment line,
# and N is exactly 2.
dev_protocol_ok() {
  local found
  found="$(grep -E '^(#|--) envi-dev-protocol: ' "$1" 2>/dev/null)" || return 1
  case "$found" in *$'\n'*) return 1 ;; esac
  [ "${found#* envi-dev-protocol: }" = 2 ]
}
