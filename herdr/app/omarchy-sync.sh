#!/usr/bin/env bash
# Install the Omarchy layout from the herdr/app/omarchy submodule (private fork
# michael-casas/herdr-omarchy) into the Herdr app home.
#
# - mods are COPIED: herdr-app 0.1.14 runs a symlinked mod folder's JS but does
#   not load its svg/image assets. Re-run this after changing mods in the fork.
# - themes, the layout and the wallpapers are SYMLINKED (verified to work).
# - omarchy-ai-usage is skipped (replaced by a spacer in the fork's layout).
# - keys.json is not touched; see herdr/app/docs/omarchy.md to merge keys.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/omarchy"
home="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
skip=(omarchy-ai-usage)

[[ -f "$src/layouts/omarchy.json" ]] || {
  echo "missing $src; run: git submodule update --init herdr/app/omarchy" >&2
  exit 1
}
mkdir -p "$home"/{mods,themes,layouts,backgrounds}

for m in "$src"/mods/omarchy-*; do
  name="$(basename "$m")"
  [[ " ${skip[*]} " == *" $name "* ]] && continue
  dest="$home/mods/$name"
  [[ -L "$dest" ]] && rm "$dest"
  rsync -a --delete "$m/" "$dest/"
done

for f in "$src"/themes/*.json; do
  ln -sfn "$f" "$home/themes/$(basename "$f")"
done
ln -sfn "$src/layouts/omarchy.json" "$home/layouts/omarchy.json"
ln -sfn "$src/layouts/omarchy.svg" "$home/layouts/omarchy.svg"
ln -sfn "$src/backgrounds/omarchy" "$home/backgrounds/omarchy"

echo "omarchy synced into $home"
