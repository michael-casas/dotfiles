#!/usr/bin/env python3
"""Link canonical dotfiles skills directly into Claude and Agents only.

A destination that already holds something else (a real skill directory or a
file) is user-owned: it is left untouched, reported, and the remaining links
are still applied. Links an earlier installer created for skills this repository
no longer ships are removed, but only when they point at exactly the old
canonical path.
"""

import argparse
import json
import os
import sys
from pathlib import Path

HOME = Path.home()
CANONICAL = Path(__file__).resolve().parent / "skills"
TARGETS = [HOME / ".claude/skills", HOME / ".agents/skills"]
# Skills this repository used to ship.
RETIRED = ("herdr-bridge",)
# Every directory an earlier version of this script linked skills into, and the
# index it generated.
LEGACY_DIRS = [HOME / p for p in (".local/share/agent-skills/catalog", ".agents/skills",
                                  ".codex/skills", ".pi/agent/skills", ".claude/skills")]
LEGACY_MANIFEST = HOME / ".local/share/agent-skills/manifest.json"


def retired_entries():
    """Installer-owned links and manifest entries for retired skills."""
    links, manifest = [], []
    for name in RETIRED:
        source = CANONICAL / name
        if source.exists():
            continue  # still shipped; nothing to retire
        for directory in LEGACY_DIRS:
            dest = directory / name
            if dest.is_symlink() and os.readlink(dest) == str(source):
                links.append(dest)
        if LEGACY_MANIFEST.is_file():
            try:
                index = json.loads(LEGACY_MANIFEST.read_text())
            except ValueError:
                index = None
            if isinstance(index, dict) and index.get(name) == str(source):
                manifest.append(name)
    return links, manifest


def retire(links, manifest):
    for dest in links:
        dest.unlink(missing_ok=True)
    if manifest:
        index = json.loads(LEGACY_MANIFEST.read_text())
        for name in manifest:
            index.pop(name, None)
        temporary = LEGACY_MANIFEST.with_name(".skill-manifest.json")
        temporary.write_text(json.dumps(index, indent=2) + "\n")
        os.replace(temporary, LEGACY_MANIFEST)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true", help="Create direct canonical skill links")
    args = parser.parse_args()
    if not CANONICAL.is_dir() or CANONICAL.is_symlink():
        parser.error(f"Canonical skills must be a real directory: {CANONICAL}")
    sources = sorted(entry for entry in CANONICAL.iterdir()
                     if not entry.is_symlink() and (entry / "SKILL.md").is_file())
    if not sources:
        parser.error(f"No canonical skills found in {CANONICAL}")
    skipped, links = [], []
    for target in TARGETS:
        if target.is_symlink() or (target.exists() and not target.is_dir()):
            skipped.append(str(target))
            continue
        for source in sources:
            dest = target / source.name
            if dest.is_symlink():
                if os.readlink(dest) == str(source):
                    continue
            elif dest.exists():
                skipped.append(str(dest))
                continue
            links.append((dest, source))
    stale_links, stale_manifest = retired_entries()
    if args.apply:
        for dest, source in links:
            dest.parent.mkdir(parents=True, exist_ok=True)
            temporary = dest.with_name(".skill-link-" + dest.name)
            temporary.unlink(missing_ok=True)
            temporary.symlink_to(source, target_is_directory=True)
            try:
                os.replace(temporary, dest)
            finally:
                temporary.unlink(missing_ok=True)
        retire(stale_links, stale_manifest)
    print(json.dumps({"sources": len(sources), "links_needed": len(links),
                      "skipped_user_owned": skipped,
                      "retired_links": [str(dest) for dest in stale_links],
                      "retired_manifest_entries": stale_manifest,
                      "applied": args.apply,
                      "canonical_home": str(CANONICAL),
                      "targets": [str(target) for target in TARGETS]}, indent=2))
    for path in skipped:
        print(f"warning: kept existing {path}; it is not a link to this repository", file=sys.stderr)


if __name__ == "__main__":
    main()
