#!/usr/bin/env bash
# The cutover (envi-migrate) in a sandbox: refusals before any write, dry run,
# apply, idempotent re-apply, rollback, a T3 client reading its session file
# throughout, and a SIGKILL after every single cp/mv of apply and of rollback,
# each followed by a recovery that must converge.
#   nvim/bin/test/migrate.sh
# shellcheck source=nvim/bin/test/sandbox.sh
. "$(dirname "$0")/sandbox.sh"

migrate() { "$repo/nvim/bin/envi-migrate" "$@"; }
put() { # <file> <content> [touch -t stamp]
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
  touch -t "${3:-202606010000}" "$1"
}
snapshot() { # every file and link under $1: content hash and mtime, or target
  (cd "$1" 2>/dev/null && find . \( -type f -o -type l \) -print0 | sort -z | while IFS= read -r -d '' f; do
    if [ -L "$f" ]; then
      printf '%s -> %s\n' "$f" "$(readlink -n "$f" | od -An -c | tr -s ' ')"
    else
      printf '%s %s %s\n' "$f" "$(cksum <"$f" | cut -d' ' -f1)" "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")"
    fi
  done)
}
links() {
  for l in "$XDG_CONFIG_HOME/nvim" "$XDG_CONFIG_HOME/envi" "$HOME/.local/bin/envi" "$HOME/.local/bin/envi-dev"; do
    printf '%s -> %s\n' "${l#"$HOME"}" "$(readlink -n "$l" 2>/dev/null || echo ABSENT)"
  done
}
world_state() { printf '%s\n--\n%s\n--\n%s\n' "$(snapshot "$XDG_STATE_HOME/nvim")" "$(snapshot "$XDG_STATE_HOME/envi")" "$(links)"; }
no_staging() { ! find "$XDG_STATE_HOME" -maxdepth 1 -name 'nvim.envi-migrate.*' | grep -q .; }

# A world: a fresh HOME with today's layout (envi from slot 2, its own state).
world() { # <name>
  export HOME="$sandbox/$1"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  local e="$XDG_STATE_HOME/envi" n="$XDG_STATE_HOME/nvim"
  mkdir -p "$HOME/.dotfiles/nvim/bin" "$sandbox/slot2-$1/nvim/bin" "$XDG_CONFIG_HOME" "$HOME/.local/bin"
  cp "$repo/nvim/bin/envi" "$repo/nvim/bin/envi-dev" "$HOME/.dotfiles/nvim/bin/"
  : >"$HOME/.dotfiles/nvim/init.lua"
  ln -s "$HOME/.dotfiles/nvim" "$XDG_CONFIG_HOME/nvim"
  ln -s "$sandbox/slot2-$1/nvim" "$XDG_CONFIG_HOME/envi"
  ln -s "$XDG_CONFIG_HOME/envi/bin/envi" "$HOME/.local/bin/envi"
  put "$e/shada/main.shada" "envi shada" 202611010000
  put "$e/shada/main.shada.tmp.a" "torn"
  put "$e/undo/%only%envi" "u1"
  put "$e/undo/%both" "envi's"
  put "$e/undo/line"$'\n'"break" "odd"
  put "$e/hcmux/t3-layout.log" "envi log"
  put "$e/envi-hotreload.dotfiles" "abc1234"
  put "$e/swap/%x.swp" "envi swap"
  put "$e/e2e/run.log" "leftover"
  put "$e/t3-session.json" '{"token":"fixture","expiresAt":"2099-01-01T00:00:00Z"}'
  chmod 600 "$e/t3-session.json"
  put "$n/shada/main.shada" "nvim shada" 202601010000
  put "$n/undo/%both" "nvim's"
  put "$n/undo/%only%nvim" "u2"
  put "$n/swap/%y.swp" "nvim swap"
  put "$n/lsp.log" "nvim log"
  put "$n/hcmux/t3-layout.log" "nvim layout log"
}

# ── refusals: each before any write ──────────────────────────────────────

