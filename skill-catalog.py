#!/usr/bin/env python3
"""Link canonical dotfiles skills directly into Claude and Agents only."""

import argparse
import json
import os
from pathlib import Path

HOME = Path.home()
CANONICAL = Path(__file__).resolve().parent / "skills"
TARGETS = [HOME / ".claude/skills", HOME / ".agents/skills"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Create direct canonical skill links")
    args = parser.parse_args()
    if not CANONICAL.is_dir() or CANONICAL.is_symlink():
        parser.error(f"Canonical skills must be a real directory: {CANONICAL}")
    sources = sorted(entry for entry in CANONICAL.iterdir()
                     if not entry.is_symlink() and (entry / "SKILL.md").is_file())
    if not sources:
        parser.error(f"No canonical skills found in {CANONICAL}")
    conflicts, links = [], []
    for target in TARGETS:
        if target.is_symlink() or (target.exists() and not target.is_dir()):
            conflicts.append(str(target))
            continue
        for source in sources:
            dest = target / source.name
            if dest.is_symlink():
                if os.readlink(dest) == str(source):
                    continue
            elif dest.exists():
                conflicts.append(str(dest))
                continue
            links.append((dest, source))
    applied = False
    if args.apply and not conflicts:
        for dest, source in links:
            dest.parent.mkdir(parents=True, exist_ok=True)
            temporary = dest.with_name(".skill-link-" + dest.name)
            temporary.symlink_to(source, target_is_directory=True)
            try:
                os.replace(temporary, dest)
            finally:
                temporary.unlink(missing_ok=True)
        applied = True
    print(json.dumps({"sources": len(sources), "links_needed": len(links),
                      "conflicts": conflicts, "applied": applied,
                      "canonical_home": str(CANONICAL),
                      "targets": [str(target) for target in TARGETS]}, indent=2))
    if conflicts:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
