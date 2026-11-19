#!/usr/bin/env bash
# The cutover (envi-migrate) in a sandbox: dry run, apply, idempotent
# re-apply, rollback, and a T3 client reading its session file throughout.
#   nvim/bin/test/migrate.sh
# shellcheck source=nvim/bin/test/sandbox.sh
. "$(dirname "$0")/sandbox.sh"

envi="$XDG_STATE_HOME/envi"
nvim="$XDG_STATE_HOME/nvim"
migrate() { "$HOME/.dotfiles/nvim/bin/envi-migrate" "$@"; }

# ── today's layout ───────────────────────────────────────────────────────
make_config "$HOME/.dotfiles"
git -C "$HOME/.dotfiles" init -q
git -C "$HOME/.dotfiles" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$HOME/.dotfiles" -c user.name=t -c user.email=t@example.invalid commit -qm base
echo "-- the owner's local edit" >>"$HOME/.dotfiles/nvim/init.lua"
slot2="$sandbox/slot2/.dotfiles"
make_config "$slot2"
mkdir -p "$XDG_CONFIG_HOME" "$HOME/.local/bin"
ln -s "$HOME/.dotfiles/nvim" "$XDG_CONFIG_HOME/nvim"
ln -s "$slot2/nvim" "$XDG_CONFIG_HOME/envi"
ln -s "$XDG_CONFIG_HOME/envi/bin/envi" "$HOME/.local/bin/envi"

put() { # <file> <content> <touch -t stamp>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
  touch -t "$3" "$1"
}
old=202601010000 mid=202606010000 new=202611010000
shada() { # <file> <register a> <touch -t stamp>: a real ShaDa file
  mkdir -p "$(dirname "$1")"
  nvim -u NONE -i "$1" --headless +"call setreg('a', '$2')" +qa
  touch -t "$3" "$1"
}
shada "$envi/shada/main.shada" "envi shada" "$new"
shada "$nvim/shada/main.shada" "nvim shada" "$old"
put "$envi/shada/main.shada.tmp.a" "torn" "$new"
put "$envi/undo/%only%envi" "u1" "$mid"
put "$envi/undo/%same" "same" "$mid"
put "$nvim/undo/%same" "same" "$old"
put "$envi/undo/%envi%newer" "envi wins" "$new"
put "$nvim/undo/%envi%newer" "nvim loses" "$old"
put "$envi/undo/%nvim%newer" "envi loses" "$old"
put "$nvim/undo/%nvim%newer" "nvim wins" "$new"
put "$envi/undo/%with [brackets] *" "glob" "$mid"
put "$envi/hcmux/t3-layout.log" "envi log" "$new"
put "$nvim/hcmux/t3-layout.log" "nvim log" "$old"
put "$envi/envi-hotreload.dotfiles" "abc1234" "$mid"
put "$envi/swap/%x.swp" "swap" "$mid"
put "$envi/e2e/run.log" "leftover" "$mid"
put "$envi/charters/c.md" "leftover" "$mid"
put "$envi/t3-session.json" '{"token":"fixture","expiresAt":"2099-01-01T00:00:00Z"}' "$mid"
chmod 600 "$envi/t3-session.json"
put "$nvim/swap/%y.swp" "nvim swap" "$mid"

snapshot() { # every file under $1 with its content hash and mtime; links with targets
  (cd "$1" 2>/dev/null && find . \( -type f -o -type l \) -print0 | sort -z | while IFS= read -r -d '' f; do
    if [ -L "$f" ]; then
      printf '%s -> %s\n' "$f" "$(readlink "$f")"
    else
      printf '%s %s %s\n' "$f" "$(cksum <"$f" | cut -d' ' -f1)" "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")"
    fi
  done)
}
links() {
  for l in "$XDG_CONFIG_HOME/nvim" "$XDG_CONFIG_HOME/envi" "$HOME/.local/bin/envi" "$HOME/.local/bin/envi-dev"; do
    printf '%s -> %s\n' "$l" "$(readlink "$l" 2>/dev/null || echo ABSENT)"
  done
}
envi_before="$(snapshot "$envi")"
nvim_before="$(snapshot "$nvim")"
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
trap 'kill "$t3_pid" 2>/dev/null || true; rm -rf "$sandbox"' EXIT

