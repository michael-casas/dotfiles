#!/usr/bin/env bash
# The launcher, dev profile and cutover suites (sandboxed; nothing real is touched).
#   nvim/bin/test/run.sh
set -u
cd "$(dirname "$0")" || exit 2
failed=0
for suite in launcher migrate; do
  if out="$(./"$suite".sh 2>&1)"; then
    echo "ok   $suite ($(tail -n 1 <<<"$out"))"
  else
    echo "FAIL $suite"
    grep -v '^PASS' <<<"$out" | sed 's/^/     /'
    failed=1
  fi
done
exit $failed
