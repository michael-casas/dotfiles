---
name: command-slim
description: Slim COMMAND generator for the dispatch lane. Takes (intent, file_target) and writes a 2-3KB minimal COMMAND.md to disk. Replaces the 1.4KB process/command SKILL.md (which is for architects) with a 5-section template for haiku workers. Used by Fable 5, aes-summon, and any agent that needs to dispatch bounded work to a tier-aware runtime.
version: 1.0.0
author: Django
license: MIT
metadata:
  hermes:
    tags: [delegation, command, dispatch-lane, haiku]
    priority: high
    parent: process/command
---

# Command Slim — Dispatch-Lane COMMAND Generator

The dispatch lane (haiku workers) does not need the full `process/command`
SKILL.md (1.4KB, architect-oriented, handoff-document-pattern). It
needs ONE thing: a 5-section minimal COMMAND.md that takes (intent,
file_target) and produces a tight contract the worker can read in one
shot.

## The 5-Section Minimal COMMAND

```yaml
# 1. IDENTITY
#    dispatch_id: <uuid>
#    tier: <tier-0|tier-1|tier-2|tier-3|tier-4>
#    worker_profile: <codex profile or opencode model>
#    spawned_by: aes-summon (or Fable 5 direct)
#
# 2. MISSION
#    <intent — 1 sentence, what the worker must produce>
#
# 3. SCOPE
#    write_to: <list of absolute file paths the worker MAY touch>
#    read_from: <list of absolute paths the worker SHOULD read for evidence>
#    out_of_scope: <list of paths the worker MUST NOT touch>
#
# 4. MUTATIONS
#    <bounded operations — what the worker should change>
#    - e.g., "add 'cta' node type to ContentNode.contract.ts:87"
#    - e.g., "add 'media-with-aside' variant to Section.contract.ts:124"
#
# 5. VALIDATION
#    - <command>: <expected exit code>
#    - e.g., "pnpm typecheck:app": 0
#    - e.g., "pnpm agent:compare:convergence": 0 with score >= 0.92
#
# 6. OUTPUT CONTRACT
#    On success: print "COMPLETE: <1-sentence summary>" and exit 0
#    On halt: print "HALT: <reason>" and exit non-zero
```

The full template with all 6 sections lives at
`templates/COMMAND-SLIM.md` in this skill's directory.

## Usage

```bash
python3 ~/.dotfiles/opencode/skills/command-slim/scripts/command-generate.py \
  --intent "Add 'cta' node type to ContentNode.contract.ts for the /about S04 section" \
  --target src/contracts/content/ContentNode.contract.ts \
  --out /tmp/COMMAND-s04-cta.md \
  --tier tier-2 \
  --workdir /path/to/iqne \
  --validation "pnpm typecheck:app" "0" \
  --validation "pnpm agent:compare:convergence --route /about" "0"
```

The script:
1. Reads the template at `templates/COMMAND-SLIM.md`
2. Fills in: dispatch_id (uuidgen), intent, target (normalized to
   absolute path), tier, workdir, validation commands
3. Auto-derives `out_of_scope` from the campaign charter's forbidden
   write list (theme.css out of ROLE anchors, scoped CSS, new section
   types, hand-rolled JSX in `src/app/components/sections/*`)
4. Auto-derives `read_from` from the file_target's import graph (1-hop
   expansion via ripgrep)
5. Writes a 2-3KB minimal COMMAND.md to the `--out` path

## When to use command-slim vs process/command

| Use case | Skill | Why |
|---|---|---|
| Architect → Implementer handoff (Opus → Sonnet) | `process/command` | full document hierarchy, CRITERION.md, PLAN.md pattern |
| Haiku dispatch lane (tier-0/1/2/3/4 work) | `command-slim` | 5-section, no handoff doc, fast generation |
| `/goal` campaign charter (Fable 5) | `process/command` (evidence-grounded-goal-charter template) | multi-phase, ATDD, pre-flight |
| Single bounded mutation dispatched to a worker | `command-slim` | this is what aes-summon needs |

## Hard rules

- **Always use the template, never write COMMAND.md by hand.** The
  script is the only source of truth.
- **Never include secrets in the intent or scope.** The script
  rejects prompts with `password`, `token`, `api_key`, `secret`,
  `.env`, `BEGIN PRIVATE KEY` patterns.
- **Never set `tier` to something not in the tier table.** The
  script enforces `tier ∈ {tier-0, tier-1, tier-2, tier-3, tier-4}`.
- **Always include at least 1 validation command.** The script
  requires `--validation` to be passed at least once.

## Reference

- Full Command skill: `process/command/SKILL.md`
- Tier table: `aes-summon` agent's TIER TABLE section
- Campaign charter: `iqne/.agent/commands/fable5-non-compiler-routes.md`
- Tier profiles: `~/.codex/tier-{0,1,2,3,m3}-*.config.toml` + `~/.codex/convergence.config.toml`
