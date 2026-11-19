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

# 8. Lock: an flock on <git dir>/dotfiles-sync.lock, shared by `run` and
# `now`, released by the kernel when its holders exit or are killed.
lock="$prod/.git/dotfiles-sync.lock"
hold_lock() { # hold the lock in the background for $1 seconds; sets $holder
  (exec 9>>"$lock" && exec perl -e 'use Fcntl qw(:flock); open(my $fh, ">&=", 9) or die; flock($fh, LOCK_EX) or die; sleep shift' "$1") </dev/null >/dev/null 2>&1 &
  holder=$!
}
hold_lock 30
sleep 0.5
push nvim/lua/c.lua 'return 3'
before="$(head_of)"
out="$("$sync" 2>&1)"
rc=$?
check "locked: periodic run exits 3" [ "$rc" -eq 3 ]
check "locked: quiet" [ -z "$out" ]
check "locked: untouched" [ "$(head_of)" = "$before" ]
DOTFILES_SYNC_WAIT=1 "$sync" now >/dev/null 2>&1
check "locked: 'now' gives up after DOTFILES_SYNC_WAIT" [ $? -eq 3 ]
kill -KILL "$holder"
wait "$holder" 2>/dev/null
"$sync"
check "holder killed (SIGKILL): the next run syncs" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]
# `now` waits for a running sync to finish, then runs.
hold_lock 2
sleep 0.5
push nvim/lua/d.lua 'return 4'
"$sync" now >/dev/null
check "now: waited for the lock, then synced" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]
wait "$holder" 2>/dev/null
# Two runs started together never overlap: the fetch is slowed down and marks
# its time inside; a second run inside at the same time is recorded.
real_git="$(command -v git)"
hooks="$root/hooks"
mkdir -p "$hooks"
cat >"$hooks/git" <<HOOK
#!/bin/bash
# SLOW_FETCH=<dir>: the fetch takes 1 s and records overlapping runs.
# HOOK_AT=<subcommand> HOOK_NTH=<n> HOOK_WHEN=before|after HOOK_DO=<shell>:
# run HOOK_DO around the n-th call of that subcommand.
for a in "\$@"; do
  if [ "\$a" = fetch ] && [ -n "\${SLOW_FETCH:-}" ]; then
    mkdir "\$SLOW_FETCH/inside" 2>/dev/null || touch "\$SLOW_FETCH/overlap"
    sleep 1
    "$real_git" "\$@"; rc=\$?
    rmdir "\$SLOW_FETCH/inside"
    exit \$rc
  fi
  if [ "\$a" = "\${HOOK_AT:-none}" ]; then
    n=\$(( \$(cat "$root/hook.count" 2>/dev/null || echo 0) + 1 ))
    echo \$n >"$root/hook.count"
    [ "\$n" -eq "\${HOOK_NTH:-1}" ] || break
    [ "\${HOOK_WHEN:-after}" = before ] && eval "\$HOOK_DO"
    "$real_git" "\$@"; rc=\$?
    [ "\${HOOK_WHEN:-after}" = after ] && eval "\$HOOK_DO"
    exit \$rc
  fi
