#!/usr/bin/env python3
"""
ATDD Spec Generator — creates structured Acceptance Test-Driven Development
specification documents from a brief problem description.

Usage:
  # Interactive (asks questions)
  python3 scripts/generate.py

  # From a markdown brief file
  python3 scripts/generate.py --brief defects.md --output specs/repair.atdd.md

  # Direct CLI (all fields)
  python3 scripts/generate.py \\
    --name kimi-streaming \\
    --seam bridge-streaming \\
    --problem "Kimi SSE stream emits double response.completed..." \\
    --impact "Codex hangs on duplicate terminal event" \\
    --context "Go llm-gateway bridge translates Codex Responses API..." \\
    --runtime "Go 1.23" \\
    --frameworks "stdlib net/http, encoding/json" \\
    --dependencies "OpenCode Kimi-K2.6 endpoint" \\
    --scenarios 4 \\
    --coverage 80 \\
    --output .agent/specs/atdd/repair.atdd.md
"""

import argparse
import os
import sys
from datetime import datetime


TEMPLATE = """# ATDD Specification: {name}

## 1. Problem Statement

- **Context:** {context}
- **The Gap / Bug:** {bug}
- **Impact:** {impact}

## 2. System Constraints & Environment

- **Runtime:** {runtime}
- **Frameworks:** {frameworks}
- **External Dependencies:** {dependencies}

## 3. Black-Box Test Cases (The "Green" Gates)

{scenarios}
## 4. Definition of Done (DoD)

- [ ] 100% of the above Scenarios implemented as automated integration tests.
- [ ] Regression testing passes (existing features remain unbroken).
- [ ] Code coverage for the affected modules meets or exceeds {coverage}%.
"""


def prompt(question, default=""):
    """Ask the user a question and return their answer."""
    if default:
        result = input(f"{question} [{default}]: ").strip()
        return result if result else default
    return input(f"{question}: ").strip()


def scenario_block(index, title, given, when_desc, then_desc):
    """Format a single scenario block."""
    return (
        f"### Scenario {index}: {title}\n"
        f"\n"
        f"- **Given:** {given}\n"
        f"- **When:** {when_desc}\n"
        f"- **Then:** {then_desc}\n"
        f"\n"
    )


def interactive_mode():
    """Run in interactive prompt mode."""
    print("=== ATDD Spec Generator ===\n")
    name = prompt("Spec name (e.g., kimi-streaming)")
    seam = prompt("Seam boundary (e.g., bridge-streaming)", default=name)
    context = prompt("Current system context (2-3 sentences)")
    bug = prompt("The gap or bug (what's broken or missing)")
    impact = prompt("Impact if not fixed")
    runtime = prompt("Runtime", default="Go 1.23")
    frameworks = prompt("Frameworks", default="stdlib")
    dependencies = prompt("External dependencies", default="None")

    try:
        num_scenarios = int(prompt("Number of test scenarios", default="4"))
    except ValueError:
        num_scenarios = 4

    scenarios = []
    print(f"\n--- Enter {num_scenarios} Scenarios ---")
    for i in range(1, num_scenarios + 1):
        print(f"\nScenario {i}:")
        title = prompt("  Title")
        given = prompt("  Given")
        when_desc = prompt("  When")
        then_desc = prompt("  Then")
        scenarios.append(scenario_block(i, title, given, when_desc, then_desc))

    try:
        coverage = int(prompt("Coverage target %", default="80"))
    except ValueError:
        coverage = 80

    output = prompt("Output path", default=f".agent/specs/atdd/{seam}.atdd.md")

    content = TEMPLATE.format(
        name=name,
        context=context,
        bug=bug,
        impact=impact,
        runtime=runtime,
        frameworks=frameworks,
        dependencies=dependencies,
        scenarios="".join(scenarios),
        coverage=coverage,
    )

    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    with open(output, "w") as f:
        f.write(content)

    print(f"\n✓ Spec written to {output}")
    return output


