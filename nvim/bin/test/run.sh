#!/usr/bin/env bash
# Sandboxed launcher, migration, and Markdown editing suites.
#   nvim/bin/test/run.sh
set -u
cd "$(dirname "$0")" || exit 2
failed=0
run_suite() {
  local suite="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    echo "ok   $suite ($(tail -n 1 <<<"$out"))"
  else
    echo "FAIL $suite"
    grep -v '^PASS' <<<"$out" | sed 's/^/     /'
    failed=1
  fi
}

run_suite launcher ./launcher.sh
run_suite migrate ./migrate.sh
EMMET_MD_ENVI_CONFIG="$(cd ../.. && pwd)" run_suite emmet-md ../../plugins/emmet-md/tests/run-lua.sh
run_suite envi-snippets ../../tools/snippets/test/run-lua.sh
exit $failed