done
exec "$real_git" "\$@"
HOOK
chmod +x "$hooks/git"
marks="$root/marks"
mkdir -p "$marks"
push nvim/lua/race.lua 'return 5'
PATH="$hooks:$PATH" SLOW_FETCH="$marks" "$sync" now >"$marks/a.out" 2>&1 &
pa=$!
PATH="$hooks:$PATH" SLOW_FETCH="$marks" "$sync" now >"$marks/b.out" 2>&1 &
pb=$!
sleep 0.4
"$sync" # a periodic run in the middle backs off
rc_run=$?
wait "$pa"
ra=$?
wait "$pb"
rb=$?
check "concurrent runs: never inside together" [ ! -e "$marks/overlap" ]
check "concurrent runs: a periodic run backs off (3)" [ "$rc_run" -eq 3 ]
check "concurrent runs: both 'now' runs finish (0)" [ "$ra" -eq 0 ] && [ "$rb" -eq 0 ]
check "concurrent runs: one synced, the other found it up to date" sh -c "cat '$marks/a.out' '$marks/b.out' | grep -c -e ' synced ' -e ' uptodate ' | grep -qx 2"
# The shell is killed while its merge is still running: the merge keeps the
# lock, so another run reports busy and HEAD stays put until the merge is
# done; then the next run is a no-op. (The merge is parked by the hook.)
push nvim/lua/killed.lua 'return 6'
before="$(head_of)"
rm -f "$root/hook.count" "$marks/go"
PATH="$hooks:$PATH" HOOK_AT=merge HOOK_WHEN=before HOOK_DO="echo \$\$ >'$marks/merge.pid'; while [ ! -e '$marks/go' ]; do sleep 0.05; done" "$sync" now >/dev/null 2>&1 &
shell=$!
for _ in $(seq 100); do [ -s "$marks/merge.pid" ] && break; sleep 0.05; done
kill -KILL "$shell"
wait "$shell" 2>/dev/null
child="$(cat "$marks/merge.pid")"
check "killed shell: its merge child is still alive" kill -0 "$child"
"$sync"
rc=$?
check "killed shell, live merge: next run is busy (3)" [ "$rc" -eq 3 ]
check "killed shell, live merge: HEAD unchanged" [ "$(head_of)" = "$before" ]
DOTFILES_SYNC_WAIT=1 "$sync" now >/dev/null 2>&1
check "killed shell, live merge: 'now' busy too" [ $? -eq 3 ]
touch "$marks/go"
for _ in $(seq 100); do kill -0 "$child" 2>/dev/null || break; sleep 0.05; done
"$sync"
rc=$?
check "after the merge finished: the next run succeeds" [ "$rc" -eq 0 ]
check "after the merge finished: at origin/main" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]
# Split state: a run with another log directory still shares the lock.
hold_lock 30
push nvim/lua/split.lua 'return 7'
before="$(head_of)"
DOTFILES_SYNC_STATE="$root/other-state" DOTFILES_SYNC_WAIT=1 "$sync" now >/dev/null 2>&1
rc=$?
check "another state dir: same lock, busy (3)" [ "$rc" -eq 3 ]
check "another state dir: HEAD unchanged" [ "$(head_of)" = "$before" ]
kill -KILL "$holder"
wait "$holder" 2>/dev/null
DOTFILES_SYNC_STATE="$root/other-state" "$sync"
check "another state dir: syncs once free" [ "$(head_of)" = "$(git -C "$dev" rev-parse HEAD)" ]
check "the lock lives in the git dir" [ -f "$lock" ] && [ ! -e "$state/sync.lock" ]

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

# 12. Paths compared byte for byte (NUL-delimited): an ignored non-ASCII file.
printf '*.local\n' >>"$dev/.gitignore"
git -C "$dev" add .gitignore && git -C "$dev" commit -qm ignore-local && git -C "$dev" push -q origin main
"$sync"
echo owner >"$prod/café.local"
echo incoming >"$dev/café.local"
git -C "$dev" add -f "café.local" && git -C "$dev" commit -qm cafe && git -C "$dev" push -q origin main
before="$(head_of)"
"$sync"
check "ignored non-ASCII file: blocked" grep -q ' blocked local changes in café.local$' "$state/last"
check "ignored non-ASCII file: untouched" [ "$(cat "$prod/café.local")" = owner ]
check "ignored non-ASCII file: HEAD unchanged" [ "$(head_of)" = "$before" ]
rm "$prod/café.local"
"$sync"

# 13. Staged and unstaged edits that cancel out in the worktree still block.
echo staged >"$prod/nvim/lua/a.lua"
git -C "$prod" add nvim/lua/a.lua
git -C "$prod" show HEAD:nvim/lua/a.lua >"$prod/nvim/lua/a.lua"
push nvim/lua/a.lua 'return 7'
before="$(head_of)"
"$sync"
check "staged + unstaged: blocked, named" grep -q ' blocked local changes in nvim/lua/a.lua$' "$state/last"
check "staged + unstaged: index kept" [ "$(git -C "$prod" show :nvim/lua/a.lua)" = staged ]
check "staged + unstaged: HEAD unchanged" [ "$(head_of)" = "$before" ]
git -C "$prod" reset -q -- nvim/lua/a.lua # sandbox cleanup
"$sync"

