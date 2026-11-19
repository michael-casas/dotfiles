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
check "dev runs: no production session document" lacks "$HC_LOG" "^doc\.[a-z]* nvs\."
check "dev runs: production index never read or written" lacks "$HC_LOG" "^doc\.[a-z]* nvs-index$"
check "dev runs: the dev index was used" has "$HC_LOG" "^doc.set nvsdev-index$"
check "dev runs: dev documents in their own namespace" has "$HC_LOG" "^doc.set nvsdev.dev-dotfiles$"
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

# ── r1: namespace collision, legacy worktrees, aliases, nested launches ──

# A production session whose name starts with dev- is out of a dev profile's reach.
: >"$HC_LOG"
ENVI_SESSION=dev-existing-production envi --headless +qa 2>/dev/null
check "production may name a session dev-*" has "$HC_LOG" "^doc.set nvs.dev-existing-production$"
cp "$HC_DOCS" "$sandbox/docs-before"
: >"$HC_LOG"
(cd "$wt_a" && envi-dev kill dev-existing-production -f >/dev/null 2>&1) || :
check "envi-dev kill never touches the production dev-* document" lacks "$HC_LOG" "nvs\.dev-existing-production"
check "  ... which is unchanged" python3 -I -c '
import json, sys
a, b = (json.load(open(f)) for f in sys.argv[1:])
sys.exit(a["nvs.dev-existing-production"] != b["nvs.dev-existing-production"])' "$sandbox/docs-before" "$HC_DOCS"

# A worktree from before the dev profile is refused before anything runs.
for file in nvim/bin/envi nvim/lua/hcmux/session.lua; do
  legacy="$sandbox/legacy-$(basename "$file")"
  make_config "$legacy"
  git -C "$repo" show "0fc1e3f:$file" >"$legacy/$file"
  : >"$HC_LOG"
  : >"$PROBE_OUT"
  if ENVI_SESSION=legacy envi-dev "$legacy" --headless +qa 2>"$sandbox/err-legacy"; then
    bad "legacy $file: refused"
  else
    ok "legacy $file: refused"
  fi
  check "  ... before nvim or the core ran" test ! -s "$PROBE_OUT" -a ! -s "$HC_LOG"
  check "  ... telling the owner to rebase" has "$sandbox/err-legacy" "rebase it onto main"
done
if ENVI_DEV="$sandbox/legacy-session.lua" ENVI_SESSION=legacy envi --headless +qa 2>/dev/null; then
  bad "ENVI_DEV=<legacy> envi: refused (old hcmux.session)"
else ok "ENVI_DEV=<legacy> envi: refused (old hcmux.session)"; fi

# A dev profile folder that links into production is refused, never written through.
prod_state() { find "$XDG_STATE_HOME/nvim" -type f -exec cksum {} + 2>/dev/null | sort; }
alias_check() { # <name> <path to replace with a link> <link target>
  local before
  before="$(prod_state)"
  mv "$2" "$sandbox/aside"
  ln -s "$3" "$2"
  : >"$PROBE_OUT"
  if ENVI_SESSION=aliased envi-dev "$wt_a" --headless +qa 2>/dev/null; then bad "$1: refused"; else ok "$1: refused"; fi
  check "  ... before nvim ran" test ! -s "$PROBE_OUT"
  check "  ... production state untouched" test "$(prod_state)" = "$before"
  rm "$2"
  mv "$sandbox/aside" "$2"
}
ENVI_SESSION=aliased envi-dev "$wt_a" --headless +qa 2>/dev/null
alias_check "state folder linked to production state" "$XDG_STATE_HOME/$app_a" "$XDG_STATE_HOME/nvim"
mkdir -p "$XDG_STATE_HOME/$app_a/shada"
alias_check "a link inside the state folder" "$XDG_STATE_HOME/$app_a/shada" "$XDG_STATE_HOME/nvim/shada"
alias_check "envi-dev/ state parent linked to production" "$XDG_STATE_HOME/envi-dev" "$XDG_STATE_HOME/nvim"
mkdir -p "$sandbox/other-data"
alias_check "plugin link pointing anywhere but production data" "$XDG_DATA_HOME/$app_a" "$sandbox/other-data"
ENVI_SESSION=aliased envi-dev "$wt_a" --headless +qa 2>/dev/null
check "after the checks the dev profile runs again" test "$(field appname)" = "$app_a"

# `envi <file>` inside a dev nvim: production, no session (not the inherited one).
PATH="$sandbox/fake:$PATH" HCMUX_SESSION=dev-inherited NVIM_APPNAME="$app_a" envi notes.txt 2>/dev/null
check "envi <file> drops an inherited HCMUX_SESSION" test "$(tail -n 1 "$FAKE_LOG" | cut -d' ' -f1-2)" = "appname=<unset> session=<unset>"
PATH="$sandbox/fake:$PATH" HCMUX_SESSION=dev-inherited ENVI_SESSION=named envi notes.txt 2>/dev/null
check "  ... but ENVI_SESSION still picks one" test "$(tail -n 1 "$FAKE_LOG" | cut -d' ' -f2)" = "session=named"
PATH="$sandbox/fake:$PATH" HCMUX_SESSION=dev-inherited envi 2>/dev/null
check "  ... and envi with no arguments is still the dotfiles session" test "$(tail -n 1 "$FAKE_LOG" | cut -d' ' -f2)" = "session=dotfiles"

