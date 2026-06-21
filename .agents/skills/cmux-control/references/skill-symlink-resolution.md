# Skill Symlink Resolution Troubleshooting

## The Problem

Agents (Claude Code, Codex, Hermes) load skills from `~/.<agent>/skills/`. When these are symlinked to share a single source of truth (e.g. from dotfiles), **circular symlink chains** can form:

```
~/.claude/skills → ~/.dotfiles/.agents/skills
~/.dotfiles/.agents/skills → ~/.agents/skills           ← loop!
~/.agents/skills → ~/.dotfiles/.agents/skills            ← loop!
```

Result: `Too many levels of symbolic links`, empty skill list, or agent crash.

## The Fix

**One level of symlink only.** Each agent's skills directory must point directly to the real source directory — never through an intermediate symlink:

```bash
# ✅ CORRECT — direct symlink to source of truth
ln -sfn ~/.dotfiles/.agents/skills ~/.claude/skills
ln -sfn ~/.dotfiles/.agents/skills ~/.codex/skills
ln -sfn ~/.dotfiles/.agents/skills ~/.hermes/skills

# ❌ WRONG — chained symlinks that can loop
ln -sfn ~/.agents/skills ~/.dotfiles/.agents/skills   # don't do this
```

## Verification

```bash
# Check each path resolves to the same real directory
readlink ~/.claude/skills      # → ~/.dotfiles/.agents/skills
readlink ~/.dotfiles/.agents/skills   # → the real dir (NOT another symlink)

# If readlink fails with ELOOP (too many levels), you have a circular chain
```

## Agent Skill Paths

| Agent | Default skills path |
|-------|-------------------|
| Claude Code | `~/.claude/skills/` or `./.claude/skills/` |
| Codex | `~/.codex/skills/` or `./.codex/skills/` |
| OpenCode | `~/.opencode/skills/` or `./.opencode/skills/` |
| Hermes | `~/.hermes/skills/` |

## Root Cause

Circular symlinks typically happen when:
1. A setup bootstrap script creates bi-directional symlinks
2. A dotfiles installer creates `~/.agents/skills → dotfiles`, then a later pass creates `dotfiles/.agents/skills → ~/.agents/skills`
3. Manually editing links without checking existing targets first

## Prevention

Keep the source of truth in one place (e.g. `~/.dotfiles/.agents/skills/` with actual SKILL.md files). Every agent's skills directory is a **direct symlink** to that directory. No intermediate hops.
