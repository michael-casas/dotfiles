#!/usr/bin/env python3
"""
command-generate.py — Slim COMMAND.md generator for the dispatch lane.

Takes (intent, file_target) and produces a 2-3KB minimal COMMAND.md that
haiku workers can consume in one read.

Usage:
    python3 command-generate.py \\
        --intent "Add 'cta' node type to ContentNode.contract.ts" \\
        --target src/contracts/content/ContentNode.contract.ts \\
        --out /tmp/COMMAND-s04-cta.md \\
        --tier tier-2 \\
        --workdir /path/to/iqne \\
        --validation "pnpm typecheck:app" "0" \\
        --route /about
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import uuid
from typing import List, Optional

# Tier table (mirrors aes-summon)
TIER_TABLE = {
    "tier-0": ("tier-0-dsv4",      "opencode-go/deepseek-v4-flash"),
    "tier-1": ("tier-1-mini",      "gpt-5.4-mini"),
    "tier-2": ("tier-2-kimi",      "opencode-go/kimi-k2.6"),
    "tier-3": ("tier-3-m3",        "minimax-m3"),
    "tier-4": ("convergence",      "gpt-5.5"),
}

TIER_MAX_RUNTIME = {
    "tier-0": 600,
    "tier-1": 600,
    "tier-2": 1200,
    "tier-3": 1800,
    "tier-4": 3600,
}

FORBIDDEN_PATHS = [
    "src/styles/theme.css",
    "src/app/components/sections/",
    "package.json",
    "pnpm-lock.yaml",
    ".env",
    ".env.local",
    ".envrc",
]

SECRET_PATTERNS = [    r"(?i)password\s*[:=]",
    r"(?i)api[_-]?key\s*[:=]",
    r"(?i)secret\s*[:=]",
    r"(?i)token\s*[:=]",
    r"BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY",
    r"(?i)bearer\s+[A-Za-z0-9._-]{20,}",
]


def detect_secrets(text):
    hits = []
    for pat in SECRET_PATTERNS:
        if re.search(pat, text):
            hits.append(pat)
    return hits


def normalize_path(target, workdir):
    if os.path.isabs(target):
        return os.path.abspath(target)
    return os.path.abspath(os.path.join(workdir, target))


def check_path_exists(path, allow_missing):
    if not os.path.exists(path):
        if allow_missing:
            print(f"warning: target file does not exist: {path}", file=sys.stderr)
        else:
            print(f"error: target file does not exist: {path}", file=sys.stderr)
            print("hint: pass --allow-missing if the worker should CREATE the file", file=sys.stderr)
            sys.exit(1)


def expand_imports(target, workdir):
    imports = []
    try:
        result = subprocess.run(
            ["rg", "--no-heading", "-n", "-o",
             r"^import\s+(?:[^'\"]+from\s+)?['\"]([^'\"]+)['\"]",
             target],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                m = re.search(r"['\"]([^'\"]+)['\"]", line)
                if not m:
                    continue
                spec = m.group(1)
                if spec.startswith("."):
                    base = os.path.dirname(target)
                    resolved = os.path.normpath(os.path.join(base, spec))
                    for ext in [".ts", ".tsx", ".js", ".jsx", "/index.ts", "/index.tsx"]:
                        candidate = resolved + ext
                        if os.path.exists(candidate):
                            imports.append(os.path.abspath(candidate))
                            break
                elif spec.startswith("@/") or spec.startswith("~/"):
                    alias = spec[2:]
                    candidate = os.path.join(workdir, "src", alias)
                    for ext in [".ts", ".tsx", ".js", ".jsx", "/index.ts", "/index.tsx"]:
                        c = candidate + ext
                        if os.path.exists(c):
                            imports.append(os.path.abspath(c))
                            break
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return imports[:10]


def build_out_of_scope(workdir):
    return [os.path.join(workdir, p) for p in FORBIDDEN_PATHS]


def render_command_md(intent, target, tier, workdir, route, validation, read_from, out_of_scope):
    dispatch_id = str(uuid.uuid4())
    codex_profile, opencode_model = TIER_TABLE[tier]
    if codex_profile in ("tier-0-dsv4", "tier-2-kimi"):
        worker_profile = opencode_model
    else:
        worker_profile = codex_profile
    max_runtime = TIER_MAX_RUNTIME[tier]

    read_from_block = "\n".join(f"  - {p}" for p in read_from) or "  - (auto-discovery failed)"
    oos_block = "\n".join(f"  - {p}" for p in out_of_scope)
    validation_block = "\n".join(
        f"- `{cmd}`: exit {ec}" for cmd, ec in validation
    ) or "- (none specified)"

    md = f"""# COMMAND-SLIM — Minimal Worker Contract

## 1. IDENTITY

```
dispatch_id:      {dispatch_id}
tier:             {tier}
worker_profile:   {worker_profile}
spawned_by:       aes-summon (or Fable 5)
campaign:         fable5-non-compiler-routes
route:            {route or '(none)'}
workdir:          {workdir}
max_runtime_sec:  {max_runtime}
```

## 2. MISSION

```
{intent}
```

## 3. SCOPE

```
write_to:
  - {target}

read_from (evidence sources):
{read_from_block}

out_of_scope (MUST NOT touch):
{oos_block}
```

