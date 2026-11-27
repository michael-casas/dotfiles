#!/usr/bin/env bash
# Run the Markdown Emmet tests with only the repo and Neovim's built-in runtime.
set -euo pipefail
cd "$(dirname "$0")/../../../.."
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/envi-markdown-emmet.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT
export XDG_CONFIG_HOME="$sandbox/config" XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state" XDG_CACHE_HOME="$sandbox/cache"
export NVIM_APPNAME=envi-markdown-emmet-test

nvim --headless -u NONE -i NONE -n -l nvim/tools/markdown-emmet/test/expansion.lua
