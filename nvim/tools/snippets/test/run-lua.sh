#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../../.."
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/envi-snippets.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT
export XDG_CONFIG_HOME="$sandbox/config" XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state" XDG_CACHE_HOME="$sandbox/cache"
export NVIM_APPNAME=envi-snippets-test
nvim --headless -u NONE -i NONE -n -l nvim/tools/snippets/test/pipeline.lua
nvim --headless -u NONE -i NONE -n -l nvim/tools/snippets/test/blink.lua
nvim --headless -u NONE -i NONE -n -l nvim/tools/snippets/test/helptags.lua
