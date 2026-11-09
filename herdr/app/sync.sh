#!/usr/bin/env bash
# Install herdr/app into the Herdr app home.
#
# Symlinked (verified to work through a symlink):
#   settings.json, keys.json, themes/*.json, layouts/*.{json,svg},
#   and the Omarchy fork's themes, layout and backgrounds/omarchy.
# Copied: every mod folder (ours in mods/, and the fork's omarchy-* mods).
#   herdr-app 0.1.14 runs a symlinked mod's JS but does not load its svg/image
#   assets. Re-run this after changing any mod.
# Skipped: omarchy-ai-usage (the fork's layout has a spacer in its place).
#
# ln -sfn replaces live files: back them up first if they hold unsaved changes.
set -euo pipefail

app="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
omarchy="$app/omarchy"
home="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
skip=(omarchy-ai-usage)

mkdir -p "$home"/{mods,themes,layouts,backgrounds}

link() { ln -sfn "$1" "$2"; }
copy_mod() {
  local src="$1" dest="$home/mods/$(basename "$1")"
  [[ -L "$dest" ]] && rm "$dest"
  rsync -a --delete "$src/" "$dest/"
}

# Ours.
for f in settings.json keys.json programs.json; do
  [[ -f "$app/$f" ]] && link "$app/$f" "$home/$f"
done
for f in "$app"/themes/*.json; do [[ -e "$f" ]] && link "$f" "$home/themes/$(basename "$f")"; done
for f in "$app"/layouts/*.json "$app"/layouts/*.svg; do [[ -e "$f" ]] && link "$f" "$home/layouts/$(basename "$f")"; done
for m in "$app"/mods/*/; do [[ -d "$m" ]] && copy_mod "${m%/}"; done

# The Omarchy fork (submodule).
if [[ -f "$omarchy/layouts/omarchy.json" ]]; then
  for m in "$omarchy"/mods/omarchy-*; do
    [[ " ${skip[*]} " == *" $(basename "$m") "* ]] && continue
    copy_mod "$m"
  done
  for f in "$omarchy"/themes/*.json; do link "$f" "$home/themes/$(basename "$f")"; done
  link "$omarchy/layouts/omarchy.json" "$home/layouts/omarchy.json"
  link "$omarchy/layouts/omarchy.svg" "$home/layouts/omarchy.svg"
  link "$omarchy/backgrounds/omarchy" "$home/backgrounds/omarchy"
else
  echo "skipping omarchy: run 'git submodule update --init herdr/app/omarchy'" >&2
fi

echo "herdr/app synced into $home"