# 14. The checkout changes mid-run: right after the fetch, or right after the
# path check. It skips; the other branch and main stay where they were.
# (verify runs `git symbolic-ref` at the start, after the fetch, and after the
# path check: its 3rd call is the first git command after the path check.)
for at in fetch preflight; do
  push "nvim/lua/switch-$at.lua" 'return 8'
  before="$(head_of)"
  rm -f "$root/hook.count"
  if [ "$at" = fetch ]; then h_at=fetch h_nth=1 h_when=after; else h_at=symbolic-ref h_nth=3 h_when=before; fi
  PATH="$hooks:$PATH" HOOK_AT=$h_at HOOK_NTH=$h_nth HOOK_WHEN=$h_when \
    HOOK_DO="$real_git -C '$prod' switch -q -c concurrent-$at" "$sync"
  rc=$?
  check "branch switched after $at: skipped (3)" [ "$rc" -eq 3 ]
  check "branch switched after $at: says so" grep -q " skip .* is on concurrent-$at, not main (the checkout changed during the sync)$" "$state/last"
  check "branch switched after $at: other branch untouched" [ "$(git -C "$prod" rev-parse "concurrent-$at")" = "$before" ]
  check "branch switched after $at: main untouched" [ "$(git -C "$prod" rev-parse main)" = "$before" ]
  git -C "$prod" switch -q main
done
"$sync"

# 15. An ignored file that appears after the path check (right before the merge): git refuses the merge
# (--no-overwrite-ignore) and the file survives.
echo incoming >"$dev/late.local"
git -C "$dev" add -f late.local && git -C "$dev" commit -qm late && git -C "$dev" push -q origin main
before="$(head_of)"
rm -f "$root/hook.count"
PATH="$hooks:$PATH" HOOK_AT=merge HOOK_WHEN=before HOOK_DO="echo owner >'$prod/late.local'" "$sync"
rc=$?
check "ignored file created after the check: refused (1)" [ "$rc" -eq 1 ]
check "ignored file created after the check: kept" [ "$(cat "$prod/late.local")" = owner ]
check "ignored file created after the check: HEAD unchanged" [ "$(head_of)" = "$before" ]
check "ignored file created after the check: git's reason logged" grep -q ' refused .*late.local' "$state/last"
rm "$prod/late.local"
"$sync"

# 15b. Switched at the very moment the merge starts (out of scope): git
# advances that branch. The result names it and the recovery, which works.
git -C "$prod" branch side-at-entry
push nvim/lua/entry.lua 'return 10'
before="$(head_of)"
incoming="$(git -C "$dev" rev-parse HEAD)"
rm -f "$root/hook.count"
PATH="$hooks:$PATH" HOOK_AT=merge HOOK_WHEN=before HOOK_DO="$real_git -C '$prod' switch -q side-at-entry" "$sync"
rc=$?
check "switched at merge entry: error (1)" [ "$rc" -eq 1 ]
check "switched at merge entry: wrongbranch names the branch" grep -q " wrongbranch the merge advanced side-at-entry (not main) from $before to $incoming; " "$state/last"
check "switched at merge entry: gives both recovery commands" grep -q "recover: git -C $prod reset --keep $before (while it is checked out), or git -C $prod branch -f side-at-entry $before$" "$state/last"
check "switched at merge entry: main untouched" [ "$(git -C "$prod" rev-parse main)" = "$before" ]
git -C "$prod" reset -q --keep "$before"
check "the recovery command restores the branch" [ "$(git -C "$prod" rev-parse side-at-entry)" = "$before" ] && [ -z "$(git -C "$prod" status --porcelain -- nvim/lua/entry.lua)" ]
git -C "$prod" switch -q main
"$sync"

# 16. Only the main checkout: not a linked worktree, not a subdirectory.
git -C "$prod" switch -q -c holding
git -C "$prod" worktree add -q "$root/linked" main
push nvim/lua/linked.lua 'return 9'
before="$(git -C "$root/linked" rev-parse HEAD)"
DOTFILES_SYNC_REPO="$root/linked" "$sync"
rc=$?
check "linked worktree at runtime: error (1)" [ "$rc" -eq 1 ]
check "linked worktree at runtime: untouched" [ "$(git -C "$root/linked" rev-parse HEAD)" = "$before" ]
check "linked worktree at runtime: says why" grep -q ' error .* is a linked worktree, not the main checkout$' "$state/last"
mkdir -p "$root/linked/sync" && cp "$sync" "$root/linked/sync/"
DOTFILES_SYNC_REPO="$root/linked" DOTFILES_SYNC_AGENTS_DIR="$agents" "$agent" install --no-load >/dev/null 2>&1
rc=$?
check "linked worktree: install refused, no plist" [ "$rc" -ne 0 ] && [ ! -e "$plist" ]
DOTFILES_SYNC_REPO="$prod/nvim" "$sync" check 2>/dev/null
check "subdirectory of the checkout: refused" [ $? -ne 0 ]
check "main checkout: accepted" "$sync" check
git -C "$prod" worktree remove --force "$root/linked"
git -C "$prod" switch -q main

if [ "$fails" -gt 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "dotfiles-sync tests passed"
