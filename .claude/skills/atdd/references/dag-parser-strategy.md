# Parser Strategy

`scripts/generate.py` parses `tasks.md` with regex, not full markdown AST.
This document explains why and the trade-offs.

## Why regex, not mistune

The spec-generation skill recommends `frontmatter + mistune` for production
parsing of complex multi-wave specs. We inherit that capability but defer
frontmatter adoption for `atdd-dag-generation` v1.

Reasons:

1. **Validators are scaffolded, not run through a parser at runtime.** The
   scaffolder is a build-time tool. Once `validate-<task-id>.mjs` files
   exist, the Kanban dispatcher invokes them as Node.js scripts. No
   runtime parsing of `tasks.md` is needed.

2. **Regex on a constrained grammar is simpler and faster.** The task
   shape is rigid (checkbox + ID + title + body). Mistune gives us a
   generic markdown parser; regex gives us a domain-specific extractor
   that errors loudly when the shape is wrong.

3. **The scaffolder is a one-shot tool.** It runs once per spec to emit
   validator files. Re-parsing on every spec edit is fine because the
   cost is microseconds.

4. **The downstream Kanban dispatcher uses mistune on the lane body
   (the markdown between lane boundaries) to extract directives, ops,
   and task descriptions.** That parsing is the runtime concern. The
   scaffolder's job is just to bind one validator per task ID.

## What the regex extracts

| Field | Regex | Notes |
|---|---|---|
| Task ID (with phase) | `TITLE_WITH_PHASE_RE` | Preferred: phase in parens |
| Task ID (without phase) | `TITLE_BARE_RE` | Phase pulled from body |
| Write Surface | `WRITE_SURFACE_RE` | Multi-line, may have backticks |
| TDD Phase | `TDD_PHASE_RE` | Body fallback if title doesn't have it |
| Executable | `EXECUTABLE_RE` | The `pnpm agent:validate:<task-id>` line |
| Wave | `TASK_ID_RE` | Numeric prefix |
| Lane | `TASK_ID_RE` | Letter prefix |

## What the regex ignores

- **Scenario bodies** — the Given/When/Then sections inside a task are
  not extracted. The implementer writes the assertion in the validator
  script, the human reads the scenario in `tasks.md`.
- **Directives and Op Groups** — narrative structure preserved in the
  spec for human reading. The scaffolder ignores them; the validator
  doesn't care which directive/Op Group a task belongs to.
- **Frontmatter** — not yet adopted. If the spec author wants machine
  readability at runtime, they can add YAML frontmatter and the
  Kanban dispatcher's enqueuer will use it.

## Body extraction

The "body" of a task is the text between this task's checkbox and the
next checkbox at the same indent level (or the next h1-h4 heading).
This is the simplest definition that works for both:

- Tasks separated by blank lines (most common)
- Tasks separated by a heading boundary (e.g., a new Wave)

If a task body extends across multiple checkboxes (e.g., a `Definition
of Done` checklist is followed by another task), the regex may
incorrectly include the next task's body. The implementer can fix this
by adding a blank line or heading between tasks.

## Audit mode

`--audit` reads the parsed task list and confirms a corresponding
`validate-<task-id>.mjs` exists at the output path. This is the
scaffolder's quality gate — run it after every spec edit to catch
drift.

```bash
# After editing tasks.md, regenerate validators and audit
python3 scripts/generate.py --spec .kiro/specs/<slug>/tasks.md --output .agent/tools/
python3 scripts/generate.py --spec .kiro/specs/<slug>/tasks.md --output .agent/tools/ --audit
# exit 0 = all good, exit 1 = missing validators
```

## When to switch to mistune

If the spec author needs to:

- Extract scenario bodies programmatically (e.g., to auto-generate
  test stubs in the target language)
- Walk the Directive/Op Group hierarchy for the enqueuer
- Generate a JSON manifest of the spec for downstream tools

Then add a mistune pass on top of the regex pass. The regex identifies
task boundaries; mistune walks the body to extract scenario content.

For v1, the scaffolded validator is the runtime contract. The
implementer fills it in. Spec author writes scenarios as Markdown.
Both are human-readable, mechanically checkable.
