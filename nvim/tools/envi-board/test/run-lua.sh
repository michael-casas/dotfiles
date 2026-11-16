#!/usr/bin/env bash
# Fail closed: :luafile followed by :qa can hide Lua errors behind exit 0.
set -u
cd "$(dirname "$0")/../../../.." || exit 2
failed=0
log=$(mktemp "${TMPDIR:-/tmp}/envi-board-lua.XXXXXX") || exit 2
trap 'rm -f "$log"' EXIT
for file in nvim/tools/envi-board/test/*.lua; do
  if nvim --headless -u NONE \
    -c "lua local ok, e = pcall(dofile, '$file') if not ok then io.stderr:write(tostring(e) .. '\n') vim.cmd('cquit 1') end" \
    -c 'qa!' >"$log" 2>&1; then
    echo "ok   $(basename "$file" .lua)"
  else
    echo "FAIL $(basename "$file" .lua)"
    tail -15 "$log"
    failed=1
  fi
done
exit "$failed"
