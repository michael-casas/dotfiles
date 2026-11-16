#!/usr/bin/env bash
# Save and swap whole Herdr app views.
#
# A view is everything that makes the window look and behave the way it does:
# herdr/app at one dotfiles commit (layouts, themes, keys, settings, our mods,
# and the Omarchy fork pinned by the submodule) plus the clicks the app keeps
# outside git (node sizes, hidden nodes, chosen stack children).
#
#   view.sh save <name>   record the shown layout's clicks in views/<name>.json,
#                         commit that file, and tag the commit herdr-view/<name>
#   view.sh load <name>   export herdr-view/<name> to ~/.local/share/herdr-views/<name>,
#                         install it with that copy's sync.sh, switch to its layout,
#                         and replay its clicks. The checkout is not touched.
#   view.sh live          go back to the checkout (runs ~/.dotfiles/herdr/app/sync.sh)
#   view.sh list          saved views
#
# save needs herdr/app committed (it refuses with uncommitted changes there), so
# the tag is the exact view. Re-saving a name needs -f, which moves the tag.
set -euo pipefail

app="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$app" rev-parse --show-toplevel)"
home="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
store="${HERDR_VIEWS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/herdr-views}"

# Python as strings, not heredocs: Homebrew bash 5.3 can hang on a heredoc
# feeding a pipeline.
SAVE_PY='
import json, sys, os, datetime
state, layout, fork, out = sys.argv[1:]
clicks = json.load(open(state)).get("nodes", {}) if os.path.exists(state) else {}
with open(out, "w") as f:
    json.dump({"layout": layout, "clicks": clicks, "omarchy_fork": fork,
               "saved": datetime.date.today().isoformat()}, f, indent=2)
    f.write("\n")
'
CLICKS_PY='
import json, sys
for id, n in json.load(open(sys.argv[1]))["clicks"].items():
    size = n.get("size") or {}
    if "px" in size: print("layout.resize", json.dumps({"id": id, "px": size["px"]}), sep="\t")
    elif "weight" in size: print("layout.resize", json.dumps({"id": id, "weight": size["weight"]}), sep="\t")
    if "active" in n: print("layout.select", json.dumps({"stack": id, "child": n["active"]}), sep="\t")
    if "hidden" in n: print("layout.hide" if n["hidden"] else "layout.show", json.dumps({"id": id}), sep="\t")
'

die() { echo "view.sh: $*" >&2; exit 1; }
check_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "name must be lowercase letters, digits and dashes: '$1'"; }
shown_layout() { herdr-app status | python3 -c 'import json,sys; print(json.load(sys.stdin)["layout"])'; }

save() {
  local force=0
  [[ "${1:-}" == "-f" ]] && { force=1; shift; }
  local name="${1:-}"; check_name "$name"
  local tag="herdr-view/$name" rel="herdr/app/views/$name.json"
  if git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null && (( ! force )); then
    die "$tag exists. Use 'save -f $name' to replace it"
  fi
  if [[ -n "$(git -C "$repo" status --porcelain -- herdr/app ':!herdr/app/views')" ]]; then
    git -C "$repo" status --short -- herdr/app ':!herdr/app/views' >&2
    die "commit herdr/app first, so the view is reproducible"
  fi
  local layout; layout="$(shown_layout)"
  local fork; fork="$(git -C "$repo" rev-parse "HEAD:herdr/app/omarchy" 2>/dev/null || echo none)"
  mkdir -p "$app/views"
  python3 -c "$SAVE_PY" "$home/layouts/.state/$layout.json" "$layout" "$fork" "$app/views/$name.json"
  git -C "$repo" add -- "$rel"
  if ! git -C "$repo" diff --cached --quiet -- "$rel"; then
    git -C "$repo" commit -q -m "chore(herdr): save the $name view" -- "$rel"
  fi
  git -C "$repo" tag -f -a "$tag" -m "Herdr app view: $name (layout $layout)" >/dev/null
  echo "saved $tag at $(git -C "$repo" rev-parse --short HEAD): layout $layout, $(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["clicks"]))' "$app/views/$name.json") click(s)"
}

load() {
  local name="${1:-}"; check_name "$name"
  local tag="herdr-view/$name"
  git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no view '$name' (try: view.sh list)"
  local dest="$store/$name"
  [[ "$dest" == "$store/"* && -n "$name" ]] || die "bad export path"
  rm -rf "$dest" && mkdir -p "$dest"
  # Archive to a file, not a pipe: bsdtar stops reading at the end marker, and
  # git archive then dies of SIGPIPE writing its padding (fails under pipefail).
  local tarball; tarball="$(mktemp -t herdr-view)"
  git -C "$repo" archive -o "$tarball" "$tag" herdr/app
  tar -x -f "$tarball" -C "$dest" --strip-components=2
  local fork; fork="$(git -C "$repo" rev-parse "$tag:herdr/app/omarchy" 2>/dev/null || true)"
  if [[ -n "$fork" ]]; then
    git -C "$repo/herdr/app/omarchy" cat-file -e "$fork^{commit}" 2>/dev/null \
      || die "fork commit $fork is missing: run 'git -C herdr/app/omarchy fetch origin'"
    mkdir -p "$dest/omarchy"
    git -C "$repo/herdr/app/omarchy" archive -o "$tarball" "$fork"
    tar -x -f "$tarball" -C "$dest/omarchy"
  fi
  rm -f "$tarball"
  bash "$dest/sync.sh" >/dev/null
  local meta="$dest/views/$name.json"
  local layout; layout="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["layout"])' "$meta")"
  herdr-app "do" layout.switch "{\"name\":\"$layout\"}" >/dev/null
  local cmds; cmds="$(python3 -c "$CLICKS_PY" "$meta")"
  while IFS=$'\t' read -r cmd args; do
    [[ -n "$cmd" ]] && herdr-app "do" "$cmd" "$args" >/dev/null
  done <<< "$cmds"
  echo "loaded $tag from $dest (layout $layout). 'view.sh live' goes back to the checkout"
}

live() {
  bash "$app/sync.sh" >/dev/null
  echo "live: herdr-app runs from $app again"
}

list() {
  git -C "$repo" for-each-ref --format='%(refname:strip=2)  %(*objectname:short)  %(contents:subject)' 'refs/tags/herdr-view/*' \
    | sed 's#^herdr-view/##'
}

case "${1:-}" in
  save) shift; save "$@" ;;
  load) shift; load "$@" ;;
  live) live ;;
  list) list ;;
  *) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
