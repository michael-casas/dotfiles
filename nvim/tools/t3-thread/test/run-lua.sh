#!/usr/bin/env bash
# Run the envi headless Lua suites; exit nonzero if any fails.
#   nvim/tools/t3-thread/test/run-lua.sh            # every suite
#   nvim/tools/t3-thread/test/run-lua.sh prs agent  # named suites
# `nvim --headless '+luafile x' +qa` exits 0 even when x throws, so each suite
# runs under pcall and a failure quits with :cquit. Errors raised later in
# scheduled callbacks/timers land in :messages, so those fail the suite too.
set -u
cd "$(dirname "$0")/../../../.." || exit 2
dir=nvim/tools/t3-thread/test
# Isolation: node children load the test guard (no live port 3773, no real
# ~/.t3); T3 data and the default URL are throwaway.
guard_home=$(mktemp -d "${TMPDIR:-/tmp}/t3-lua-home.XXXXXX")
trap 'rm -rf "$guard_home"' EXIT
export T3UPD_GUARD_REAL_HOME="$HOME" T3UPD_GUARD_HOME="$guard_home" T3CODE_HOME="$guard_home/.t3"
export T3_URL="${T3_URL:-http://127.0.0.1:9}"
export NODE_OPTIONS="${NODE_OPTIONS:-} --import $PWD/$dir/support/guard.mjs"
if [ $# -gt 0 ]; then names=("$@"); else
  names=()
  for f in "$dir"/*.lua; do names+=("$(basename "$f" .lua)"); done
fi
failed=0
for n in "${names[@]}"; do
  f="$dir/$n.lua"
  if nvim --headless -u NONE \
    -c "lua local ok, e = pcall(dofile, '$f') if not ok then io.stderr:write(tostring(e) .. '\n') vim.cmd('cquit 1') end" \
    -c "lua vim.wait(50, function() return false end) if vim.api.nvim_exec2('messages', { output = true }).output:find('Error executing', 1, true) then io.stderr:write('error in a scheduled callback\n') vim.cmd('cquit 1') end" \
    -c 'qa!' >"/tmp/envi-lua-$n.log" 2>&1; then
    echo "ok   $n"
  else
    echo "FAIL $n"; sed 's/^/     /' "/tmp/envi-lua-$n.log" | tail -15; failed=1
  fi
done
exit $failed
