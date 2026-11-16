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
    stat -c '%u %a' "$1" 2>/dev/null || stat -f '%u %Lp' "$1"
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
        fi
    done
    read -r owner perms <<< "$(metadata "$path")"
    [ "$owner" = "$uid" ] && [ "$perms" = 700 ] || fail 'root must be owned mode 0700'
}
check_release() {
    local release=$1 mode size expected path count=0
    [ -d "$release" ] && [ ! -L "$release" ] || return 1
    [ -f "$release/MANIFEST" ] && [ ! -L "$release/MANIFEST" ] || return 1
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
    [ -z "$(find "$release" -type l -print)" ] || return 1
}
operation=$1
if [ "$operation" = probe ]; then
    [ -x /bin/bash ] || fail 'Bash /bin/bash required'
    case "$(tar --version 2>/dev/null)" in *'GNU tar'*|*bsdtar*) ;; *) fail 'unsupported tar' ;; esac
    if command -v sha256sum >/dev/null 2>&1; then hash_tool=sha256sum
    elif command -v shasum >/dev/null 2>&1; then hash_tool=shasum
    else fail 'SHA-256 unavailable'; fi
    printf 'protocol=1\ntar=ustar\nhash=%s\n' "$hash_tool"
    printf 'charmap=%s\n' "$(locale charmap)"
    for tool in nvim git starship rg fd fdfind fzf tmux mosh-server; do
        if command -v "$tool" >/dev/null 2>&1; then printf '%s=1\n' "$tool"; else printf '%s=0\n' "$tool"; fi
    done
    exit
fi
root=$2
digest=$3
archive_hash=$4
manifest=$5
locale_name=$6
mode=$7
case "$operation" in stage|cached|launch) ;; *) fail 'unknown operation' ;; esac
case "$mode" in persistent|temporary) ;; *) fail 'bad storage mode' ;; esac
[ "${#digest}" = 64 ] && [ "${#archive_hash}" = 64 ] || fail 'bad digest'
case "$digest$archive_hash" in *[!a-f0-9]*) fail 'bad digest alphabet' ;; esac
# The local policy owns this absolute root. No inferred HOME destination.
private_path "$root"
for dir in releases staging locks state; do private_path "$root/$dir"; done
release="$root/releases/$digest"
if [ "$operation" = launch ]; then
    check_release "$release" || fail 'cached release invalid'
    state=$(mktemp -d "$root/state/session.XXXXXXXX") || fail 'state creation failed'
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
[ "$operation" != cached ] || fail 'requested cached release missing'
stage=$(mktemp -d "$root/staging/upload.XXXXXXXX") || fail 'staging creation failed'
# Limit the read even for a broken sender. A partial archive never gets extracted.
dd bs=1 count=262145 of="$stage/archive.tgz" 2>/dev/null
[ "$(wc -c < "$stage/archive.tgz" | tr -d ' ')" -le 262144 ] || fail 'archive exceeds bound'
[ "$(hash "$stage/archive.tgz")" = "$archive_hash" ] || fail 'archive hash mismatch'
# Exact archive bytes are already approved by the local closed packer/validator.
mkdir "$stage/release"
tar -xzf "$stage/archive.tgz" -C "$stage/release" || fail 'extract failed'
check_release "$stage/release" || fail 'extracted release invalid'
# Same-filesystem rename under a non-stealable per-release lock. No live mutation.
mv "$stage/release" "$release" || fail 'publish failed'
check_release "$release" || fail 'published release invalid'
printf 'ready=%s\n' "$digest"
