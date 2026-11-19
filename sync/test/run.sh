#!/bin/bash
# Sandbox tests for sync/dotfiles-sync and sync/dotfiles-sync-agent.
#   sync/test/run.sh
# Everything lives in a temp HOME: a bare "origin", a production clone standing
# in for ~/.dotfiles, and a second clone that pushes. Runs under macOS /bin/bash
# (3.2), like launchd does. Nothing outside the temp dir is touched.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
sync="$here/dotfiles-sync"
agent="$here/dotfiles-sync-agent"
root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sync-test.XXXXXX")"
trap 'rm -rf "$root"' EXIT

export HOME="$root/home" XDG_STATE_HOME="$root/home/.local/state"
unset DOTFILES_SYNC_REPO DOTFILES_SYNC_STATE DOTFILES_SYNC_LOG_MAX
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
git config --global init.defaultBranch main
git config --global merge.autoStash true # the sync must not stash even so
state="$XDG_STATE_HOME/dotfiles-sync"
prod="$HOME/.dotfiles"
dev="$root/dev"

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # check <name> <command...>
  name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
push() { # push <file> <text>: commit in the dev clone and push to origin
  mkdir -p "$(dirname "$dev/$1")"
  printf '%s\n' "$2" >"$dev/$1"
  git -C "$dev" add -A && git -C "$dev" commit -qm "change $1" && git -C "$dev" push -q origin main
}
head_of() { git -C "$prod" rev-parse HEAD; }
log_lines() { if [ -f "$state/sync.log" ]; then wc -l <"$state/sync.log" | tr -d ' '; else echo 0; fi; }

git init -q --bare "$root/origin.git"
git clone -q "$root/origin.git" "$dev" 2>/dev/null
mkdir -p "$dev/nvim/lua/plugins" "$dev/.agents/skills/.system/imagegen"
echo 'return {}' >"$dev/nvim/lua/plugins/neo-tree.lua"
echo 'skill' >"$dev/.agents/skills/.system/imagegen/SKILL.md"
echo 'marker' >"$dev/.agents/skills/.system/.codex-system-skills.marker"
echo 'ignored/' >"$dev/.gitignore"
git -C "$dev" add -A && git -C "$dev" commit -qm init && git -C "$dev" push -q origin main
git clone -q "$root/origin.git" "$prod"

# 1. Nothing to do: quiet (no output, no log line), exit 0.
out="$("$sync" 2>&1)"
rc=$?
check "nothing to do: exit 0" [ "$rc" -eq 0 ]
check "nothing to do: no output" [ -z "$out" ]
check "nothing to do: last says uptodate" grep -q ' uptodate ' "$state/last"
n0="$(log_lines)"
"$sync"
check "repeat run adds no log line" [ "$(log_lines)" -eq "$n0" ]

# 2. The owner's uncommitted deletions elsewhere don't block a fast-forward.
rm "$prod/.agents/skills/.system/imagegen/SKILL.md" "$prod/.agents/skills/.system/.codex-system-skills.marker"
dirty_before="$(git -C "$prod" status --porcelain)"
push nvim/lua/a.lua 'return 1'
before="$(head_of)"
out="$("$sync" now)"
rc=$?
check "ff with unrelated deletions: exit 0" [ "$rc" -eq 0 ]
check "ff with unrelated deletions: moved to origin/main" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]
check "ff: 'now' prints the result" sh -c "printf '%s' \"\$1\" | grep -q '^dotfiles-sync: synced ${before:0:7}\.\.'" _ "$out"
check "ff: deletions still there" [ "$(git -C "$prod" status --porcelain)" = "$dirty_before" ]
check "ff: logged" grep -q ' synced ' "$state/sync.log"

# 3. A dirty file inside nvim/ that the update touches: blocked, nothing changes.
echo '-- local edit' >>"$prod/nvim/lua/plugins/neo-tree.lua"
local_copy="$(cat "$prod/nvim/lua/plugins/neo-tree.lua")"
push nvim/lua/plugins/neo-tree.lua 'return { upstream = true }'
before="$(head_of)"
out="$("$sync" now)"
rc=$?
check "dirty nvim file: exit 1" [ "$rc" -eq 1 ]
check "dirty nvim file: HEAD unchanged" [ "$(head_of)" = "$before" ]
check "dirty nvim file: local edit kept" [ "$(cat "$prod/nvim/lua/plugins/neo-tree.lua")" = "$local_copy" ]
check "dirty nvim file: last names the path" grep -q ' blocked local changes in nvim/lua/plugins/neo-tree.lua$' "$state/last"
check "dirty nvim file: log names the path" grep -q 'blocked local changes in nvim/lua/plugins/neo-tree.lua' "$state/sync.log"
check "dirty nvim file: 'now' says blocked" sh -c "printf '%s' \"\$1\" | grep -q '^dotfiles-sync: blocked local changes in nvim/lua/plugins/neo-tree.lua'" _ "$out"
n1="$(log_lines)"
"$sync"
check "blocked again: same result, no new log line" [ "$(log_lines)" -eq "$n1" ]
check "no stash was ever made" [ -z "$(git -C "$prod" stash list)" ]
# The owner resolves it (here: drops the edit); the next run catches up.
git -C "$prod" checkout -q -- nvim/lua/plugins/neo-tree.lua
check "after the owner cleans up: syncs" "$sync"
check "after the owner cleans up: at origin/main" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]

