---
name: ticketing
description: Transform user intent into structured Jira tickets. Epics are technical Feature Charters; Tasks are Directives; Subtasks are evidence-based fulfilment requirements; Bugs use the canonical Directive description with reproduction and regression proof. Use to draft, refine, split, create, or update tickets, not to execute their implementation.
metadata:
  version: "1.0.0"
---

# Ticketing — Claude Code

Read applicable CLAUDE.md, AGENTS.md and README.md. Use Jira connectors and task/todo tools actually exposed in Claude Code; do not require Codex or Pi APIs.

Read [the authoring contract](references/authoring.md), then classify and draft from evidence. Prepare the Epic batch first; deeply inspect each Epic before writing its Tasks. Each Subtask names one parent-Directive obligation and closing evidence. Use [the Epic template](templates/EPIC.md) for features and [the Directive template](templates/DIRECTIVE.md) for child Tasks and Bugs. Bug Directives use Class: fix and include repro, actual/expected behavior, impact, Severity and regression obligations.

Distinguish a publishable ticket draft from an issued executable Directive. Missing execution bindings are explicit dispatch prerequisites, never fabricated values. Publish only within the user's Jira write authority, read back the result, and report actual issue links. Otherwise return complete drafts and unresolved decisions.

Hand approved inputs to the sibling [Han Solo skill](../han-solo/SKILL.md) for execution planning and delivery. This authoring skill does not launch agents or grant implementation, merge, deployment or production authority.

## Source alignment

`~/.claude/skills` is canonical. `~/.codex/skills`, `~/.agents/skills`, `~/.pi/agent/skills` and `~/.dotfiles/skills` mirror it, except intentional harness-specific lines (for example Claude Code versus Codex tool names), which stay. Keep references/authoring.md identical across installed mirrors. EPIC.md mirrors Han Solo's canonical Epic template. DIRECTIVE.md mirrors ~/.claude/skills/batdd/templates/DIRECTIVE.md. Update distributed templates together; resolve drift before issuing work. This installation is self-contained and does not require Pi.
