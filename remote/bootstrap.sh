#!/bin/bash
# Protocol 1, reviewed local code sent as a quoted SSH command; stdin is archive only.
# Bash 3.2; GNU/BSD stat, tar, SHA-256. Never execute an unverified payload.
set -eu
umask 077
fail() { printf 'envi-remote bootstrap: %s\n' "$1" >&2; exit 23; }
hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
    else fail 'SHA-256 unavailable'; fi
}
metadata() {
    local owner mode
    if stat -c '%u %a' "$1" 2>/dev/null; then return; fi
    read -r owner mode <<< "$(stat -f '%u %p' "$1")"
    printf '%s %o\n' "$owner" "$((8#$mode & 07777))"
}
private_path() {
    local path=$1 current='' part owner perms uid
    uid=$(id -u)
    case "$path" in /*) ;; *) fail 'absolute root required' ;; esac
    case "$path" in *'/../'*|*'/./'*|*'//'*) fail 'noncanonical root' ;; esac
    local oldifs=$IFS
    IFS=/
    read -r -a parts <<< "$path"
    IFS=$oldifs
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="$current/$part"
        [ ! -L "$current" ] || fail 'symlink in root'
        if [ -e "$current" ]; then
            [ -d "$current" ] || fail 'root component is not a directory'
            read -r owner perms <<< "$(metadata "$current")"
            [ "$owner" = "$uid" ] || [ "$owner" = 0 ] || fail 'foreign-owned root'
            # Only root-owned sticky system temp ancestors are exceptions.
            if (( (8#$perms & 0022) != 0 )); then
                if [ "$owner" != 0 ] || (( (8#$perms & 01000) == 0 )); then
                    fail 'writable root ancestor'
                fi
            fi
        else
            mkdir "$current" || fail 'cannot create private root'
            chmod 0700 "$current" || fail 'cannot create private root'
        fi
    done
    read -r owner perms <<< "$(metadata "$path")"
    if [ "$owner" != "$uid" ] || (( (8#$perms & 0777) != 0700 || (8#$perms & 05000) != 0 )); then
        fail 'root must be owned mode 0700'
    fi
}
check_release() {
    local release=$1 mode size expected path directory owner perms count=0
    [ -d "$release" ] && [ ! -L "$release" ] || return 1
    # Cached trees are revalidated, including parent directories and hardlinks.
    while IFS= read -r directory; do
        read -r owner perms <<< "$(metadata "$directory")"
        [ "$owner" = "$(id -u)" ] || return 1
        (( (8#$perms & 0022) == 0 )) || return 1
    done < <(find "$release" -type d -print)
    [ -z "$(find "$release" -type f -links +1 -print)" ] || return 1
    [ -f "$release/MANIFEST" ] && [ ! -L "$release/MANIFEST" ] || return 1
    read -r owner perms <<< "$(metadata "$release/MANIFEST")"
    [ "$owner" = "$(id -u)" ] && [ "$perms" = 644 ] || return 1
    [ "$(hash "$release/MANIFEST")" = "$digest" ] || return 1
    [ "$(cat "$release/MANIFEST")" = "$manifest" ] || return 1
    while read -r mode size expected path; do
        case "$mode" in schema|protocol) continue ;; esac
        [ -f "$release/$path" ] && [ ! -L "$release/$path" ] || return 1
        [ "$(hash "$release/$path")" = "$expected" ] || return 1
        [ "$(wc -c < "$release/$path" | tr -d ' ')" = "$size" ] || return 1
        read -r owner perms <<< "$(metadata "$release/$path")"
        [ "$owner" = "$(id -u)" ] && [ "0$perms" = "$mode" ] || return 1
        count=$((count + 1))
    done <<< "$manifest"
    [ "$(find "$release" -type f | wc -l | tr -d ' ')" = "$((count + 1))" ] || return 1
    [ -z "$(find "$release" ! -type d ! -type f -print)" ] || return 1
}
normalize_locale() {
    # Territory/language are retained; only the codeset is case/hyphen insensitive.
    local value=$1
    case "$value" in
        *.*) printf '%s.' "${value%%.*}"; printf '%s' "${value#*.}" | tr '[:upper:]' '[:lower:]' | tr -d '-' ;;
        *) printf '%s' "$value" ;;
    esac
}
select_locale() {
    local requested=$1 candidate key
    key=$(normalize_locale "$requested")
    while IFS= read -r candidate; do
        if [ "$(normalize_locale "$candidate")" = "$key" ]; then
            locale_name=$candidate
            export LC_ALL="$locale_name"
            [ "$(locale charmap 2>&1)" = UTF-8 ] || fail 'approved locale is not UTF-8'
            return
        fi
    done < <(locale -a)
    fail 'approved locale unavailable'
}
extra_path() {
    local extra part current owner perms
    for extra in "$@"; do
        current=
        local oldifs=$IFS
        IFS=/
        read -r -a parts <<< "$extra"
        IFS=$oldifs
        for part in "${parts[@]}"; do
            [ -n "$part" ] || continue
            current="$current/$part"
            [ -d "$current" ] && [ ! -L "$current" ] || fail 'unsafe extra PATH'
            read -r owner perms <<< "$(metadata "$current")"
            [ "$owner" = 0 ] || [ "$owner" = "$(id -u)" ] || fail 'unsafe extra PATH'
            (( (8#$perms & 0022) == 0 )) || fail 'unsafe extra PATH'
        done
    done
    # Retain target account PATH; only explicit approved extras are prepended.
    for (( index=$#; index>0; index-- )); do
        PATH="${!index}:$PATH"
    done
    export PATH
}
select_term() {
    local candidate
    for candidate in "${TERM:-}" xterm-256color vt100 dumb; do
        case "$candidate" in ''|*[!A-Za-z0-9._+-]*) continue ;; esac
        if infocmp "$candidate" >/dev/null 2>&1; then
            TERM=$candidate
            export TERM
            return
        fi
    done
    fail 'no supported terminal'
}
version_line() {
    local tool=$1
    shift
    if command -v "$tool" >/dev/null 2>&1; then
        # Read at most one bounded display line, never an environment/config dump.
        NVIM_LOG_FILE=/dev/null "$tool" "$@" 2>&1 | head -c 256 | head -n 1 | tr -cd '[:print:]'
    else
        printf unavailable
    fi
}
probe() {
    [ -x /bin/bash ] || fail 'Bash /bin/bash required'
    case "$(tar --version 2>/dev/null)" in *'GNU tar'*|*bsdtar*) ;; *) fail 'unsupported tar' ;; esac
    if command -v sha256sum >/dev/null 2>&1; then hash_tool=sha256sum
    elif command -v shasum >/dev/null 2>&1; then hash_tool=shasum
    else fail 'SHA-256 unavailable'; fi
    printf 'protocol=1\ntar=ustar\nhash=%s\n' "$hash_tool"
    printf 'charmap=%s\nlocale=%s\n' "$(locale charmap)" "$locale_name"
    printf 'os=%s\narch=%s\n' "$(uname -s | head -c 64)" "$(uname -m | head -c 64)"
    printf 'bash=%s\nnvim_version=%s\nmosh_version=%s\ntmux_version=%s\n' \
        "$(version_line /bin/bash --version)" "$(version_line nvim --version)" \
        "$(version_line mosh-server --version)" "$(version_line tmux -V)"
    select_term
    printf 'term=%s\n' "$TERM"
    for term in xterm-256color tmux-256color; do
        if infocmp "$term" >/dev/null 2>&1; then present=1; else present=0; fi
        case "$term" in xterm-*) printf 'terminfo_xterm=%s\n' "$present" ;; *) printf 'terminfo_tmux=%s\n' "$present" ;; esac
    done
    for tool in nvim git starship rg fd fdfind fzf tmux mosh-server; do
        if command -v "$tool" >/dev/null 2>&1; then printf '%s=1\n' "$tool"; else printf '%s=0\n' "$tool"; fi
    done
}
operation=$1
PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
export PATH
if [ "$operation" = probe ]; then
    locale_name=${2:-}
    if [ -n "$locale_name" ]; then select_locale "$locale_name"; else locale_name=default; fi
    probe
    exit
fi
root=$2
digest=$3
archive_hash=$4
manifest=$(printf '%s' "$5")
locale_name=$6
mode=$7
case "$operation" in stage|inspect|launch) ;; *) fail 'unknown operation' ;; esac
case "$mode" in persistent|temporary) ;; *) fail 'bad storage mode' ;; esac
[ "${#digest}" = 64 ] && [ "${#archive_hash}" = 64 ] || fail 'bad digest'
case "$digest$archive_hash" in *[!a-f0-9]*) fail 'bad digest alphabet' ;; esac
shift 7
extra_path "$@"
if [ "$operation" = inspect ]; then
    select_locale "$locale_name"
    probe
fi
# The local policy owns this absolute root. No inferred HOME destination.
private_path "$root"
for dir in releases staging locks state; do private_path "$root/$dir"; done
release="$root/releases/$digest"
if [ "$operation" = inspect ]; then
    if [ -e "$release" ] || [ -L "$release" ]; then
        check_release "$release" || fail 'cached release invalid'
        printf 'ready=%s\n' "$digest"
    else
        printf 'missing=%s\n' "$digest"
    fi
    exit
fi
if [ "$operation" = launch ]; then
    check_release "$release" || fail 'cached release invalid'
    select_term
    private_path "$root/state/$digest"
    state=$(mktemp -d "$root/state/$digest/session.XXXXXXXX") || fail 'state creation failed'
    # enter performs one final environment reset; no exported caller state survives.
    exec "$release/bin/enter" "$release" "$state" "$locale_name" "$mode" "$root"
fi
lock="$root/locks/$digest"
mkdir "$lock" 2>/dev/null || fail 'release locked; never steal a stale lock'
stage=
cleanup() {
    [ -z "$stage" ] || rm -rf -- "$stage"
    rmdir "$lock"
}
trap cleanup EXIT
trap 'exit 23' HUP INT TERM
if [ -e "$release" ] || [ -L "$release" ]; then
    check_release "$release" || fail 'existing release invalid; preserved for inspection'
    printf 'ready=%s\n' "$digest"
    exit
fi
stage=$(mktemp -d "$root/staging/upload.XXXXXXXX") || fail 'staging creation failed'
# Limit the read even for a broken sender. A partial archive never gets extracted.
dd bs=1 count=262145 of="$stage/archive.tgz" 2>/dev/null
[ "$(wc -c < "$stage/archive.tgz" | tr -d ' ')" -le 262144 ] || fail 'archive exceeds bound'
[ "$(hash "$stage/archive.tgz")" = "$archive_hash" ] || fail 'archive hash mismatch'
# Exact archive bytes are already approved by the local closed packer/validator.
mkdir "$stage/release"
tar -xzpf "$stage/archive.tgz" -C "$stage/release" || fail 'extract failed'
check_release "$stage/release" || fail 'extracted release invalid'
# Same-filesystem rename under a non-stealable per-release lock. No live mutation.
mv "$stage/release" "$release" || fail 'publish failed'
check_release "$release" || fail 'published release invalid'
printf 'ready=%s\n' "$digest"