refused() { # <name> <args...>: refused, and nothing changed (no backup either)
  local name="$1" before
  shift
  before="$(world_state)"
  if migrate "$@" >"$sandbox/out" 2>&1; then bad "$name: refused"; else ok "$name: refused"; fi
  check "  ... nothing changed" test "$(world_state)" = "$before"
  check "  ... no backup made" test ! -e "$HOME/.backups"
}
world refusals
printf '#!/bin/sh\necho 4242\n' >"$sandbox/bin/pgrep"
refused "any nvim running (plain, envi or dev)" cutover
check "  ... naming it" has "$sandbox/out" "pid 4242"
printf '#!/bin/sh\nexit 1\n' >"$sandbox/bin/pgrep"
mv "$HOME/.local/bin/envi" "$sandbox/aside" && put "$HOME/.local/bin/envi" "a real launcher"
refused "a real file where a link goes" cutover
rm "$HOME/.local/bin/envi" && mv "$sandbox/aside" "$HOME/.local/bin/envi"
mv "$HOME/.dotfiles/nvim/bin/envi-dev" "$sandbox/aside"
refused "no production launcher in ~/.dotfiles" cutover
mv "$sandbox/aside" "$HOME/.dotfiles/nvim/bin/envi-dev"
for p in nvim/hcmux envi/undo nvim; do
  mv "$XDG_STATE_HOME/$p" "$sandbox/aside"
  ln -s "$XDG_STATE_HOME/envi/swap" "$XDG_STATE_HOME/$p"
  refused "state/$p is a link" cutover
  rm "$XDG_STATE_HOME/$p" && mv "$sandbox/aside" "$XDG_STATE_HOME/$p"
done
mv "$XDG_STATE_HOME" "$HOME/.local/real-state" && ln -s real-state "$XDG_STATE_HOME"
refused "a linked ancestor of the state folders" state
rm "$XDG_STATE_HOME" && mv "$HOME/.local/real-state" "$XDG_STATE_HOME"
rm -rf "$XDG_STATE_HOME/envi/swap"
migrate state >"$sandbox/out" 2>&1
check "no envi swap folder: zero swap files, not an error" test -f "$XDG_STATE_HOME/nvim/undo/%only%envi"

# ── the cutover, end to end ──────────────────────────────────────────────

world main
make_config "$HOME/.dotfiles.git-tmp" && rm -rf "$HOME/.dotfiles" && mv "$HOME/.dotfiles.git-tmp" "$HOME/.dotfiles"
git -C "$HOME/.dotfiles" init -q
git -C "$HOME/.dotfiles" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$HOME/.dotfiles" -c user.name=t -c user.email=t@example.invalid commit -qm base
echo "-- the owner's local edit" >>"$HOME/.dotfiles/nvim/init.lua"
for f in envi nvim; do # real ShaDa files: an nvim runs on them after the cutover
  rm "$XDG_STATE_HOME/$f/shada/main.shada"
  nvim -u NONE -i "$XDG_STATE_HOME/$f/shada/main.shada" --headless +"call setreg('a', '$f shada')" +qa
done
touch -t 202611010000 "$XDG_STATE_HOME/envi/shada/main.shada"
envi="$XDG_STATE_HOME/envi"
nvim="$XDG_STATE_HOME/nvim"
before="$(world_state)"
nvim_before="$(snapshot "$nvim")"
envi_before="$(snapshot "$envi")"
links_before="$(links)"
t3_before="$(ls -li "$envi/t3-session.json")"

# A running T3 client: reads the session file exactly where t3.mjs does
# (HOME/.local/state/envi/t3-session.json, whatever the nvim profile) every
# 10 ms through the whole cutover and rollback, and logs any failed read.
grep -q 'const SESSION = path.join(os.homedir(), ".local/state/envi/t3-session.json")' \
  "$repo/nvim/tools/t3-thread/t3.mjs" || bad "t3.mjs still reads ~/.local/state/envi/t3-session.json"
