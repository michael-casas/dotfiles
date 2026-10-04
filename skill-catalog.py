#!/usr/bin/env python3
"""Link the curated canonical skills; preserve vendor and variant entries."""

import argparse
import json
import os
from pathlib import Path

HOME = Path.home()
REPO = Path(__file__).resolve().parent
CANONICAL = REPO / "skills"
NAMES = (
    "agent-wiki", "batdd", "bb-cli", "caveman", "git-branch", "han-solo",
    "herdr-bridge", "lavish", "nx-monorepo", "ticketing",
)
CATALOG = HOME / ".local/share/agent-skills/catalog"
TARGETS = [HOME / p for p in (".agents/skills", ".codex/skills", ".pi/agent/skills", ".claude/skills")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Create canonical catalog and harness entry links")
    parser.add_argument("--include-claude", action="store_true", help="Also link Claude's canonical entries")
    args = parser.parse_args()
    targets = [CATALOG, *(TARGETS if args.include_claude else TARGETS[:-1])]
    conflicts, missing, links = [], [], []
    for name in NAMES:
        source = CANONICAL / name
        if source.is_symlink() or not (source / "SKILL.md").is_file():
            missing.append(str(source))
    for target in targets:
        if target.is_symlink() or (target.exists() and not target.is_dir()):
            conflicts.append(str(target))
            continue
        for name in NAMES:
            dest = target / name
            if target == HOME / ".codex/skills" and name == "han-solo":
                # A9: Codex owns a real harness-specific implementation.
                if dest.is_symlink() or (dest.exists() and not dest.is_dir()):
                    conflicts.append(str(dest))
                continue
            if dest.is_symlink():
                if os.readlink(dest) == str(CANONICAL / name):
                    continue
            elif dest.exists():
                conflicts.append(str(dest))
                continue
            links.append((dest, CANONICAL / name))
    applied = False
    if args.apply and not conflicts and not missing:
        for dest, source in links:
            dest.parent.mkdir(parents=True, exist_ok=True)
            temporary = dest.with_name(".t19-link-" + dest.name)
            temporary.symlink_to(source, target_is_directory=True)
            try:
                os.replace(temporary, dest)
            finally:
                temporary.unlink(missing_ok=True)
        applied = True
    print(json.dumps({"sources": len(NAMES), "entries": len(NAMES),
                      "links_needed": len(links), "conflicts": conflicts,
                      "missing": missing, "applied": applied,
                      "canonical_home": str(CANONICAL)}, indent=2))
    if conflicts or missing:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
