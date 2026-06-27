#!/usr/bin/env python3
"""
atdd-dag-generation scaffolder.

Emits one .agent/tools/validate-<task-id>.mjs per task ID declared in tasks.md,
filling in the Write Surface and TDD Phase from the parsed spec.

Usage:
    # Parse tasks.md and emit all validators
    python3 generate.py --spec .kiro/specs/my-feature/tasks.md --output .agent/tools/

    # Audit mode: confirm every declared task ID has a validator
    python3 generate.py --spec .kiro/specs/my-feature/tasks.md --output .agent/tools/ --audit

    # Single-task mode
    python3 generate.py --spec .kiro/specs/my-feature/tasks.md --output .agent/tools/ --task-id W2.A.1.1

    # Wire pnpm scripts into package.json
    python3 generate.py --spec .kiro/specs/my-feature/tasks.md --output .agent/tools/ --wire-package-json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# Task ID format: W<wave>.<lane>.<directive>.<seq>
# Phase may be in the title line (preferred) or in the body's TDD Phase field
TASK_ID_RE = re.compile(r"\bW(\d+)\.([A-Z]+)\.(\d+)\.(\d+)\b")
WRITE_SURFACE_RE = re.compile(r"\*\*Write Surface:\*\*\s*(.+?)(?=\n\s*-|\n\s*###|\n\s*\*\*|\Z)", re.DOTALL)
TDD_PHASE_RE = re.compile(r"\*\*TDD Phase:\*\*\s*(\S+)")
EXECUTABLE_RE = re.compile(r"\*\*Executable:\*\*\s*`?([^`\n]+)`?")
# Title with phase in parens (preferred)
TITLE_WITH_PHASE_RE = re.compile(
    r"^- \[ \] (W\d+\.[A-Z]+\.\d+\.\d+)\s+(.+?)\s*\((RED|GREEN|REFACTOR|N/A)\)\s*$",
    re.MULTILINE,
)
# Title without phase — phase extracted from body
TITLE_BARE_RE = re.compile(
    r"^- \[ \] (W\d+\.[A-Z]+\.\d+\.\d+)\s+(.+?)\s*$",
    re.MULTILINE,
)


@dataclass
class TaskSpec:
    task_id: str
    title: str
    tdd_phase: str
    write_surface: list[str] = field(default_factory=list)
    executable: Optional[str] = None
    wave: int = 0
    lane: str = ""

    @property
    def safe_id(self) -> str:
        return self.task_id.replace(".", "-")


def parse_tasks_md(path: Path) -> list[TaskSpec]:
    """Parse a tasks.md file and extract every task ID with its metadata.

    Looks for checkbox lines matching the task ID format and pulls the
    adjacent Write Surface, TDD Phase, and Executable fields from the same body.
    """
    text = path.read_text(encoding="utf-8")
    tasks: list[TaskSpec] = []
    seen_ids: set[str] = set()

    # Split by task checkboxes while preserving the body for context
    # A task body extends from its checkbox to the next checkbox at the same
    # indent level (or to the next heading at the same or higher level).
    for match in TITLE_WITH_PHASE_RE.finditer(text):
        task_id = match.group(1)
        title = match.group(2).strip()
        phase = match.group(3)

        if task_id in seen_ids:
            continue
        seen_ids.add(task_id)

        # Find the body following the checkbox
        body_start = match.end()
        # Find next checkbox or h2/h3/h4 at start of line
        next_match = re.search(
            r"^- \[ \] W\d+\.[A-Z]+\.\d+\.\d+|^(#{1,4}) ",
            text[body_start:],
            re.MULTILINE,
        )
        body = text[body_start : body_start + next_match.start()] if next_match else text[body_start:]

        # Extract Write Surface
        write_surface: list[str] = []
        ws_match = WRITE_SURFACE_RE.search(body)
        if ws_match:
            raw = ws_match.group(1)
            for line in raw.split("\n"):
                line = line.strip().lstrip("-").strip()
                if not line:
                    continue
                line = line.replace("`", "")
                write_surface.append(line)

        # Extract Executable
        executable = None
        exec_match = EXECUTABLE_RE.search(body)
        if exec_match:
            executable = exec_match.group(1).strip()

        # Parse wave/lane from task ID
        id_match = TASK_ID_RE.match(task_id)
        wave = int(id_match.group(1)) if id_match else 0
        lane = id_match.group(2) if id_match else ""

        tasks.append(
            TaskSpec(
                task_id=task_id,
                title=title,
                tdd_phase=phase,
                write_surface=write_surface,
                executable=executable,
                wave=wave,
                lane=lane,
            )
        )

    # Second pass: title without phase in parens. Phase comes from body.
    for match in TITLE_BARE_RE.finditer(text):
        task_id = match.group(1)
        title = match.group(2).strip()

        if task_id in seen_ids:
            continue
        seen_ids.add(task_id)

        # Find body
        body_start = match.end()
        next_match = re.search(
            r"^- \[ \] W\d+\.[A-Z]+\.\d+\.\d+|^(#{1,4}) ",
            text[body_start:],
            re.MULTILINE,
        )
        body = text[body_start : body_start + next_match.start()] if next_match else text[body_start:]

        # Phase from body
        phase = "N/A"
        phase_match = TDD_PHASE_RE.search(body)
        if phase_match:
            phase = phase_match.group(1).strip()

        # Write Surface
        write_surface: list[str] = []
        ws_match = WRITE_SURFACE_RE.search(body)
        if ws_match:
            raw = ws_match.group(1)
            for line in raw.split("\n"):
                line = line.strip().lstrip("-").strip()
                if not line:
                    continue
                line = line.replace("`", "")
                write_surface.append(line)

        # Executable
        executable = None
        exec_match = EXECUTABLE_RE.search(body)
        if exec_match:
            executable = exec_match.group(1).strip()

        id_match = TASK_ID_RE.match(task_id)
        wave = int(id_match.group(1)) if id_match else 0
        lane = id_match.group(2) if id_match else ""

        tasks.append(
            TaskSpec(
                task_id=task_id,
                title=title,
                tdd_phase=phase,
                write_surface=write_surface,
                executable=executable,
                wave=wave,
                lane=lane,
            )
        )

    return tasks


def render_validator(task: TaskSpec, template: str) -> str:
    """Render a validator script for one task using the template."""
    write_surface_js = ",\n  ".join(f"'{p}'" for p in task.write_surface) if task.write_surface else ""
    return (
        template
        .replace("<TASK_ID>", task.task_id)
        .replace("<TASK_TITLE>", task.title.replace("'", "\\'"))
        .replace("<TDD_PHASE>", task.tdd_phase)
        .replace(
            "  // '<relative-path-to-file-1>',\n  // '<relative-path-to-file-2>',",
            f"  {write_surface_js}," if write_surface_js else "  // (no write surface declared)",
        )
    )


def emit_validators(tasks: list[TaskSpec], output_dir: Path, template: str) -> list[Path]:
    """Emit one .mjs file per task. Returns the list of paths written."""
    output_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for task in tasks:
        path = output_dir / f"validate-{task.task_id}.mjs"
        path.write_text(render_validator(task, template), encoding="utf-8")
        path.chmod(0o755)
        written.append(path)
    return written


def audit_validators(tasks: list[TaskSpec], output_dir: Path) -> tuple[int, list[str]]:
    """Confirm every declared task ID has a validator file. Returns (missing_count, missing_list)."""
    missing: list[str] = []
    for task in tasks:
        path = output_dir / f"validate-{task.task_id}.mjs"
        if not path.exists():
            missing.append(task.task_id)
    return len(missing), missing


def wire_package_json(tasks: list[TaskSpec], package_json_path: Path, dry_run: bool = False) -> dict:
    """Add pnpm scripts for every task's validator to package.json.

    Returns the diff (added scripts) so the caller can print what changed.
    """
    if not package_json_path.exists():
        return {"error": f"package.json not found at {package_json_path}"}

    pkg = json.loads(package_json_path.read_text(encoding="utf-8"))
    scripts = pkg.setdefault("scripts", {})
    added: dict[str, str] = {}

    for task in tasks:
        script_key = f"agent:validate:{task.task_id}"
        if script_key not in scripts:
            command = f"node .agent/tools/validate-{task.task_id}.mjs"
            added[script_key] = command

    if added and not dry_run:
        scripts.update(added)
        package_json_path.write_text(
            json.dumps(pkg, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    return {"added": added, "dry_run": dry_run}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="atdd-dag-generation scaffolder: emit .agent/tools/validate-<task-id>.mjs per task ID."
    )
    parser.add_argument("--spec", type=Path, required=True, help="Path to tasks.md")
    parser.add_argument("--output", type=Path, required=True, help="Output directory for validators (e.g. .agent/tools/)")
    parser.add_argument("--template", type=Path, default=None, help="Path to validator template (defaults to assets/validator.template.mjs)")
    parser.add_argument("--task-id", type=str, default=None, help="Single-task mode: only emit this task ID")
    parser.add_argument("--audit", action="store_true", help="Audit mode: confirm every task ID has a validator")
    parser.add_argument("--wire-package-json", action="store_true", help="Add pnpm scripts to package.json")
    parser.add_argument("--package-json", type=Path, default=Path("package.json"), help="Path to package.json (default: ./package.json)")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be done without writing")
    args = parser.parse_args()

    if not args.spec.exists():
        print(f"❌ Spec file not found: {args.spec}", file=sys.stderr)
        return 1

    # Load template
    if args.template:
        template_path = args.template
    else:
        template_path = Path(__file__).parent.parent / "assets" / "validator.template.mjs"
    if not template_path.exists():
        print(f"❌ Validator template not found: {template_path}", file=sys.stderr)
        return 1
    template = template_path.read_text(encoding="utf-8")

    # Parse
    tasks = parse_tasks_md(args.spec)
    if not tasks:
        print(f"⚠️  No tasks found in {args.spec}", file=sys.stderr)
        return 1

    if args.task_id:
        tasks = [t for t in tasks if t.task_id == args.task_id]
        if not tasks:
            print(f"❌ Task {args.task_id} not found in spec", file=sys.stderr)
            return 1

    # Audit mode
    if args.audit:
        missing_count, missing = audit_validators(tasks, args.output)
        if missing_count == 0:
            print(f"✅ All {len(tasks)} task(s) have validators at {args.output}")
            return 0
        else:
            print(f"❌ {missing_count}/{len(tasks)} task(s) missing validators:")
            for tid in missing:
                print(f"   - {tid} → {args.output}/validate-{tid}.mjs")
            return 1

    # Emit
    if args.dry_run:
        print(f"Would emit {len(tasks)} validator(s) to {args.output}:")
        for task in tasks:
            print(f"   - validate-{task.task_id}.mjs")
            for f in task.write_surface:
                print(f"       Write surface: {f}")
        return 0

    written = emit_validators(tasks, args.output, template)
    print(f"✅ Emitted {len(written)} validator(s) to {args.output}/")
    for path in written:
        print(f"   - {path.name}")

    # Wire package.json
    if args.wire_package_json:
        result = wire_package_json(tasks, args.package_json)
        if "error" in result:
            print(f"⚠️  {result['error']}", file=sys.stderr)
        else:
            added = result["added"]
            if added:
                print(f"\n✅ Added {len(added)} script(s) to {args.package_json}:")
                for key, cmd in added.items():
                    print(f'   "{key}": "{cmd}"')
            else:
                print(f"\n✓ All {len(tasks)} script(s) already present in {args.package_json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