export T3_READS="$sandbox/t3-reads.log" T3_STOP="$sandbox/t3-stop"
# shellcheck disable=SC2016 # JavaScript, not shell
env -u NVIM_APPNAME node -e '
  const fs = require("fs"), os = require("os"), path = require("path");
  const SESSION = path.join(os.homedir(), ".local/state/envi/t3-session.json");
  let n = 0, bad = 0;
  const t = setInterval(() => {
    try { if (JSON.parse(fs.readFileSync(SESSION, "utf8")).token !== "fixture") bad++; } catch { bad++; }
    n++;
    if (fs.existsSync(process.env.T3_STOP) || n > 6000) { // stop after a minute at most
      clearInterval(t);
      fs.writeFileSync(process.env.T3_READS, `${n} ${bad}\n`);
    }
  }, 10);
' >/dev/null 2>&1 &
t3_pid=$!
trap 'kill "$t3_pid" 2>/dev/null || true; rm -rf "$sandbox" 2>/dev/null || true' EXIT

migrate --dry-run cutover >"$sandbox/dry" 2>&1
check "dry run: plans the state swap" has "$sandbox/dry" "would build $XDG_STATE_HOME/nvim.envi-migrate."
check "dry run: plans the links" has "$sandbox/dry" "would link $HOME/.local/bin/envi -> $HOME/.dotfiles/nvim/bin/envi"
check "dry run: plans removing ~/.config/envi" has "$sandbox/dry" "would remove $XDG_CONFIG_HOME/envi"
check "dry run: lists local edits in ~/.dotfiles/nvim" has "$sandbox/dry" "M nvim/init.lua"
check "dry run: writes nothing" test "$(world_state)" = "$before" -a ! -e "$HOME/.backups"

migrate cutover >"$sandbox/apply" 2>&1
backup="$(sed -n 's/^backup: //p' "$sandbox/apply")"
check "apply: one backup under ~/.backups, private" test -d "$backup" -a "$(stat -f %Lp "$backup" 2>/dev/null || stat -c %a "$backup")" = 700
check "apply: marked APPLIED" test -f "$backup/APPLIED"
check "apply: the old nvim state is in the backup, exactly" test "$(snapshot "$backup/state-nvim")" = "$nvim_before"
check "apply: envi's newer shada" cmp -s "$envi/shada/main.shada" "$nvim/shada/main.shada"
check "apply: envi wins a name collision" cmp -s "$envi/undo/%both" "$nvim/undo/%both"
check "apply: nvim-only files kept" has "$nvim/undo/%only%nvim" u2
check "apply: odd names copied" cmp -s "$envi/undo/line"$'\n'"break" "$nvim/undo/line"$'\n'"break"
check "apply: hcmux/ and the hot-reload marker" test -f "$nvim/hcmux/t3-layout.log" -a -f "$nvim/envi-hotreload.dotfiles"
check "apply: mtime kept" test "$(stat -f %m "$nvim/undo/%only%envi" 2>/dev/null || stat -c %Y "$nvim/undo/%only%envi")" = \
  "$(stat -f %m "$envi/undo/%only%envi" 2>/dev/null || stat -c %Y "$envi/undo/%only%envi")"
check "apply: shada temp files and envi swap files skipped" test ! -e "$nvim/shada/main.shada.tmp.a" -a ! -e "$nvim/swap/%x.swp"
check "apply: nvim's own swap file kept" test -f "$nvim/swap/%y.swp"
check "apply: T3 session file and leftovers stay in envi" test ! -e "$nvim/t3-session.json" -a ! -e "$nvim/e2e"
check "apply: envi state unchanged, file for file" test "$(snapshot "$envi")" = "$envi_before"
check "apply: the T3 session file: same inode, mode, size and mtime" test "$(ls -li "$envi/t3-session.json")" = "$t3_before"
check "apply: links" test "$(readlink "$XDG_CONFIG_HOME/nvim"):$(readlink "$HOME/.local/bin/envi"):$(readlink "$HOME/.local/bin/envi-dev")" = \
  "$HOME/.dotfiles/nvim:$HOME/.dotfiles/nvim/bin/envi:$HOME/.dotfiles/nvim/bin/envi-dev"