# ── dry run ──────────────────────────────────────────────────────────────
migrate --dry-run cutover >"$sandbox/dry" 2>&1
check "dry run: plans the new file" has "$sandbox/dry" "would create undo/%only%envi"
check "dry run: plans envi's newer file" has "$sandbox/dry" "would replace undo/%envi%newer"
check "dry run: plans keeping nvim's newer file" has "$sandbox/dry" "would keep undo/%nvim%newer"
check "dry run: plans the hot-reload marker" has "$sandbox/dry" "would create envi-hotreload.dotfiles"
check "dry run: plans the links" has "$sandbox/dry" "would link $HOME/.local/bin/envi -> $HOME/.dotfiles/nvim/bin/envi"
check "dry run: plans removing ~/.config/envi" has "$sandbox/dry" "would remove $XDG_CONFIG_HOME/envi"
check "dry run: lists local edits in ~/.dotfiles/nvim" has "$sandbox/dry" "M nvim/init.lua"
check "dry run: writes nothing (nvim state)" test "$(snapshot "$nvim")" = "$nvim_before"
check "dry run: writes nothing (links)" test "$(links)" = "$links_before"
check "dry run: makes no backup" test ! -e "$HOME/.backups"

# ── refused while envi runs ──────────────────────────────────────────────
printf '#!/bin/sh\necho 4242\n' >"$sandbox/bin/pgrep"
if migrate cutover >"$sandbox/busy" 2>&1; then bad "apply refused while envi runs"; else ok "apply refused while envi runs"; fi
check "  ... naming the pid" has "$sandbox/busy" "pid 4242"
check "  ... changing nothing" test "$(snapshot "$nvim"):$(links)" = "$nvim_before:$links_before"
printf '#!/bin/sh\nexit 1\n' >"$sandbox/bin/pgrep"

# ── links refused until the launcher is in ~/.dotfiles ───────────────────
mv "$HOME/.dotfiles/nvim/bin/envi-dev" "$sandbox/envi-dev.aside"
if migrate links >"$sandbox/nolauncher" 2>&1; then bad "links refused without the production launcher"; else
  ok "links refused without the production launcher"
fi
check "  ... changing nothing" test "$(links)" = "$links_before"
mv "$sandbox/envi-dev.aside" "$HOME/.dotfiles/nvim/bin/envi-dev"

# ── apply ────────────────────────────────────────────────────────────────
migrate cutover >"$sandbox/apply" 2>&1
backup="$(sed -n 's/^backup: //p' "$sandbox/apply")"
check "apply: one timestamped backup under ~/.backups" test -d "$backup" -a "${backup#"$HOME/.backups/envi-migrate-"}" != "$backup"
check "apply: backup is private" test "$(stat -f %Lp "$backup" 2>/dev/null || stat -c %a "$backup")" = 700
check "apply: new file copied" cmp -s "$envi/undo/%only%envi" "$nvim/undo/%only%envi"
check "apply: a name with glob characters copied" cmp -s "$envi/undo/%with [brackets] *" "$nvim/undo/%with [brackets] *"
check "apply: newer envi shada wins" cmp -s "$envi/shada/main.shada" "$nvim/shada/main.shada"
check "apply: the losing nvim shada is in the backup" has "$backup/displaced/nvim/shada/main.shada" "nvim shada"
check "apply: and the winning one is envi's" has "$nvim/shada/main.shada" "envi shada"
check "apply: newer envi undo wins" cmp -s "$envi/undo/%envi%newer" "$nvim/undo/%envi%newer"
check "apply: the losing nvim undo is in the backup" has "$backup/displaced/nvim/undo/%envi%newer" "nvim loses"
check "apply: newer nvim undo kept" has "$nvim/undo/%nvim%newer" "nvim wins"
check "apply: the losing envi undo is in the backup" has "$backup/losers/envi/undo/%nvim%newer" "envi loses"
check "apply: mtime kept on copies" test "$(stat -f %m "$nvim/undo/%only%envi" 2>/dev/null || stat -c %Y "$nvim/undo/%only%envi")" = \
  "$(stat -f %m "$envi/undo/%only%envi" 2>/dev/null || stat -c %Y "$envi/undo/%only%envi")"