def brief_mode(brief_path, output):
    """Parse a simple markdown brief and generate the spec.

    The brief is a minimal markdown file with sections like:
    # Defect Name
    Context: ...
    Bug: ...
    Impact: ...
    Scenarios:
    - Title: ... Given: ... When: ... Then: ...
    """
    with open(brief_path) as f:
        text = f.read()

    lines = text.strip().split("\n")
    name = brief_path.split("/")[-1].replace(".md", "").replace("_", "-")

    # Parse simple key: value pairs
    fields = {
        "name": name,
        "context": "",
        "bug": "",
        "impact": "",
        "runtime": "Go 1.23",
        "frameworks": "stdlib",
        "dependencies": "None",
        "coverage": "80",
    }

    current_key = None
    scenarios_raw = []
    in_scenarios = False

    for line in lines:
        line_stripped = line.strip()
        if line_stripped.startswith("# ATDD") or line_stripped.startswith("# ") and not line_stripped.startswith("## "):
            if not line_stripped.startswith("# ATDD"):
                fields["name"] = line_stripped.lstrip("# ").strip()
            continue
        if line_stripped.startswith("Scenarios:") or line_stripped.startswith("## Scenarios"):
            in_scenarios = True
            continue
        if in_scenarios and line_stripped.startswith("## "):
            in_scenarios = False

        if not in_scenarios and ":" in line_stripped:
            key, _, val = line_stripped.partition(":")
            key_lower = key.strip().lower()
            val = val.strip()
            if val:
                key_map = {
                    "context": "context",
                    "bug": "bug",
                    "the gap / bug": "bug",
                    "gap": "bug",
                    "impact": "impact",
                    "runtime": "runtime",
                    "frameworks": "frameworks",
                    "dependencies": "dependencies",
                    "external dependencies": "dependencies",
                    "coverage": "coverage",
                }
                mapped = key_map.get(key_lower)
                if mapped:
                    fields[mapped] = val

        if in_scenarios and line_stripped.startswith("- ") or (in_scenarios and line_stripped.startswith("* ")):
            scenarios_raw.append(line_stripped.lstrip("- *").strip())

    # Build scenario blocks from raw lines or prompt for them
    scenarios = []
    if scenarios_raw:
        for i, raw in enumerate(scenarios_raw, 1):
            # Try to parse structured scenario from brief
            parts = raw.split("Given:")
            title = parts[0].replace("Title:", "").strip() if "Title:" in parts[0] else f"Scenario {i}"
            given = ""
            when_desc = ""
            then_desc = ""
            if len(parts) > 1:
                given_parts = parts[1].split("When:")
                given = given_parts[0].strip()
                if len(given_parts) > 1:
                    when_then = given_parts[1].split("Then:")
                    when_desc = when_then[0].strip()
                    then_desc = when_then[1].strip() if len(when_then) > 1 else ""
            scenarios.append(scenario_block(i, title, given, when_desc, then_desc))
    else:
        scenarios.append(scenario_block(
            1, "Primary success path",
            "The system is in its initial state",
            "The action is performed",
            "The expected result is produced"
        ))

    content = TEMPLATE.format(
        name=fields["name"],
        context=fields["context"],
        bug=fields["bug"],
        impact=fields["impact"],
        runtime=fields["runtime"],
        frameworks=fields["frameworks"],
        dependencies=fields["dependencies"],
        scenarios="".join(scenarios) if scenarios else "(define scenarios below)\n\n",
        coverage=fields["coverage"],
    )

    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    with open(output, "w") as f:
        f.write(content)

    print(f"✓ Spec written to {output}")
    return output


def cli_mode(args):
    """Build spec from CLI arguments."""
    scenarios = []
    for i in range(1, args.scenarios + 1):
        title = getattr(args, f"scenario_{i}_title", None) or f"Scenario {i}"
        given = getattr(args, f"scenario_{i}_given", None) or "The system is in its initial state"
        when_desc = getattr(args, f"scenario_{i}_when", None) or "The action is performed"
        then_desc = getattr(args, f"scenario_{i}_then", None) or "The expected result is produced"
        scenarios.append(scenario_block(i, title, given, when_desc, then_desc))

    content = TEMPLATE.format(
        name=args.name,
        context=args.context,
        bug=args.problem,
        impact=args.impact,
        runtime=args.runtime,
        frameworks=args.frameworks,
        dependencies=args.dependencies,
        scenarios="".join(scenarios),
        coverage=args.coverage,
    )

    output = args.output or f".agent/specs/atdd/{args.name}.atdd.md"
    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    with open(output, "w") as f:
        f.write(content)

    print(f"✓ Spec written to {output}")
    return output


def main():
    parser = argparse.ArgumentParser(
        description="Generate an ATDD specification document.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Mode flags
    mode = parser.add_argument_group("mode (pick one)")
    mode.add_argument("--brief", help="Read a markdown brief file instead of CLI args")

    # Spec fields
    spec = parser.add_argument_group("spec fields")
    spec.add_argument("--name", help="Spec name (e.g., kimi-streaming)")
    spec.add_argument("--seam", help="Seam/boundary name (e.g., bridge-streaming)")
    spec.add_argument("--problem", "-b", help="The bug or gap")
    spec.add_argument("--impact", help="Impact if not fixed")
    spec.add_argument("--context", "-c", help="System context (2-3 sentences)")
    spec.add_argument("--runtime", help="Runtime (e.g., Go 1.23)", default="Go 1.23")
    spec.add_argument("--frameworks", help="Frameworks", default="stdlib")
    spec.add_argument("--dependencies", help="External dependencies", default="None")
    spec.add_argument("--scenarios", type=int, default=4, help="Number of scenarios")
    spec.add_argument("--coverage", type=int, default=80, help="Coverage target %")
    spec.add_argument("--output", "-o", help="Output path")

    args = parser.parse_args()

    if args.brief:
        output = args.output or f".agent/specs/atdd/{os.path.basename(args.brief).replace('.md', '')}.atdd.md"
        brief_mode(args.brief, output)
    elif args.name and args.problem:
        cli_mode(args)
    else:
        interactive_mode()


if __name__ == "__main__":
    main()
