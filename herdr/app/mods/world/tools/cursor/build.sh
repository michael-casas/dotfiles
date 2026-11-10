#!/usr/bin/env bash
# Builds the world-cursor helper into ../../bin/world-cursor (mods/world/bin).
# Skips the compile when the binary is already newer than the source.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/world-cursor.swift"
out_dir="$(cd "$here/../.." && pwd)/bin"
out="$out_dir/world-cursor"

if [[ -x "$out" && "$out" -nt "$src" ]]; then
  echo "world-cursor is up to date: $out"
  exit 0
fi

mkdir -p "$out_dir"
swiftc -O -o "$out.tmp" "$src"
mv -f "$out.tmp" "$out"
echo "built $out"