check "apply: hcmux/ brought over" cmp -s "$envi/hcmux/t3-layout.log" "$nvim/hcmux/t3-layout.log"
check "apply: hot-reload marker brought over" cmp -s "$envi/envi-hotreload.dotfiles" "$nvim/envi-hotreload.dotfiles"
check "apply: shada temp files skipped" test ! -e "$nvim/shada/main.shada.tmp.a"
check "apply: swap files never touched" test ! -e "$nvim/swap/%x.swp" -a -f "$nvim/swap/%y.swp"
check "apply: dev leftovers stay in envi" test ! -e "$nvim/e2e" -a ! -e "$nvim/charters"
check "apply: the T3 session file is not copied" test ! -e "$nvim/t3-session.json"
check "apply: envi state is unchanged, file for file" test "$(snapshot "$envi")" = "$envi_before"
check "apply: the T3 session file: same inode, mode, size and mtime" test "$(ls -li "$envi/t3-session.json")" = "$t3_before"
check "apply: ~/.config/nvim -> ~/.dotfiles/nvim" test "$(readlink "$XDG_CONFIG_HOME/nvim")" = "$HOME/.dotfiles/nvim"
check "apply: ~/.local/bin/envi -> ~/.dotfiles" test "$(readlink "$HOME/.local/bin/envi")" = "$HOME/.dotfiles/nvim/bin/envi"
check "apply: ~/.local/bin/envi-dev -> ~/.dotfiles" test "$(readlink "$HOME/.local/bin/envi-dev")" = "$HOME/.dotfiles/nvim/bin/envi-dev"
check "apply: ~/.config/envi is gone" test ! -e "$XDG_CONFIG_HOME/envi" -a ! -L "$XDG_CONFIG_HOME/envi"
check "apply: the owner's edit in ~/.dotfiles untouched" has "$HOME/.dotfiles/nvim/init.lua" "the owner's local edit"
nvim_after="$(snapshot "$nvim")"
links_after="$(links)"

# ── idempotent ───────────────────────────────────────────────────────────
migrate cutover >"$sandbox/again" 2>&1
check "re-apply: nothing to change" has "$sandbox/again" "^nothing to change$"
check "re-apply: no second backup" test "$(find "$HOME/.backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1
check "re-apply: state and links as after the first" test "$(snapshot "$nvim"):$(links)" = "$nvim_after:$links_after"

# ── rollback ─────────────────────────────────────────────────────────────
migrate --dry-run rollback >"$sandbox/rb-dry" 2>&1
check "rollback dry run: plans the restore" has "$sandbox/rb-dry" "would restore shada/main.shada"
check "rollback dry run: changes nothing" test "$(snapshot "$nvim"):$(links)" = "$nvim_after:$links_after"
migrate rollback >"$sandbox/rb" 2>&1
check "rollback: nvim state exactly as before, mtimes included" test "$(snapshot "$nvim")" = "$nvim_before"
check "rollback: links exactly as before" test "$(links)" = "$links_before"
check "rollback: envi state still unchanged" test "$(snapshot "$envi")" = "$envi_before"
check "rollback: marked done" test -f "$backup/ROLLED_BACK"
migrate rollback >"$sandbox/rb2" 2>&1
check "rollback again: nothing to roll back" has "$sandbox/rb2" "no backup to roll back"
check "rollback again: still as before" test "$(snapshot "$nvim"):$(links)" = "$nvim_before:$links_before"

# A change made after the cutover is set aside on rollback, never deleted.
migrate cutover >/dev/null 2>&1
echo "edited after cutover" >>"$nvim/undo/%only%envi"
migrate rollback >"$sandbox/rb3" 2>&1
backup2="$(find "$HOME/.backups" -mindepth 1 -maxdepth 1 -newer "$backup" -type d | head -n 1)"
check "rollback keeps a post-cutover edit aside" has "$backup2/rollback-displaced/nvim/undo/%only%envi" "edited after cutover"
check "  ... and still restores the rest" test "$(links)" = "$links_before"

# ── after the cutover ────────────────────────────────────────────────────
# envi on PATH is production, on the dotfiles session; :reload still works.
migrate cutover >/dev/null 2>&1
: >"$PROBE_OUT"
: >"$HC_LOG"
(cd "$sandbox" && PROBE_RELOAD_ONCE="$sandbox/reload-once" ENVI_SESSION=dotfiles PATH="$HOME/.local/bin:$PATH" \
  envi --headless >"$sandbox/post" 2>&1) || bad "after cutover: envi exited $?"
check "after cutover: envi runs the default profile from ~/.dotfiles" has "$PROBE_OUT" \
  "^appname= config=$HOME/.dotfiles/nvim state=$nvim session=dotfiles reloadable=true "
check "after cutover: :reload comes back on the dotfiles session" test "$(grep -c "session=dotfiles reloadable=true" "$PROBE_OUT")" = 2
check "after cutover: envi attaches the dotfiles session" has "$HC_LOG" "^doc.set nvs.dotfiles$"

# ── the T3 client never noticed ──────────────────────────────────────────
touch "$T3_STOP"
wait "$t3_pid"
read -r reads failed <"$T3_READS"
check "T3 client: read the session file throughout ($reads reads)" test "$reads" -gt 10
check "T3 client: every read succeeded with the same token" test "$failed" = 0
check "T3 session file: same inode, mode, size and mtime at the end" test "$(ls -li "$envi/t3-session.json")" = "$t3_before"

finish