check "apply: ~/.config/envi is gone" test ! -e "$XDG_CONFIG_HOME/envi" -a ! -L "$XDG_CONFIG_HOME/envi"
check "apply: no staging left" no_staging
check "apply: the owner's edit in ~/.dotfiles untouched" has "$HOME/.dotfiles/nvim/init.lua" "the owner's local edit"
after="$(world_state)"

migrate cutover >"$sandbox/again" 2>&1
check "re-apply: nothing to change" has "$sandbox/again" "^nothing to change$"
check "re-apply: no second backup" test "$(find "$HOME/.backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1
check "re-apply: state and links as after the first" test "$(world_state)" = "$after"

echo "edited after the cutover" >>"$nvim/undo/%only%envi"
post="$(snapshot "$nvim")"
migrate --dry-run rollback >"$sandbox/rb-dry" 2>&1
check "rollback dry run: changes nothing" test "$(snapshot "$nvim")" = "$post" -a ! -e "$backup/ROLLED_BACK"
migrate rollback >"$sandbox/rb" 2>&1
check "rollback: nvim state exactly as before, mtimes included" test "$(snapshot "$nvim")" = "$nvim_before"
check "rollback: links exactly as before" test "$(links)" = "$links_before"
check "rollback: the post-cutover state kept, untouched" test "$(snapshot "$backup/rollback-displaced/nvim")" = "$post"
check "rollback: envi state still unchanged" test "$(snapshot "$envi")" = "$envi_before"
check "rollback: marked ROLLED_BACK" test -f "$backup/ROLLED_BACK"
migrate rollback >"$sandbox/rb2" 2>&1
check "rollback again: nothing to roll back, nothing changed" test "$(snapshot "$nvim"):$(links)" = "$nvim_before:$links_before"

# A link path that holds real content blocks rollback, which stays retryable.
migrate cutover >/dev/null 2>&1
backup2="$(migrate backups | sed -n 's/^applied //p')"
rm "$XDG_CONFIG_HOME/nvim" && put "$XDG_CONFIG_HOME/nvim/owner" "keep"
if migrate rollback >"$sandbox/blocked" 2>&1; then bad "rollback blocked by a real folder: fails"; else ok "rollback blocked by a real folder: fails"; fi
check "  ... leaves the folder and the state alone" test -f "$XDG_CONFIG_HOME/nvim/owner" -a -f "$backup2/state-nvim/lsp.log"
check "  ... not marked done" test ! -e "$backup2/ROLLED_BACK"
mv "$XDG_CONFIG_HOME/nvim" "$sandbox/owner-aside"
migrate rollback >/dev/null 2>&1
check "  ... and after moving it aside, the retry restores everything" test "$(snapshot "$nvim"):$(links)" = "$nvim_before:$links_before"

# After the cutover: envi on PATH is production, on the dotfiles session; :reload works.
migrate cutover >/dev/null 2>&1
: >"$PROBE_OUT"
: >"$HC_LOG"
(cd "$sandbox" && PROBE_RELOAD_ONCE="$sandbox/reload-once" ENVI_SESSION=dotfiles PATH="$HOME/.local/bin:$PATH" \
  envi --headless >"$sandbox/post" 2>&1) || bad "after cutover: envi exited $?"
check "after cutover: envi runs the default profile from ~/.dotfiles" has "$PROBE_OUT" \
  "^appname= config=$HOME/.dotfiles/nvim state=$nvim session=dotfiles reloadable=true "
check "after cutover: :reload comes back on the dotfiles session" test "$(grep -c "session=dotfiles reloadable=true" "$PROBE_OUT")" = 2
check "after cutover: envi attaches the dotfiles session" has "$HC_LOG" "^doc.set nvs.dotfiles$"

touch "$T3_STOP"
wait "$t3_pid"
read -r reads failed <"$T3_READS"
check "T3 client: read the session file throughout ($reads reads)" test "$reads" -gt 10
check "T3 client: every read succeeded with the same token" test "$failed" = 0
check "T3 session file: same inode, mode, size and mtime at the end" test "$(ls -li "$envi/t3-session.json")" = "$t3_before"