# 4. An untracked file where the update adds one: blocked, file untouched.
echo 'mine' >"$prod/nvim/lua/new.lua"
push nvim/lua/new.lua 'theirs'
before="$(head_of)"
"$sync"
rc=$?
check "untracked in the way: exit 1" [ "$rc" -eq 1 ]
check "untracked in the way: HEAD unchanged" [ "$(head_of)" = "$before" ]
check "untracked in the way: file untouched" [ "$(cat "$prod/nvim/lua/new.lua")" = mine ]
check "untracked in the way: named" grep -q 'blocked local changes in nvim/lua/new.lua$' "$state/last"
rm "$prod/nvim/lua/new.lua"
"$sync"

# 5. An ignored file where the update adds one (git would overwrite it silently).
mkdir -p "$prod/ignored"
echo 'mine' >"$prod/ignored/x"
git -C "$dev" add -f ignored >/dev/null 2>&1
mkdir -p "$dev/ignored" && echo theirs >"$dev/ignored/x"
git -C "$dev" add -f ignored/x && git -C "$dev" commit -qm ignored && git -C "$dev" push -q origin main
before="$(head_of)"
"$sync"
check "ignored file in the way: blocked" grep -q 'blocked local changes in ignored/x$' "$state/last"
check "ignored file in the way: untouched" [ "$(cat "$prod/ignored/x")" = mine ]
check "ignored file in the way: HEAD unchanged" [ "$(head_of)" = "$before" ]
rm -rf "$prod/ignored"
"$sync"

# 6. Not on main: skipped, untouched.
git -C "$prod" switch -q -c side
push nvim/lua/b.lua 'return 2'
before="$(head_of)"
"$sync"
rc=$?
check "not on main: exit 3" [ "$rc" -eq 3 ]
check "not on main: untouched" [ "$(head_of)" = "$before" ]
check "not on main: says why" grep -q ' skip .* is on side, not main$' "$state/last"
git -C "$prod" switch -q main

# 7. Diverged: refused, untouched.
git -C "$prod" commit -q --allow-empty -m local
before="$(head_of)"
"$sync"
rc=$?
check "diverged: exit 1" [ "$rc" -eq 1 ]
check "diverged: untouched" [ "$(head_of)" = "$before" ]
check "diverged: refused" grep -q ' refused .*have diverged' "$state/last"
git -C "$prod" reset -q --hard HEAD~1 # test cleanup in the sandbox only
"$sync"

# 8. Lock: a live holder makes a periodic run back off quietly; a dead one is taken over.
mkdir "$state/lock"
sleep 30 &
holder=$!
echo "$holder" >"$state/lock/pid"
push nvim/lua/c.lua 'return 3'
before="$(head_of)"
out="$("$sync" 2>&1)"
rc=$?
check "locked: periodic run exits 3" [ "$rc" -eq 3 ]
check "locked: quiet" [ -z "$out" ]
check "locked: untouched" [ "$(head_of)" = "$before" ]
DOTFILES_SYNC_WAIT=1 "$sync" now >/dev/null 2>&1
check "locked: 'now' gives up after DOTFILES_SYNC_WAIT" [ $? -eq 3 ]
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
"$sync" # the dead holder's lock is cleared on this run …
"$sync" # … and this one takes it
check "stale lock: taken over and synced" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]
check "lock released" [ ! -d "$state/lock" ]
# `now` waits for a running sync to finish, then runs.
mkdir "$state/lock"
(sleep 2 && rm -rf "$state/lock") &
push nvim/lua/d.lua 'return 4'
"$sync" now >/dev/null
check "now: waited for the lock, then synced" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]

# 9. Log rotation.
for i in 1 2 3 4 5 6; do push "nvim/lua/r$i.lua" "return $i"; DOTFILES_SYNC_LOG_MAX=200 "$sync"; done
check "log rotated: sync.log.1 exists" [ -f "$state/sync.log.1" ]
check "log rotated: sync.log stays small" [ "$(wc -c <"$state/sync.log")" -le 400 ]

# 10. status
check "status prints the last result" sh -c "\"$sync\" status | head -1 | grep -q ' synced '"

# 11. LaunchAgent template: no host paths; rendered from \$HOME; plutil-clean.
check "template has no host paths" sh -c "! grep -E '/Users/|/home/' \"$here/dotfiles-sync.plist.in\""
agents="$root/LaunchAgents"
mkdir -p "$prod/sync" && cp "$sync" "$prod/sync/" # what the agent runs
DOTFILES_SYNC_AGENTS_DIR="$agents" "$agent" install --no-load >/dev/null
plist="$agents/local.dotfiles-sync.plist"
check "install --no-load wrote the plist" [ -f "$plist" ]
check "plutil -lint" plutil -lint "$plist"
check "rendered from \$HOME" grep -q "<string>$HOME/.dotfiles/sync/dotfiles-sync</string>" "$plist"
check "no tokens left" sh -c "! grep -q '@[A-Z]*@' \"$plist\""
check "StartInterval 60 and RunAtLoad" sh -c "plutil -extract StartInterval raw \"$plist\" | grep -qx 60 && plutil -extract RunAtLoad raw \"$plist\" | grep -qx true"
DOTFILES_SYNC_AGENTS_DIR="$agents" "$agent" uninstall --no-load >/dev/null
check "uninstall --no-load removed it" [ ! -f "$plist" ]

if [ "$fails" -gt 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "dotfiles-sync tests passed"
