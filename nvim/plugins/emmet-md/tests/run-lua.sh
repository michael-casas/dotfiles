#!/usr/bin/env bash
# Run the Markdown Emmet tests with the plugin and Neovim's built-in runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/emmet-md.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT
export XDG_CONFIG_HOME="$sandbox/config" XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state" XDG_CACHE_HOME="$sandbox/cache"
export NVIM_APPNAME=emmet-md-test

if [ "$#" -eq 0 ]; then
  set -- api expansion interaction helptags
fi
for suite do
  nvim --headless -u NONE -i NONE -n -l "tests/$suite.lua"
done