# ── SIGKILL after every cp and mv ────────────────────────────────────────

# Shims count each call, run the real tool, then kill the migration after call
# number $SHIM_KILL_AT of $SHIM_KILL_TOOL.
mkdir -p "$sandbox/shim"
for tool in cp mv; do
  cat >"$sandbox/shim/$tool" <<EOF
#!/bin/sh
n=\$((\$(cat "\$SHIM_COUNT.$tool" 2>/dev/null || echo 0) + 1))
echo "\$n" >"\$SHIM_COUNT.$tool"
"$(command -v "$tool")" "\$@"
rc=\$?
if [ "\${SHIM_KILL_TOOL:-}" = $tool ] && [ "\$n" = "\${SHIM_KILL_AT:-0}" ]; then kill -KILL "\$PPID"; fi
exit \$rc
EOF
  chmod +x "$sandbox/shim/$tool"
done
shimmed() { # <tool> <n> <args...>: exit status of a migration killed after that call
  local tool="$1" at="$2" rc=0
  shift 2
  rm -f "$sandbox/count".*
  SHIM_COUNT="$sandbox/count" SHIM_KILL_TOOL="$tool" SHIM_KILL_AT="$at" PATH="$sandbox/shim:$PATH" migrate "$@" \
    >"$sandbox/out" 2>&1 || rc=$?
  return "$rc"
}
calls() { cat "$sandbox/count.$1" 2>/dev/null || echo 0; }

world reference
pre="$(world_state)"
shimmed none 0 cutover
apply_calls_cp="$(calls cp)" apply_calls_mv="$(calls mv)"
ref_after="$(world_state | sed "s|$HOME|<home>|g")"
shimmed none 0 rollback
rollback_calls_mv="$(calls mv)"
check "reference: apply makes cp and mv calls to interrupt" test "$apply_calls_cp" -gt 1 -a "$apply_calls_mv" -gt 2
check "reference: rollback restores" test "$(world_state)" = "$pre"

for tool in cp mv; do
  total="$apply_calls_mv"
  [ "$tool" = cp ] && total="$apply_calls_cp"
  for at in $(seq 1 "$total"); do
    name="apply killed after $tool #$at"
    world "kill-$tool-$at"
    pre="$(world_state)"
    rc=0
    shimmed "$tool" "$at" cutover || rc=$?
    check "$name: really killed" test "$rc" = 137
    if migrate cutover >/dev/null 2>&1; then bad "$name: a new apply refuses"; else ok "$name: a new apply refuses"; fi
    migrate rollback >"$sandbox/out" 2>&1 || bad "$name: rollback exits 0"
    check "$name: rollback restores state and links exactly" test "$(world_state)" = "$pre"
    check "$name: no staging left" no_staging
    migrate cutover >/dev/null 2>&1 || bad "$name: a new apply runs"
    check "$name: and then gives the same result as an uninterrupted one" \
      test "$(world_state | sed "s|$HOME|<home>|g")" = "$ref_after"
  done
done

for at in $(seq 1 "$rollback_calls_mv"); do
  name="rollback killed after mv #$at"
  world "rbkill-$at"
  pre="$(world_state)"
  migrate cutover >/dev/null 2>&1
  echo "edited after the cutover" >>"$XDG_STATE_HOME/nvim/undo/%only%envi"
  post="$(snapshot "$XDG_STATE_HOME/nvim")"
  rc=0
  shimmed mv "$at" rollback || rc=$?
  check "$name: really killed" test "$rc" = 137
  b="$(migrate backups | cut -d' ' -f2-)"
  check "$name: not marked done" test ! -e "$b/ROLLED_BACK"
  migrate rollback >"$sandbox/out" 2>&1 || bad "$name: the retry exits 0"
  check "$name: the retry restores state and links exactly" test "$(world_state)" = "$pre"
  check "$name: the post-cutover state is kept once, untouched" \
    test "$(snapshot "$b/rollback-displaced/nvim")" = "$post" -a ! -e "$b/rollback-displaced/nvim.2"
  check "$name: marked done" test -f "$b/ROLLED_BACK"
done

finish
