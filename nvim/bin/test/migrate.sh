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
open_backups() { # backups not rolled back (envi-migrate has no listing command)
  local b
  for b in "$HOME/.backups"/envi-migrate-*; do
    [[ "${b##*/}" =~ ^envi-migrate-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]] && [ ! -e "$b/ROLLED_BACK" ] && printf '%s\n' "$b"
  done
  return 0
}

# A world: a fresh HOME with today's layout (envi from slot 2, its own state).
world() { # <name>
  export HOME="$sandbox/$1"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  local e="$XDG_STATE_HOME/envi" n="$XDG_STATE_HOME/nvim"
  mkdir -p "$HOME/.dotfiles/nvim/bin" "$sandbox/slot2-$1/nvim/bin" "$XDG_CONFIG_HOME" "$HOME/.local/bin"
  cp "$repo/nvim/bin/envi" "$repo/nvim/bin/envi-dev" "$repo/nvim/bin/envi-guard.sh" "$repo/nvim/bin/nvim-session" \
    "$HOME/.dotfiles/nvim/bin/"
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

refused() { # <name> <args...>: refused, and nothing changed (no new backup either)
  local name="$1" before backups
  shift
  before="$(world_state)"
  backups="$(ls "$HOME/.backups" 2>/dev/null || true)"
  if migrate "$@" >"$sandbox/out" 2>&1; then bad "$name: refused"; else ok "$name: refused"; fi
  check "  ... nothing changed" test "$(world_state)" = "$before"
  check "  ... no backup made" test "$(ls "$HOME/.backups" 2>/dev/null || true)" = "$backups"
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
trap 'kill "$t3_pid" 2>/dev/null || true; rm -rf "$sandbox"' EXIT

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
backup2="$(open_backups)"
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

# ── failing helpers and odd inputs (r2) ─────────────────────────────────

# fail_tool <tool> <case pattern on its last (or, for find, first) argument>:
# a shim that fails exactly those calls and runs the real tool otherwise.
fail_tool() {
  mkdir -p "$sandbox/fail"
  cat >"$sandbox/fail/$1" <<EOF
#!/bin/sh
for a do last="\$a"; done
probe="\$last"
[ "$1" = find ] && probe="\$1"
case "\$probe" in $2) echo "fixture: $1 failed" >&2; exit 1 ;; esac
exec "$(command -v "$1")" "\$@"
EOF
  chmod +x "$sandbox/fail/$1"
}
with_fail() { PATH="$sandbox/fail:$PATH" migrate "$@"; }
clear_fail() { rm -rf "$sandbox/fail"; }
no_temp_links() { ! find "$XDG_CONFIG_HOME" "$HOME/.local/bin" -maxdepth 1 -name '.envi-migrate-link.*' 2>/dev/null | grep -q .; }

world faults
pre="$(world_state)"
fail_tool mv "\"$HOME/.local/bin/envi\""
if with_fail cutover >"$sandbox/out" 2>&1; then bad "a failed link rename fails apply"; else ok "a failed link rename fails apply"; fi
check "  ... with the helper's own message" has "$sandbox/out" "fixture: mv failed"
check "  ... and no APPLIED" test -z "$(find "$HOME/.backups" -name APPLIED)"
clear_fail
migrate rollback >/dev/null 2>&1 || bad "  ... rollback after it exits 0"
check "  ... which restores everything" test "$(world_state)" = "$pre"
check "  ... and leaves no temporary link" no_temp_links
migrate cutover >/dev/null 2>&1
fail_tool mv "\"$HOME/.local/bin/envi\""
if with_fail rollback >"$sandbox/out" 2>&1; then bad "a failed link rename fails rollback"; else ok "a failed link rename fails rollback"; fi
check "  ... and no ROLLED_BACK (only the earlier backup has one)" \
  test "$(find "$HOME/.backups" -name ROLLED_BACK | wc -l | tr -d ' ')" = 1
clear_fail
migrate rollback >/dev/null 2>&1 || bad "  ... the retry exits 0"
check "  ... and restores everything" test "$(world_state)" = "$pre"

world faults2
pre="$(world_state)"
fail_tool find "\"$XDG_STATE_HOME/envi/undo\""
if with_fail cutover >"$sandbox/out" 2>&1; then bad "a failed source walk fails apply"; else ok "a failed source walk fails apply"; fi
check "  ... before any change to state or links" test "$(world_state)" = "$pre"
check "  ... and no APPLIED" test -z "$(find "$HOME/.backups" -name APPLIED)"
clear_fail
migrate rollback >/dev/null 2>&1 || bad "  ... rollback exits 0"
check "  ... and leaves no staging" no_staging
pre="$(world_state)"
fail_tool stat "*"
if with_fail cutover >"$sandbox/out" 2>&1; then bad "stat failing (no device id): refused"; else ok "stat failing (no device id): refused"; fi
check "  ... nothing changed" test "$(world_state)" = "$pre"
clear_fail
printf '#!/bin/sh\nexit 2\n' >"$sandbox/bin/pgrep"
refused "a process query error (pgrep exit 2)" cutover
printf '#!/bin/sh\nexit 1\n' >"$sandbox/bin/pgrep"
chmod 644 "$HOME/.dotfiles/nvim/bin/envi"
refused "a production launcher that is not executable" cutover
chmod 755 "$HOME/.dotfiles/nvim/bin/envi"
chmod 644 "$HOME/.dotfiles/nvim/bin/nvim-session"
refused "a session helper (nvim-session) that is not executable" cutover
chmod 755 "$HOME/.dotfiles/nvim/bin/nvim-session"
rm "$HOME/.dotfiles/nvim/bin/nvim-session" && ln -s envi "$HOME/.dotfiles/nvim/bin/nvim-session"
refused "a session helper that is a link" cutover
rm "$HOME/.dotfiles/nvim/bin/nvim-session" && cp "$repo/nvim/bin/nvim-session" "$HOME/.dotfiles/nvim/bin/"
mv "$XDG_CONFIG_HOME" "$HOME/real-config" && ln -s "$XDG_STATE_HOME/envi/undo" "$XDG_CONFIG_HOME"
refused "a linked config parent (into the envi state)" cutover
rm "$XDG_CONFIG_HOME" && mv "$HOME/real-config" "$XDG_CONFIG_HOME"
migrate cutover >/dev/null 2>&1
mv "$XDG_CONFIG_HOME" "$HOME/real-config" && ln -s "$XDG_STATE_HOME/envi/undo" "$XDG_CONFIG_HOME"
before="$(snapshot "$XDG_STATE_HOME/envi"):$(snapshot "$XDG_STATE_HOME/nvim"):$(find "$HOME/.backups" -name ROLLED_BACK | wc -l)"
if migrate rollback >"$sandbox/out" 2>&1; then bad "rollback through a linked config parent: refused"; else ok "rollback through a linked config parent: refused"; fi
check "  ... nothing changed, not marked done" \
  test "$(snapshot "$XDG_STATE_HOME/envi"):$(snapshot "$XDG_STATE_HOME/nvim"):$(find "$HOME/.backups" -name ROLLED_BACK | wc -l)" = "$before"
rm "$XDG_CONFIG_HOME" && mv "$HOME/real-config" "$XDG_CONFIG_HOME"
migrate rollback >/dev/null 2>&1 || bad "  ... the retry exits 0"
check "  ... and restores everything" test "$(world_state)" = "$pre"

world formats
put "$HOME/.backups/envi-migrate-20250101-000000-00000001/manifest" "$(printf 'version\t1')"
: >"$HOME/.backups/envi-migrate-20250101-000000-00000001/APPLIED"
mkdir -p "$HOME/.backups/envi-migrate-20250101-000000-00000002"
for b in 00000001 00000002; do
  if migrate rollback "$HOME/.backups/envi-migrate-20250101-000000-$b" >"$sandbox/out" 2>&1; then
    bad "rollback refuses $b"
  else ok "rollback refuses $b"; fi
done
if migrate rollback >"$sandbox/out" 2>&1; then bad "rollback without a backup refuses when one is in doubt"; else
  ok "rollback without a backup refuses when one is in doubt"
fi
refused "apply refuses while a backup is in doubt" cutover
check "  ... and leaves their markers alone" test -f "$HOME/.backups/envi-migrate-20250101-000000-00000001/APPLIED" -a \
  -z "$(find "$HOME/.backups" -name ROLLED_BACK)"
rm -rf "$HOME/.backups"
rm "$XDG_CONFIG_HOME/nvim" && ln -s -- "-old-config"$'\n' "$XDG_CONFIG_HOME/nvim"
pre="$(world_state)"
migrate cutover >/dev/null 2>&1
migrate rollback >/dev/null 2>&1 || bad "a link target starting with a dash: rollback exits 0"
check "a link target starting with a dash (and a newline) is restored exactly" test "$(world_state)" = "$pre"

# ── r3: rollback operands, manifest integrity, initializers, preflight ──

# rollback_refused <name> <backup>: refused, live state, links and markers unchanged.
rollback_refused() {
  local before
  before="$(world_state):$(find "$HOME/.backups" -name ROLLED_BACK | wc -l)"
  if migrate rollback ${2:+"$2"} >"$sandbox/out" 2>&1; then bad "$1: refused"; else ok "$1: refused"; fi
  check "  ... nothing changed, not marked done" test "$(world_state):$(find "$HOME/.backups" -name ROLLED_BACK | wc -l)" = "$before"
}
world operands
pre="$(world_state)"
migrate cutover >/dev/null 2>&1
b="$(open_backups)"
envi_before="$(snapshot "$XDG_STATE_HOME/envi")"
ln -s "$XDG_STATE_HOME/envi/undo" "$b/rollback-displaced"
rollback_refused "a linked rollback-displaced (into the envi state)" "$b"
check "  ... the envi state untouched" test "$(snapshot "$XDG_STATE_HOME/envi")" = "$envi_before"
rm "$b/rollback-displaced"
mv "$b/state-nvim" "$b/state-aside" && ln -s "$XDG_STATE_HOME/envi" "$b/state-nvim"
rollback_refused "a linked saved state" "$b"
rm "$b/state-nvim" && mv "$b/state-aside" "$b/state-nvim"
ln -s "$XDG_STATE_HOME/envi" "$XDG_STATE_HOME/nvim.envi-migrate.${b##*envi-migrate-}"
rollback_refused "a linked staging path" "$b"
rm "$XDG_STATE_HOME/nvim.envi-migrate.${b##*envi-migrate-}"
cp "$b/manifest" "$sandbox/manifest"
sed '/^do_state=/d' "$sandbox/manifest" >"$b/manifest"
rollback_refused "a manifest without do_state" "$b"
sed 's/^link1_old=.*/link1_old=5a/' "$sandbox/manifest" >"$b/manifest"
rollback_refused "a manifest with a corrupt link entry" "$b"
{ cat "$sandbox/manifest"; echo do_state=0; } >"$b/manifest"
rollback_refused "a manifest with a repeated key" "$b"
cp "$sandbox/manifest" "$b/manifest"
mkdir -p "$sandbox/grep"
# shellcheck disable=SC2016 # the shim's own variables
printf '#!/bin/sh\nfor a do last="$a"; done\n[ "$last" = "%s" ] && exit "$GREP_RC"\nexec %s "$@"\n' "$b/manifest" "$(command -v grep)" >"$sandbox/grep/grep"
chmod +x "$sandbox/grep/grep"
for rc in 2 1; do # 2: a read error; 1: what a torn manifest looks like, here with a state change behind it
  before="$(world_state)"
  if GREP_RC=$rc PATH="$sandbox/grep:$PATH" migrate rollback "$b" >"$sandbox/out" 2>&1; then bad "manifest check exit $rc: refused"; else
    ok "manifest check exit $rc: refused"
  fi
  check "  ... nothing changed, not marked done" test "$(world_state)" = "$before" -a ! -e "$b/ROLLED_BACK"
done
mkdir -p "$sandbox/stat"
cat >"$sandbox/stat/stat" <<EOF
#!/bin/sh
for a do last="\$a"; done
[ "\$last" = "$b/state-nvim" ] && exit 1
exec "$(command -v stat)" "\$@"
EOF
chmod +x "$sandbox/stat/stat"
before="$(world_state)"
if PATH="$sandbox/stat:$PATH" migrate rollback "$b" >"$sandbox/out" 2>&1; then bad "no device id for the saved state: rollback refused"; else
  ok "no device id for the saved state: rollback refused"
fi
check "  ... nothing changed" test "$(world_state)" = "$before" -a ! -e "$b/ROLLED_BACK"
migrate rollback "$b" >/dev/null 2>&1 || bad "  ... the retry exits 0"
check "  ... and restores everything" test "$(world_state)" = "$pre"
torn="$HOME/.backups/envi-migrate-20250101-000000-0000000d"
put "$torn/manifest" "format=2"
migrate rollback "$torn" >"$sandbox/out" 2>&1 || bad "a torn manifest alone (stopped before any change): closed"
check "a torn manifest alone (stopped before any change): closed, nothing else changed" test -f "$torn/ROLLED_BACK" -a "$(world_state)" = "$pre"

world preflight
pre="$(world_state)"
cat >"$sandbox/stat/stat" <<EOF
#!/bin/sh
for a do last="\$a"; done
[ "\$last" = "$XDG_STATE_HOME/nvim" ] && echo 99999999 && exit 0
exec "$(command -v stat)" "\$@"
EOF
if PATH="$sandbox/stat:$PATH" migrate cutover >"$sandbox/out" 2>&1; then bad "the state folder on another device: refused"; else
  ok "the state folder on another device: refused"
fi
check "  ... nothing changed, no backup" test "$(world_state)" = "$pre" -a ! -e "$HOME/.backups"
fail_tool od "-tx1"
if with_fail cutover >"$sandbox/out" 2>&1; then bad "a manifest encoding error: refused"; else ok "a manifest encoding error: refused"; fi
check "  ... before any change or backup" test "$(world_state)" = "$pre" -a ! -e "$HOME/.backups"
clear_fail
mv "$HOME/.dotfiles/nvim/bin/envi-guard.sh" "$sandbox/guard-aside"
refused "a production launcher whose sourced helper is missing" cutover
mv "$sandbox/guard-aside" "$HOME/.dotfiles/nvim/bin/envi-guard.sh"
ln -s "$XDG_CONFIG_HOME/old" "$HOME/.local/bin/nvim"
if XDG_CONFIG_HOME="$HOME/.local/bin" migrate cutover >"$sandbox/out" 2>&1; then bad "overlapping managed paths: refused"; else
  ok "overlapping managed paths: refused"
fi
check "  ... nothing changed, no backup" test ! -e "$HOME/.backups" -a "$(readlink "$HOME/.local/bin/nvim")" = "$XDG_CONFIG_HOME/old"
rm "$HOME/.local/bin/nvim"
mkdir -p "$HOME/.backups/envi-migrate-manual.init" "$HOME/.backups/envi-migrate-20250101-000000-0000000a.init" "$HOME/.backups/notes"
echo keep >"$HOME/.backups/envi-migrate-manual.init/sentinel"
echo keep >"$HOME/.backups/envi-migrate-20250101-000000-0000000a.init/sentinel"
mkdir -m 700 "$HOME/.backups/envi-migrate-20250101-000000-0000000b.init"
mkdir -p "$XDG_STATE_HOME/envi/swap"
fail_tool find "\"$XDG_STATE_HOME/envi/swap\""
if with_fail cutover >"$sandbox/out" 2>&1; then ok "a failed swap count is advisory: exit 0"; else bad "a failed swap count is advisory: exit 0"; fi
check "  ... with APPLIED" test -n "$(find "$HOME/.backups" -name APPLIED)"
check "  ... and a warning" has "$sandbox/out" "advisory"
clear_fail
check "foreign initializer-like folders untouched" test -f "$HOME/.backups/envi-migrate-manual.init/sentinel" -a \
  -f "$HOME/.backups/envi-migrate-20250101-000000-0000000a.init/sentinel" -a -d "$HOME/.backups/notes"
check "  ... while this tool's own empty initializer is removed" test ! -e "$HOME/.backups/envi-migrate-20250101-000000-0000000b.init"
mkdir -m 700 "$HOME/.backups/envi-migrate-20250101-000000-0000000c.init"
migrate cutover >"$sandbox/out" 2>&1
check "a no-op re-apply also removes its own initializer" test ! -e "$HOME/.backups/envi-migrate-20250101-000000-0000000c.init"
check "  ... and changes nothing else" has "$sandbox/out" "^nothing to change$"
migrate links >/dev/null 2>&1
rm "$HOME/.local/bin/envi-dev"
migrate links >/dev/null 2>&1
if migrate rollback >"$sandbox/out" 2>&1; then bad "two open backups: rollback without a path refuses"; else
  ok "two open backups: rollback without a path refuses"
fi
check "  ... naming both" test "$(grep -c 'envi-migrate-' "$sandbox/out")" -ge 2

# ── r4: the backup inventory ────────────────────────────────────────────

world inventory
migrate cutover >/dev/null 2>&1
b="$(open_backups)"
before="$(world_state)"
chmod 300 "$HOME/.backups"
if migrate rollback >"$sandbox/out" 2>&1; then bad "an unreadable backup root: rollback refused"; else ok "an unreadable backup root: rollback refused"; fi
chmod 700 "$HOME/.backups"
check "  ... nothing changed, not marked done" test "$(world_state)" = "$before" -a ! -e "$b/ROLLED_BACK" -a -d "$b/state-nvim"
check "  ... saying it cannot read it" has "$sandbox/out" "cannot read $HOME/.backups"
check "  ... never \"no backup\"" lacks "$sandbox/out" "no backup to roll back"
doubt="$HOME/.backups/envi-migrate-20000101-000000-aabbccdd"
mkdir "$doubt"
rollback_refused "a backup in doubt beside a valid one: rollback without a path" ""
check "  ... naming the valid one" has "$sandbox/out" "^  $b"
check "  ... and the doubtful one, with its error" has "$sandbox/out" "^  $doubt: .*has no manifest"
migrate rollback "$b" >/dev/null 2>&1 || bad "  ... an explicit path still rolls back"
check "  ... and restores the state" test ! -e "$b/state-nvim" -a -f "$b/ROLLED_BACK"

world minimal # launchers that source and exec nothing need nothing more
for f in envi envi-dev; do printf '#!/bin/sh\n# ENVI_DEV\n' >"$HOME/.dotfiles/nvim/bin/$f"; done
migrate --dry-run cutover >"$sandbox/out" 2>&1 || bad "launchers with no helpers: the preflight passes"

# ── r4: rollback binds the link destinations recorded at apply ──────────

world destinations
pre="$(world_state)"
migrate cutover >/dev/null 2>&1
b="$(open_backups)"
mkdir -p "$HOME/alt-config" && ln -s "$HOME/unrelated" "$HOME/alt-config/nvim"
before="$(world_state)"
if XDG_CONFIG_HOME="$HOME/alt-config" migrate rollback "$b" >"$sandbox/out" 2>&1; then
  bad "rollback under another XDG_CONFIG_HOME: refused"
else ok "rollback under another XDG_CONFIG_HOME: refused"; fi
check "  ... nothing changed, not marked done" test "$(world_state)" = "$before" -a ! -e "$b/ROLLED_BACK"
check "  ... the other config root untouched" test "$(readlink "$HOME/alt-config/nvim")" = "$HOME/unrelated"
check "  ... naming the recorded destination" has "$sandbox/out" "$XDG_CONFIG_HOME/nvim"
migrate rollback "$b" >/dev/null 2>&1 || bad "  ... the original environment still rolls back"
check "  ... and restores everything" test "$(world_state)" = "$pre"

# ── r5: automatic selection reads each backup once ──────────────────────

world reread
pre="$(world_state)"
migrate cutover >/dev/null 2>&1
old="$(open_backups)"
migrate rollback "$old" >/dev/null 2>&1
migrate cutover >/dev/null 2>&1
active="$(open_backups)"
mkdir -p "$sandbox/head"
# shellcheck disable=SC2016 # the shim's own variables
printf '#!/bin/sh\nfor a do last="$a"; done\nif [ "$last" = "%s" ]; then\n  if [ "$HEAD_ALWAYS" = 1 ] || [ -e "%s" ]; then echo "fixture: head failed" >&2; exit 1; fi\n  : >"%s"\nfi\nexec %s "$@"\n' \
  "$old/manifest" "$sandbox/head-seen" "$sandbox/head-seen" "$(command -v head)" >"$sandbox/head/head"
chmod +x "$sandbox/head/head"
before="$(world_state)"
if HEAD_ALWAYS=1 PATH="$sandbox/head:$PATH" migrate rollback >"$sandbox/out" 2>&1; then
  bad "a backup that cannot be read: rollback without a path refused"
else ok "a backup that cannot be read: rollback without a path refused"; fi
check "  ... nothing changed, not marked done" test "$(world_state)" = "$before" -a ! -e "$active/ROLLED_BACK"
check "  ... naming the unreadable one" has "$sandbox/out" "^  $old: "
check "  ... with its error" has "$sandbox/out" "cannot read $old/manifest"
check "  ... and the active one" has "$sandbox/out" "^  $active$"
rm -f "$sandbox/head-seen"
HEAD_ALWAYS=0 PATH="$sandbox/head:$PATH" migrate rollback >"$sandbox/out" 2>&1 ||
  bad "each backup read once: rollback without a path exits 0"
check "  ... and restores everything" test "$(world_state)" = "$pre" -a -f "$active/ROLLED_BACK"

# ── SIGKILL after every cp, mv, ln and mkdir ────────────────────────────

# Shims count each call, run the real tool, then kill the migration after call
# number $SHIM_KILL_AT of $SHIM_KILL_TOOL.
mkdir -p "$sandbox/shim"
for tool in cp mv ln mkdir; do
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
clean_world() { no_staging && no_temp_links && ! find "$HOME/.backups" -maxdepth 1 -name '*.init' 2>/dev/null | grep -q .; }

world reference
pre="$(world_state)"
shimmed none 0 cutover
apply_calls="cp=$(calls cp) mv=$(calls mv) ln=$(calls ln) mkdir=$(calls mkdir)"
ref_after="$(world_state | sed "s|$HOME|<home>|g")"
shimmed none 0 rollback
rollback_calls="cp=$(calls cp) mv=$(calls mv) ln=$(calls ln) mkdir=$(calls mkdir)"
check "reference: apply calls to interrupt ($apply_calls)" test "$(calls cp)" -ge 0
check "reference: rollback restores" test "$(world_state)" = "$pre"

for spec in $apply_calls; do
  tool="${spec%=*}"
  at=0
  while [ "$at" -lt "${spec#*=}" ]; do
    at=$((at + 1))
    name="apply killed after $tool #$at"
    world "kill-$tool-$at"
    pre="$(world_state)"
    rc=0
    shimmed "$tool" "$at" cutover || rc=$?
    check "$name: really killed" test "$rc" = 137
    if [ -n "$(open_backups)" ] && [ -z "$(find "$HOME/.backups" -name APPLIED)" ]; then
      if migrate cutover >/dev/null 2>&1; then bad "$name: a new apply refuses"; else ok "$name: a new apply refuses"; fi
    else
      check "$name: no backup yet, so nothing changed" test "$(world_state)" = "$pre"
    fi
    migrate rollback >"$sandbox/out" 2>&1 || bad "$name: rollback exits 0"
    check "$name: rollback restores state and links exactly" test "$(world_state)" = "$pre"
    check "$name: no staging, temporary link or initializer left" clean_world
    migrate cutover >/dev/null 2>&1 || bad "$name: a new apply runs"
    check "$name: and then gives the same result as an uninterrupted one" \
      test "$(world_state | sed "s|$HOME|<home>|g")" = "$ref_after"
  done
done

for spec in $rollback_calls; do
  tool="${spec%=*}"
  at=0
  while [ "$at" -lt "${spec#*=}" ]; do
    at=$((at + 1))
    name="rollback killed after $tool #$at"
    world "rbkill-$tool-$at"
    pre="$(world_state)"
    migrate cutover >/dev/null 2>&1
    echo "edited after the cutover" >>"$XDG_STATE_HOME/nvim/undo/%only%envi"
    post="$(snapshot "$XDG_STATE_HOME/nvim")"
    rc=0
    shimmed "$tool" "$at" rollback || rc=$?
    check "$name: really killed" test "$rc" = 137
    b="$(open_backups)"
    check "$name: not marked done" test ! -e "$b/ROLLED_BACK"
    migrate rollback >"$sandbox/out" 2>&1 || bad "$name: the retry exits 0"
    check "$name: the retry restores state and links exactly" test "$(world_state)" = "$pre"
    check "$name: the post-cutover state is kept once, untouched" \
      test "$(snapshot "$b/rollback-displaced/nvim")" = "$post" -a ! -e "$b/rollback-displaced/nvim.2"
    check "$name: no temporary link left" clean_world
    check "$name: marked done" test -f "$b/ROLLED_BACK"
  done
done

finish