# ── stale profiles: removed by hand (Amendment 3) ──────────────────────

for cmd in ls list prune; do
  if envi-dev "$cmd" >"$sandbox/out" 2>&1; then bad "envi-dev $cmd: removed"; else ok "envi-dev $cmd: removed"; fi
  check "  ... pointing to the manual cleanup" has "$sandbox/out" "cleaned up by hand"
done
# The documented read-only listing (nvim/ENVI.md, "Cleanup") shows every profile path.
find "$XDG_CONFIG_HOME/envi-dev" "$XDG_DATA_HOME/envi-dev" "$XDG_STATE_HOME/envi-dev" "$XDG_CACHE_HOME/envi-dev" \
  -mindepth 1 -maxdepth 1 -exec ls -ld {} + >"$sandbox/listing" 2>/dev/null || :
check "the documented listing shows a profile's config link" has "$sandbox/listing" "$XDG_CONFIG_HOME/$app_a -> $wt_a/nvim"
check "  ... and its state folder" has "$sandbox/listing" "$XDG_STATE_HOME/$app_a"

# ── r2: XDG ancestor aliases, protocol values, odd slot names ───────────

# An XDG home that is itself a link into production: refused.
prod_before="$(prod_state)"
ln -s "$XDG_STATE_HOME/nvim" "$sandbox/aliased-state"
: >"$PROBE_OUT"
if XDG_STATE_HOME="$sandbox/aliased-state" ENVI_SESSION=x envi-dev "$wt_a" --headless +qa 2>/dev/null; then
  bad "a linked XDG_STATE_HOME: refused"
else ok "a linked XDG_STATE_HOME: refused"; fi
check "  ... before nvim ran" test ! -s "$PROBE_OUT"
check "  ... production state untouched" test "$(prod_state)" = "$prod_before"

# Only exactly one "envi-dev-protocol: 2" declaration counts.
for variant in "20" "2x" "02" "2 and more"; do
  proto="$sandbox/proto-$(printf '%s' "$variant" | tr -c 'a-z0-9' '-')"
  make_config "$proto"
  git -C "$repo" show "0fc1e3f:nvim/lua/hcmux/session.lua" >"$proto/nvim/lua/hcmux/session.lua"
  printf '\n-- envi-dev-protocol: %s\n' "$variant" >>"$proto/nvim/lua/hcmux/session.lua"
  : >"$HC_LOG"
  if ENVI_SESSION=dev-marker envi-dev "$proto" --headless +qa 2>/dev/null; then
    bad "protocol \"$variant\": refused"
  else ok "protocol \"$variant\": refused"; fi
  check "  ... before the core ran" test ! -s "$HC_LOG"
done
dup="$sandbox/proto-dup"
make_config "$dup"
printf '\n-- envi-dev-protocol: 2\n' >>"$dup/nvim/lua/hcmux/session.lua"
if ENVI_SESSION=x envi-dev "$dup" --headless +qa 2>/dev/null; then bad "two protocol declarations: refused"; else
  ok "two protocol declarations: refused"
fi
if ENVI_DEV="$dup" ENVI_SESSION=x envi --headless +qa 2>/dev/null; then bad "  ... also through ENVI_DEV=<path> envi"; else
  ok "  ... also through ENVI_DEV=<path> envi"
fi

# ── r3: worktree paths with control characters are refused ──────────────

slot_ok() { [[ "$1" =~ ^envi-dev/[a-z0-9-]{1,12}-[0-9a-f]{8}$ ]]; }
for name in "trailing"$'\n' "embedded"$'\n'"newline" "a"$'\t'"tab" "del"$'\x7f'"char"; do
  wt="$sandbox/cc-$name"
  make_config "$wt"
  label="$(printf '%q' "${wt##*/}")"
  before="$(find "$XDG_CONFIG_HOME/envi-dev" -mindepth 1 | wc -l)"
  : >"$PROBE_OUT"
  : >"$HC_LOG"
  if ENVI_SESSION=x envi-dev "$wt" --headless +qa 2>"$sandbox/err"; then bad "worktree $label: refused"; else
    ok "worktree $label: refused"
  fi
  check "  ... saying why" has "$sandbox/err" "control character"
  check "  ... before nvim, the core or a profile link" test ! -s "$PROBE_OUT" -a ! -s "$HC_LOG" -a "$(find "$XDG_CONFIG_HOME/envi-dev" -mindepth 1 | wc -l)" = "$before"
  if ENVI_DEV="$wt" ENVI_SESSION=x envi --headless +qa 2>/dev/null; then bad "  ... also through ENVI_DEV=<path> envi"; else
    ok "  ... also through ENVI_DEV=<path> envi"
  fi
done
# Ordinary unusual names keep working: spaces, capitals, symbols, non-ASCII.
odd="$sandbox/Odd Name With!Symbols café"
make_config "$odd"
: >"$PROBE_OUT"
ENVI_SESSION=odd envi-dev "$odd" --headless +qa 2>/dev/null || bad "odd folder name: launches"
odd_app="$(field appname)"
check "odd folder name: a valid slot ($odd_app)" slot_ok "$odd_app"
check "  ... its profile links to it" test "$(readlink -n "$XDG_CONFIG_HOME/$odd_app")" = "$odd/nvim"

finish
