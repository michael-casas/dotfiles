#!/usr/bin/env bash
# The production launcher (envi) and the dev profile (envi-dev), in a sandbox.
#   nvim/bin/test/launcher.sh
# shellcheck source=nvim/bin/test/sandbox.sh
. "$(dirname "$0")/sandbox.sh"

# Production: ~/.dotfiles/nvim, linked as the default profile; envi on PATH.
make_config "$HOME/.dotfiles"
mkdir -p "$XDG_CONFIG_HOME" "$HOME/.local/bin"
ln -s "$HOME/.dotfiles/nvim" "$XDG_CONFIG_HOME/nvim"
ln -s "$HOME/.dotfiles/nvim/bin/envi" "$HOME/.local/bin/envi"
ln -s "$HOME/.dotfiles/nvim/bin/envi-dev" "$HOME/.local/bin/envi-dev"
export PATH="$HOME/.local/bin:$PATH"

# Three dev worktrees: slot 3 of two different Treehouse pools, and a plain folder.
wt_a="$sandbox/repo-a/.treehouse/.dotfiles-aaaaaa/3/.dotfiles"
wt_b="$sandbox/repo-b/.treehouse/.dotfiles-bbbbbb/3/.dotfiles"
wt_c="$sandbox/Scratch Tree"
for wt in "$wt_a" "$wt_b" "$wt_c"; do make_config "$wt"; done

probe() { tail -n 1 "$PROBE_OUT"; }
field() { probe | tr ' ' '\n' | sed -n "s/^$1=//p"; }

# ── dev profiles, real nvim ──────────────────────────────────────────────

: >"$PROBE_OUT"
ENVI_SESSION=dotfiles envi-dev "$wt_a" --headless +qa 2>"$sandbox/err-a"
app_a="$(field appname)"
slot_a="${app_a#envi-dev/}"
check "dev A: profile is envi-dev/slot3-<id>" test "${app_a%-*}" = "envi-dev/slot3"
check "dev A: the slot is printed" has "$sandbox/err-a" "dev profile $app_a ($wt_a)"
check "dev A: config resolves into worktree A" test "$(field config)" = "$wt_a/nvim"
check "dev A: state is its own" test "$(field state)" = "$XDG_STATE_HOME/$app_a"
check "dev A: a production session name becomes dev-dotfiles" test "$(field session)" = dev-dotfiles
check "dev A: launcher-started, so reloadable" test "$(field reloadable)" = true
check "dev A: ENVI_DEV is cleared inside nvim" test -z "$(field envi_dev)"
check "dev A: the session runs in the worktree" test "$(field cwd)" = "$wt_a"
check "dev A: plugins shared with production" test "$(readlink "$XDG_DATA_HOME/$app_a")" = "$XDG_DATA_HOME/nvim"
check "dev A: shada written in its own state" test -f "$XDG_STATE_HOME/$app_a/shada/main.shada"

ENVI_SESSION=x envi-dev "$wt_a" --headless +qa 2>/dev/null
check "dev A: same worktree, same profile on every run" test "$(field appname)" = "$app_a"

ENVI_SESSION=b envi-dev "$wt_b" --headless +qa 2>/dev/null
app_b="$(field appname)"
check "dev B: same slot number, another pool: a different profile" test "$app_b" != "$app_a"
check "dev B: config resolves into worktree B" test "$(field config)" = "$wt_b/nvim"
check "dev A link still points at worktree A" test "$(readlink "$XDG_CONFIG_HOME/$app_a")" = "$wt_a/nvim"

ENVI_SESSION=c ENVI_DEV="$wt_c" envi --headless +qa 2>/dev/null
app_c="$(field appname)"
check "ENVI_DEV=<path> envi: a plain folder gets a named id" test "${app_c%-*}" = "envi-dev/scratch-tree"
check "three worktrees, three profiles" test "$(printf '%s\n' "$app_a" "$app_b" "$app_c" | sort -u | wc -l | tr -d ' ')" = 3