## 4. MUTATIONS

```
1. (auto-derived from intent — refine manually if needed)
   Read {target} and apply the smallest change that satisfies the MISSION.
2. Do not touch any file outside write_to.
```

## 5. VALIDATION

```
{validation_block}
```

## 6. OUTPUT CONTRACT

```
On success:
  print "COMPLETE: <1-sentence summary of what changed>"
  exit 0

On halt:
  print "HALT: <reason — specific file:line or missing input>"
  exit non-zero (1 = generic halt, 2 = scope drift, 3 = validation failed)
```

## EXECUTION LAWS (immutable)

- **NO_INFERENCE** — do not invent missing requirements, files, APIs.
- **NO_SCOPE_DRIFT** — do not modify files outside `write_to`.
- **NO_PARTIAL_OUTPUT** — do not claim COMPLETE unless all VALIDATION commands pass.
- **EVIDENCE_REQUIRED** — every COMPLETE claim must cite the changed files (relative paths) and the validation output.
- **DETERMINISTIC_ORDER** — prefer smallest safe change set in dependency order.
- **PRESERVE_EXISTING_CONTRACTS** — do not break public APIs, schemas, tests, or runtime contracts.

## BOUNDARIES (HALT conditions)

HALT immediately if any boundary is crossed:
- `WRITE_TO_FILES_OUT_OF_SCOPE` — touched a file not in `write_to`
- `MISSING_REQUIRED_CONTEXT` — read_from path doesn't exist
- `VALIDATION_BLOCKED` — validation command can't run (env issue)
- `TEST_FAILURE_UNRESOLVED` — validation command exits non-zero
- `DESTRUCTIVE_OPERATION_REQUIRED` — would need `rm -rf`, `git push --force`, etc.

## Reference

- Tier table: aes-summon agent's TIER TABLE section
- Tier profiles: ~/.codex/tier-{{0,1,2,3}}-*.config.toml + ~/.codex/convergence.config.toml
- Campaign charter: iqne/.agent/commands/fable5-non-compiler-routes.md
- Full Command skill: process/command/SKILL.md (for architect handoffs)
"""
    return md


def main():
    parser = argparse.ArgumentParser(
        description="Generate a slim COMMAND.md for the dispatch lane.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--intent", required=True, help="One-sentence mission")
    parser.add_argument("--target", required=True, help="File path (relative to workdir or absolute)")
    parser.add_argument("--out", required=True, help="Output path for the generated COMMAND.md")
    parser.add_argument("--tier", required=True, choices=sorted(TIER_TABLE.keys()),
                        help="Tier classification (Fable 5 must specify)")
    parser.add_argument("--workdir", required=True, help="Working directory (usually the iqne worktree)")
    parser.add_argument("--route", help="Route scope, e.g., /about (optional)")
    parser.add_argument("--validation", nargs=2, action="append", metavar=("CMD", "EXIT_CODE"),
                        help="Validation command + expected exit code (repeat for multiple)")
    parser.add_argument("--allow-missing", action="store_true",
                        help="Allow target file to not exist (worker will CREATE it)")
    parser.add_argument("--no-import-expansion", action="store_true",
                        help="Skip auto-discovery of imports for read_from")
    args = parser.parse_args()

    if args.tier not in TIER_TABLE:
        print(f"error: tier must be one of {sorted(TIER_TABLE.keys())}", file=sys.stderr)
        sys.exit(1)

    secrets = detect_secrets(args.intent)
    if secrets:
        print(f"error: intent contains secret patterns: {secrets}", file=sys.stderr)
        sys.exit(1)

    if not args.validation:
        print("error: --validation is required at least once", file=sys.stderr)
        sys.exit(1)

    target_abs = normalize_path(args.target, args.workdir)
    workdir_abs = os.path.abspath(args.workdir)

    check_path_exists(target_abs, args.allow_missing)

    read_from = [target_abs]
    if not args.no_import_expansion:
        imports = expand_imports(target_abs, workdir_abs)
        for imp in imports:
            if imp not in read_from:
                read_from.append(imp)
    read_from = read_from[:10]

    out_of_scope = build_out_of_scope(workdir_abs)

    filled = render_command_md(
        intent=args.intent,
        target=target_abs,
        tier=args.tier,
        workdir=workdir_abs,
        route=args.route,
        validation=args.validation,
        read_from=read_from,
        out_of_scope=out_of_scope,
    )

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        f.write(filled)

    out_size = os.path.getsize(args.out)
    codex_profile, opencode_model = TIER_TABLE[args.tier]
    dispatch_match = re.search(r"dispatch_id:\s+(\S+)", filled)
    dispatch_id_str = dispatch_match.group(1) if dispatch_match else "(see file)"
    print(f"OK: wrote {args.out} ({out_size} bytes)")
    print(f"   dispatch_id:  {dispatch_id_str}")
    print(f"   tier:         {args.tier}")
    print(f"   profile:      {codex_profile}")
    print(f"   opencode:     {opencode_model}")
    print(f"   target:       {target_abs}")
    print(f"   read_from:    {len(read_from)} file(s)")
    print(f"   validation:   {len(args.validation)} command(s)")


if __name__ == "__main__":
    main()
