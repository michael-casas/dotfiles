#!/usr/bin/env bash
# Headless Sudoku scenario suites (the README's @headless conventions).
#   nvim/lua/hcmux/sudoku/test/run.sh                 # every suite
#   nvim/lua/hcmux/sudoku/test/run.sh 01-open-close   # named suites
# Each suite runs in its own `nvim --headless -u NONE` with isolated XDG homes, so
# no save file, shada or state from a real profile is read or written. Plugins
# (Snacks, LazyVim, lazy.nvim) come read-only from ENVI_TEST_PLUGIN_ROOT.
set -u
cd "$(dirname "$0")/../../../../.." || exit 2
dir=nvim/lua/hcmux/sudoku/test
export ENVI_TEST_PLUGIN_ROOT="${ENVI_TEST_PLUGIN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy}"
if [ $# -gt 0 ]; then names=("$@"); else
  names=()
  for f in "$dir"/[0-9]*.lua; do names+=("$(basename "$f" .lua)"); done
fi
failed=0
for n in "${names[@]}"; do
  f="$dir/$n.lua"
  home=$(mktemp -d "${TMPDIR:-/tmp}/envi-sudoku-test.XXXXXX")
  log="$home/run.log"
  if env XDG_STATE_HOME="$home/state" XDG_DATA_HOME="$home/data" XDG_CACHE_HOME="$home/cache" \
    XDG_CONFIG_HOME="$home/config" NVIM_APPNAME=envi-sudoku-test SHELL=sh \
    nvim --headless -u NONE -i NONE -n \
    -c "lua vim.opt.rtp:prepend(vim.fn.getcwd() .. '/nvim')" \
    -c "lua local ok, e = pcall(dofile, '$f') if not ok then io.stderr:write(tostring(e) .. '\n') vim.cmd('cquit 1') end" \
    -c "lua vim.wait(50, function() return false end) if vim.api.nvim_exec2('messages', { output = true }).output:find('Error executing', 1, true) then io.stderr:write('error in a scheduled callback\n') vim.cmd('cquit 1') end" \
    -c 'qa!' >"$log" 2>&1; then
    echo "ok   $n"
    grep '^  ok ' "$log" | sed 's/^/   /'
  else
    echo "FAIL $n"
    sed 's/^/     /' "$log" | tail -40
    failed=1
  fi
  rm -rf "$home"
done
exit $failed