# Run from inside the worktree, no argument: the current git worktree.
git -C "$wt_a" init -q
(cd "$wt_a/nvim/lua" && ENVI_SESSION=y envi-dev --headless +qa 2>/dev/null)
check "envi-dev with no worktree uses the current git worktree" test "$(field appname)" = "$app_a"

# A link that already points at another worktree is never repointed.
ln -s "$wt_b/nvim" "$XDG_CONFIG_HOME/envi-dev/collide"
before="$(readlink "$XDG_CONFIG_HOME/envi-dev/collide")"
# Drive the real launcher at a colliding slot: give worktree A's id to a link for B.
mv "$XDG_CONFIG_HOME/$app_a" "$sandbox/a-link"
ln -s "$wt_b/nvim" "$XDG_CONFIG_HOME/$app_a"
if ENVI_SESSION=z envi-dev "$wt_a" --headless +qa 2>"$sandbox/err-collide"; then
  bad "a profile link owned by another worktree is refused"
else
  ok "a profile link owned by another worktree is refused"
fi
check "  ... and left as it was" test "$(readlink "$XDG_CONFIG_HOME/$app_a")" = "$wt_b/nvim"
check "  ... with a reason" has "$sandbox/err-collide" "not repointing"
rm "$XDG_CONFIG_HOME/$app_a"
mv "$sandbox/a-link" "$XDG_CONFIG_HOME/$app_a"
rm "$XDG_CONFIG_HOME/envi-dev/collide"
check "unrelated link untouched" test "$before" = "$wt_b/nvim"

# :reload in a dev nvim comes back in the same dev profile and session.
: >"$PROBE_OUT"
PROBE_RELOAD_ONCE="$sandbox/reload-once" ENVI_SESSION=reload envi-dev "$wt_a" --headless 2>/dev/null
check ":reload: nvim ran twice" test "$(wc -l <"$PROBE_OUT" | tr -d ' ')" = 2
check ":reload: same dev profile after the restart" test "$(field appname)" = "$app_a"
check ":reload: same dev session after the restart" test "$(field session)" = dev-reload

# Production was never written by any of that.
check "dev runs: no production state folder" test ! -e "$XDG_STATE_HOME/nvim"
check "dev runs: no production session document" lacks "$HC_LOG" "^doc\.[a-z]* nvs\.[^d]"
check "dev runs: production index never read or written" lacks "$HC_LOG" "^doc\.[a-z]* nvs-index$"
check "dev runs: the dev index was used" has "$HC_LOG" "^doc.set nvs-dev-index$"
check "dev runs: production config link unchanged" test "$(readlink "$XDG_CONFIG_HOME/nvim")" = "$HOME/.dotfiles/nvim"

# ── production, real nvim ────────────────────────────────────────────────

: >"$HC_LOG"
NVIM_APPNAME="$app_a" ENVI_SESSION=prodtest envi --headless +qa 2>/dev/null
check "envi: an inherited NVIM_APPNAME is dropped (default profile)" test -z "$(field appname)"
check "envi: config resolves into ~/.dotfiles" test "$(field config)" = "$HOME/.dotfiles/nvim"
check "envi: production state" test "$(field state)" = "$XDG_STATE_HOME/nvim"
check "envi: production session name kept" test "$(field session)" = prodtest
check "envi: production documents" has "$HC_LOG" "^doc.set nvs.prodtest$"
check "envi: production index" has "$HC_LOG" "^doc.set nvs-index$"
check "envi: the session runs in ~/.dotfiles" test "$(field cwd)" = "$HOME/.dotfiles"

: >"$PROBE_OUT"
PROBE_RELOAD_ONCE="$sandbox/reload-prod" ENVI_SESSION=prodtest envi --headless 2>/dev/null
check "envi :reload: restarts on the same production session" test "$(wc -l <"$PROBE_OUT" | tr -d ' '):$(field session):$(field appname)" = "2:prodtest:"

# Session management, through the real session CLI.
: >"$HC_LOG"
envi ls >"$sandbox/ls-prod"
check "envi ls lists production sessions" has "$sandbox/ls-prod" "prodtest"
check "envi ls reads the production index" has "$HC_LOG" "^doc.get nvs-index$"
: >"$HC_LOG"
(cd "$wt_a" && envi-dev sessions >"$sandbox/ls-dev" 2>/dev/null)
check "envi-dev sessions lists dev sessions" has "$sandbox/ls-dev" "dev-reload"
check "envi-dev sessions never lists production ones" lacks "$sandbox/ls-dev" "prodtest"
check "envi-dev sessions reads only the dev index" lacks "$HC_LOG" "^doc.get nvs-index$"

# ── launcher logic, fake nvim ────────────────────────────────────────────

make_fake_nvim
fakerun() { PATH="$sandbox/fake:$PATH" "$@"; tail -n 1 "$FAKE_LOG"; }
mkdir -p "$sandbox/elsewhere"
cd "$sandbox/elsewhere"
check "envi: the dotfiles session in ~/.dotfiles" test \
  "$(fakerun envi 2>/dev/null)" = "appname=<unset> session=dotfiles cwd=$HOME/.dotfiles envi_dev=<unset> args="
check "envi <file>: no session, caller's folder" test \
  "$(fakerun envi notes.txt 2>/dev/null)" = "appname=<unset> session=<unset> cwd=$sandbox/elsewhere envi_dev=<unset> args=notes.txt"
check "envi-dev: the dev-<slot> session in the worktree" test \
  "$(fakerun envi-dev "$wt_a" 2>/dev/null)" = "appname=$app_a session=dev-$slot_a cwd=$wt_a envi_dev=$wt_a args="
check "envi-dev <file>: no session" test \
  "$(fakerun envi-dev "$wt_a" notes.txt 2>/dev/null | cut -d' ' -f1-2)" = "appname=$app_a session=<unset>"
check "envi-dev: ENVI_SESSION gets the dev- prefix" test \
  "$(fakerun env ENVI_SESSION=dotfiles envi-dev "$wt_a" 2>/dev/null | cut -d' ' -f2)" = "session=dev-dotfiles"
check "envi from inside a dev nvim (inherited NVIM_APPNAME) is production" test \
  "$(fakerun env NVIM_APPNAME="$app_a" envi 2>/dev/null | cut -d' ' -f1-2)" = "appname=<unset> session=dotfiles"

# ── stale profiles ───────────────────────────────────────────────────────

envi-dev ls >"$sandbox/dev-ls"
check "envi-dev ls shows each profile live" test "$(grep -c ' live ' "$sandbox/dev-ls")" = 3
rm -rf "$wt_c"
envi-dev ls >"$sandbox/dev-ls"
check "envi-dev ls marks a removed worktree stale" has "$sandbox/dev-ls" "^${app_c#envi-dev/} *stale"
envi-dev prune --dry-run --stale >"$sandbox/prune-dry"
check "prune --dry-run lists, removes nothing" test -L "$XDG_CONFIG_HOME/$app_c" -a -d "$XDG_STATE_HOME/$app_c"
check "prune --dry-run names the paths" has "$sandbox/prune-dry" "would remove $XDG_STATE_HOME/$app_c"
envi-dev prune --stale >/dev/null
check "prune --stale removes the stale profile" test ! -e "$XDG_CONFIG_HOME/$app_c" -a ! -L "$XDG_CONFIG_HOME/$app_c" -a ! -e "$XDG_STATE_HOME/$app_c"
check "prune --stale keeps shared plugins" test -d "$XDG_DATA_HOME/nvim"
check "prune --stale keeps live profiles" test -L "$XDG_CONFIG_HOME/$app_a" -a -L "$XDG_CONFIG_HOME/$app_b"
if envi-dev prune "$slot_a" 2>/dev/null; then bad "prune refuses a live profile"; else ok "prune refuses a live profile"; fi
check "  ... and keeps it" test -L "$XDG_CONFIG_HOME/$app_a"

finish
